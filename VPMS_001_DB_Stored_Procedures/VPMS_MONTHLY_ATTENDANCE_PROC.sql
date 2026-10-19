USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_MONTHLY_ATTENDANCE_PROC
    @ActionType INT,

    @p_vehicleNumber VARCHAR(30) = NULL,
    @p_uid INT = NULL,

    @ResultStatusCode INT OUTPUT,
    @Result VARCHAR(MAX) OUTPUT,
    @ExceptionMessage VARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @LockResult INT;

    BEGIN TRY
        SET @ResultStatusCode = 1;
        SET @Result = 'Success';
        SET @ExceptionMessage = NULL;

        SET @p_vehicleNumber = UPPER(NULLIF(LTRIM(RTRIM(@p_vehicleNumber)), ''));

        /** 1. Check monthly entry eligibility **/
        IF @ActionType = 1
        BEGIN
            IF @p_vehicleNumber IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle number is required';
                RETURN;
            END;

            IF @@TRANCOUNT > 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Call this action without an existing transaction';
                RETURN;
            END;

            BEGIN TRANSACTION;
            SET @StartedTransaction = 1;

            EXEC @LockResult = sys.sp_getapplock
                 @Resource = N'ParkingV2Configuration',
                 @LockMode = N'Shared',
                 @LockOwner = N'Transaction',
                 @LockTimeout = 10000;

            IF @LockResult < 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking management is busy. Please retry';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_USER_ROLE IN ('AD', 'OP')
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator or operator is required';
                RETURN;
            END;

            DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
            DECLARE @Today DATE = CONVERT(DATE, DATEADD(MINUTE, 330, @Now));
            DECLARE @CoverageCount INT;
            DECLARE @VehicleID VARCHAR(10);
            DECLARE @VehicleTypeID VARCHAR(10);
            DECLARE @ContractID INT;
            DECLARE @SpaceID VARCHAR(10);
            DECLARE @CustomerName VARCHAR(200);
            DECLARE @SpaceCode VARCHAR(30);
            DECLARE @SpaceStatus VARCHAR(20);
            DECLARE @CanEnter BIT = 1;

            SELECT
                @CoverageCount = COUNT(*),
                @VehicleID = MIN(V.VPV_VEHICLE_ID),
                @VehicleTypeID = MIN(V.VPV_VEHICLE_TYPE_ID),
                @ContractID = MIN(MC.VPM_CONTRACT_ID),
                @SpaceID = MIN(S.VPS_SPACE_ID),
                @CustomerName = MIN(C.VPC_CUSTOMER_NAME),
                @SpaceCode = MIN(S.VPS_SPACE_CODE),
                @SpaceStatus = MIN(S.VPS_SPACE_STATUS)
            FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
            INNER JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = V.VPV_CUSTOMER_ID
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = V.VPV_VEHICLE_TYPE_ID
            INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                ON MC.VPM_VEHICLE_ID = V.VPV_VEHICLE_ID
                AND MC.VPM_CUSTOMER_ID = V.VPV_CUSTOMER_ID
            INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                ON MP.VPP_CONTRACT_ID = MC.VPM_CONTRACT_ID
            INNER JOIN dbo.VPMS_MONTHLY_RESERVATION AS R
                ON R.VPR_MONTHLY_PAYMENT_ID = MP.VPP_MONTHLY_PAYMENT_ID
            INNER JOIN dbo.VPMS_PARKING_SPACE AS S
                ON S.VPS_SPACE_ID = R.VPR_SPACE_ID
                AND S.VPS_VEHICLE_TYPE_ID = V.VPV_VEHICLE_TYPE_ID
            WHERE V.VPV_VEHICLE_NUMBER = @p_vehicleNumber
				AND V.VPV_IS_ACTIVE = 'A'
				AND C.VPC_IS_ACTIVE = 'A'
				AND VT.VVT_IS_ACTIVE = 'A'
				AND MC.VPM_CONTRACT_STATUS = 'A'
				AND MC.VPM_START_DATE <= @Today
				AND MC.VPM_END_DATE >= @Today
				AND MP.VPP_PAYMENT_STATUS = 'C'
				AND MP.VPP_PERIOD_START_DATE <= @Today
				AND MP.VPP_PERIOD_END_DATE >= @Today
				AND R.VPR_IS_ACTIVE = 'A'
				AND R.VPR_EFFECTIVE_FROM_UTC <= @Now
				AND R.VPR_EFFECTIVE_TO_UTC > @Now;

            IF @CoverageCount <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = CASE
                        WHEN @CoverageCount = 0
                            THEN 'No valid paid monthly reservation was found'
                        ELSE 'Multiple current reservations exist. An administrator must resolve them'
                    END;
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_TICKET
                WHERE VPT_VEHICLE_ID = @VehicleID
                  AND VPT_EXIT_DATE_TIME IS NULL
            )
            BEGIN
                SET @CanEnter = 0;
                SET @Result = 'This vehicle already has an open parking ticket';
            END
            ELSE IF @SpaceStatus NOT IN ('AV', 'RE')
                 OR EXISTS
                 (
                     SELECT 1
                     FROM dbo.VPMS_PARKING_TICKET
                     WHERE VPT_SPACE_ID = @SpaceID
						AND VPT_EXIT_DATE_TIME IS NULL
                 )
            BEGIN
                SET @CanEnter = 0;
                SET @Result = 'The reserved space is not available for entry';
            END
            ELSE
            BEGIN
                SET @Result = 'Valid paid monthly reservation found';
            END;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SELECT
                @CanEnter AS CanEnter,
                @VehicleID AS VPV_VEHICLE_ID,
                @VehicleTypeID AS VPV_VEHICLE_TYPE_ID,
                @CustomerName AS CustomerName,
                @ContractID AS VPM_CONTRACT_ID,
                @SpaceID AS VPS_SPACE_ID,
                @SpaceCode AS VPS_SPACE_CODE;
        END

        /** 2. Reconcile monthly contracts, reservations and spaces **/
        ELSE IF @ActionType = 2
        BEGIN
            IF @@TRANCOUNT > 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Call this action without an existing transaction';
                RETURN;
            END;

            BEGIN TRANSACTION;
            SET @StartedTransaction = 1;

            EXEC @LockResult = sys.sp_getapplock
                 @Resource = N'ParkingV2Configuration',
                 @LockMode = N'Exclusive',
                 @LockOwner = N'Transaction',
                 @LockTimeout = 10000;

            IF @LockResult < 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking management is busy. Please retry';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_USER_ROLE = 'AD'
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator is required';
                RETURN;
            END;

            DECLARE @ReconcileNow DATETIME2(0) = SYSUTCDATETIME();
            DECLARE @ReconcileToday DATE = CONVERT(DATE, DATEADD(MINUTE, 330, @ReconcileNow));

            UPDATE dbo.VPMS_PARKING_MONTHLYCONTRACT
            SET VPM_CONTRACT_STATUS = 'E',
                VPM_UPDATED_BY = @p_uid,
                VPM_UPDATED_DATE = @ReconcileNow
            WHERE VPM_CONTRACT_STATUS = 'A'
              AND VPM_END_DATE < @ReconcileToday;

            DECLARE @ExpiredContracts INT = @@ROWCOUNT;

            UPDATE R
            SET VPR_IS_ACTIVE = 'I',
                VPR_UPDATED_BY = @p_uid,
                VPR_UPDATED_DATE = @ReconcileNow
            FROM dbo.VPMS_MONTHLY_RESERVATION AS R
            INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                ON MP.VPP_MONTHLY_PAYMENT_ID = R.VPR_MONTHLY_PAYMENT_ID
            INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                ON MC.VPM_CONTRACT_ID = MP.VPP_CONTRACT_ID
            WHERE R.VPR_IS_ACTIVE = 'A'
              AND
              (
                  R.VPR_EFFECTIVE_TO_UTC <= @ReconcileNow
                  OR MP.VPP_PAYMENT_STATUS <> 'C'
                  OR MC.VPM_CONTRACT_STATUS <> 'A'
                  OR MC.VPM_END_DATE < @ReconcileToday
              );

            DECLARE @ReleasedReservations INT = @@ROWCOUNT;

            /** Mark currently reserved spaces **/
            UPDATE S
            SET VPS_SPACE_STATUS = 'RE',
                VPS_UPDATED_BY = @p_uid,
                VPS_UPDATED_DATE = @ReconcileNow
            FROM dbo.VPMS_PARKING_SPACE AS S
            WHERE S.VPS_SPACE_STATUS = 'AV'
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.VPMS_PARKING_TICKET AS T
                  WHERE T.VPT_SPACE_ID = S.VPS_SPACE_ID
                    AND T.VPT_EXIT_DATE_TIME IS NULL
              )
              AND EXISTS
              (
                  SELECT 1
                  FROM dbo.VPMS_MONTHLY_RESERVATION AS R
                  INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                      ON MP.VPP_MONTHLY_PAYMENT_ID = R.VPR_MONTHLY_PAYMENT_ID
                  INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                      ON MC.VPM_CONTRACT_ID = MP.VPP_CONTRACT_ID
                  WHERE R.VPR_SPACE_ID = S.VPS_SPACE_ID
                    AND R.VPR_IS_ACTIVE = 'A'
                    AND MP.VPP_PAYMENT_STATUS = 'C'
                    AND MC.VPM_CONTRACT_STATUS = 'A'
                    AND MC.VPM_START_DATE <= @ReconcileToday
                    AND MC.VPM_END_DATE >= @ReconcileToday
                    AND MP.VPP_PERIOD_START_DATE <= @ReconcileToday
                    AND MP.VPP_PERIOD_END_DATE >= @ReconcileToday
                    AND R.VPR_EFFECTIVE_FROM_UTC <= @ReconcileNow
                    AND R.VPR_EFFECTIVE_TO_UTC > @ReconcileNow
              );

            DECLARE @UpdatedSpaces INT = @@ROWCOUNT;

            /** Release expired reservation markers **/
            UPDATE S
            SET VPS_SPACE_STATUS = 'AV',
                VPS_UPDATED_BY = @p_uid,
                VPS_UPDATED_DATE = @ReconcileNow
            FROM dbo.VPMS_PARKING_SPACE AS S
            WHERE S.VPS_SPACE_STATUS = 'RE'
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.VPMS_PARKING_TICKET AS T
                  WHERE T.VPT_SPACE_ID = S.VPS_SPACE_ID
                    AND T.VPT_EXIT_DATE_TIME IS NULL
              )
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.VPMS_MONTHLY_RESERVATION AS R
                  INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                      ON MP.VPP_MONTHLY_PAYMENT_ID = R.VPR_MONTHLY_PAYMENT_ID
                  INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                      ON MC.VPM_CONTRACT_ID = MP.VPP_CONTRACT_ID
                  WHERE R.VPR_SPACE_ID = S.VPS_SPACE_ID
                    AND R.VPR_IS_ACTIVE = 'A'
                    AND MP.VPP_PAYMENT_STATUS = 'C'
                    AND MC.VPM_CONTRACT_STATUS = 'A'
                    AND MC.VPM_START_DATE <= @ReconcileToday
                    AND MC.VPM_END_DATE >= @ReconcileToday
                    AND MP.VPP_PERIOD_START_DATE <= @ReconcileToday
                    AND MP.VPP_PERIOD_END_DATE >= @ReconcileToday
                    AND R.VPR_EFFECTIVE_FROM_UTC <= @ReconcileNow
                    AND R.VPR_EFFECTIVE_TO_UTC > @ReconcileNow
              );

            SET @UpdatedSpaces = @UpdatedSpaces + @@ROWCOUNT;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SET @Result = 'Monthly statuses reconciled successfully';

            SELECT
                @ExpiredContracts AS ExpiredContracts,
                @ReleasedReservations AS ReleasedReservations,
                @UpdatedSpaces AS UpdatedSpaces;
        END
        ELSE
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = 'Invalid action type';
        END;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result = 'Error occurred';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO