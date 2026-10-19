USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_PARKING_MONTHLYCONTRACT_PROC
    @ActionType INT,

    @p_contractID INT = NULL,
    @p_customerID INT = NULL,
    @p_vehicleID VARCHAR(10) = NULL,
    @p_monthlyFee DECIMAL(12,2) = NULL,
    @p_startDate DATE = NULL,
    @p_endDate DATE = NULL,
    @p_cancelledReason VARCHAR(500) = NULL,
    @p_searchTerm VARCHAR(200) = NULL,
    @p_uid INT = NULL,

    @ResultStatusCode INT OUTPUT,
    @Result VARCHAR(MAX) OUTPUT,
    @ExceptionMessage VARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @ReleaseReservations BIT = 0;
    DECLARE @LockResult INT;

    BEGIN TRY
        SET @ResultStatusCode = 1;
        SET @Result = 'Success';
        SET @ExceptionMessage = NULL;

        SET @p_vehicleID = NULLIF(LTRIM(RTRIM(@p_vehicleID)), '');
        SET @p_cancelledReason = NULLIF(LTRIM(RTRIM(@p_cancelledReason)), '');
        SET @p_searchTerm = NULLIF(LTRIM(RTRIM(@p_searchTerm)), '');

        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
        DECLARE @Today DATE = CONVERT(DATE, DATEADD(MINUTE, 330, @Now));
        DECLARE @ContractNumber VARCHAR(40);

        /** 1. Get monthly contracts **/
        IF @ActionType = 1
        BEGIN
            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An active user is required';
                RETURN;
            END;

            SELECT
                MC.VPM_CONTRACT_ID,
                MC.VPM_CONTRACT_NUMBER,
                MC.VPM_CUSTOMER_ID,
                C.VPC_CUSTOMER_NAME,
                C.VPC_MOBILE_NUMBER,
                MC.VPM_VEHICLE_ID,
                V.VPV_VEHICLE_NUMBER,
                V.VPV_VEHICLE_TYPE_ID,
                VT.VVT_TYPE_NAME,
                MC.VPM_MONTHLY_FEE,
                MC.VPM_START_DATE,
                MC.VPM_END_DATE,
                MC.VPM_CONTRACT_STATUS,
                CASE
                    WHEN MC.VPM_CONTRACT_STATUS = 'CN' THEN 'CN'
                    WHEN MC.VPM_CONTRACT_STATUS = 'E'
                         OR MC.VPM_END_DATE < @Today THEN 'E'
                    WHEN MC.VPM_START_DATE > @Today THEN 'U'
                    ELSE 'A'
                END AS EffectiveContractStatus,
                MC.VPM_CANCELLED_AT,
                MC.VPM_CANCELLED_REASON
            FROM dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
            INNER JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = MC.VPM_CUSTOMER_ID
            INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                ON V.VPV_VEHICLE_ID = MC.VPM_VEHICLE_ID
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = V.VPV_VEHICLE_TYPE_ID
            WHERE (@p_customerID IS NULL OR MC.VPM_CUSTOMER_ID = @p_customerID)
              AND (@p_vehicleID IS NULL OR MC.VPM_VEHICLE_ID = @p_vehicleID)
              AND
              (
                  @p_searchTerm IS NULL
                  OR CHARINDEX(@p_searchTerm, MC.VPM_CONTRACT_NUMBER) > 0
                  OR CHARINDEX(@p_searchTerm, C.VPC_CUSTOMER_NAME) > 0
                  OR CHARINDEX(@p_searchTerm, V.VPV_VEHICLE_NUMBER) > 0
                  OR CHARINDEX(@p_searchTerm, C.VPC_MOBILE_NUMBER) > 0
              )
            ORDER BY MC.VPM_START_DATE DESC, MC.VPM_CONTRACT_ID DESC;

            SET @Result = 'Monthly contract list retrieved successfully';
        END

        /** 2. Get monthly contract by ID **/
        ELSE IF @ActionType = 2
        BEGIN
            IF @p_contractID IS NULL OR @p_contractID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid contract ID is required';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An active user is required';
                RETURN;
            END;

            SELECT
                MC.VPM_CONTRACT_ID,
                MC.VPM_CONTRACT_NUMBER,
                MC.VPM_CUSTOMER_ID,
                C.VPC_CUSTOMER_NAME,
                C.VPC_MOBILE_NUMBER,
                MC.VPM_VEHICLE_ID,
                V.VPV_VEHICLE_NUMBER,
                V.VPV_VEHICLE_TYPE_ID,
                VT.VVT_TYPE_NAME,
                MC.VPM_MONTHLY_FEE,
                MC.VPM_START_DATE,
                MC.VPM_END_DATE,
                MC.VPM_CONTRACT_STATUS,
                CASE
                    WHEN MC.VPM_CONTRACT_STATUS = 'CN' THEN 'CN'
                    WHEN MC.VPM_CONTRACT_STATUS = 'E'
                         OR MC.VPM_END_DATE < @Today THEN 'E'
                    WHEN MC.VPM_START_DATE > @Today THEN 'U'
                    ELSE 'A'
                END AS EffectiveContractStatus,
                MC.VPM_CANCELLED_AT,
                MC.VPM_CANCELLED_REASON
            FROM dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
            INNER JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = MC.VPM_CUSTOMER_ID
            INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                ON V.VPV_VEHICLE_ID = MC.VPM_VEHICLE_ID
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = V.VPV_VEHICLE_TYPE_ID
            WHERE MC.VPM_CONTRACT_ID = @p_contractID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly contract was not found';
                RETURN;
            END;

            SET @Result = 'Monthly contract retrieved successfully';
        END

        /** 3. Add monthly contract **/
        ELSE IF @ActionType = 3
        BEGIN
            IF @p_customerID IS NULL OR @p_customerID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid customer ID is required';
                RETURN;
            END;

            IF @p_vehicleID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle ID is required';
                RETURN;
            END;

            IF @p_startDate IS NULL
               OR @p_endDate IS NULL
               OR @p_endDate < @p_startDate
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Valid contract start and end dates are required';
                RETURN;
            END;

            IF @p_monthlyFee < 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly fee cannot be negative';
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

            SET @Now = SYSUTCDATETIME();
            SET @Today = CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

            IF @p_endDate < @Today
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'A new contract cannot already have ended';
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

            DECLARE @VehicleTypeID VARCHAR(10);

            SELECT @VehicleTypeID = V.VPV_VEHICLE_TYPE_ID
            FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
            INNER JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = V.VPV_CUSTOMER_ID
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = V.VPV_VEHICLE_TYPE_ID
            WHERE V.VPV_VEHICLE_ID = @p_vehicleID
              AND V.VPV_CUSTOMER_ID = @p_customerID
              AND V.VPV_IS_ACTIVE = 'A'
              AND C.VPC_IS_ACTIVE = 'A'
              AND VT.VVT_IS_ACTIVE = 'A';

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An active vehicle belonging to the active customer and an active vehicle type are required';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
                WHERE VPM_VEHICLE_ID = @p_vehicleID
                  AND VPM_CONTRACT_STATUS = 'A'
                  AND VPM_END_DATE >= @Today
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'This vehicle already has an active or upcoming monthly contract';
                RETURN;
            END;

            IF @p_monthlyFee IS NULL
            BEGIN
                SELECT @p_monthlyFee = VPR_RATE_AMOUNT
                FROM dbo.VPMS_PARKING_RATE
                WHERE VPR_VEHICLE_TYPE_ID = @VehicleTypeID
                  AND VPR_RATE_UNIT = 'M'
                  AND VPR_IS_ACTIVE = 'A'
                  AND VPR_EFFECTIVE_FROM <= @Now
                  AND (VPR_EFFECTIVE_TO IS NULL OR VPR_EFFECTIVE_TO > @Now);

                IF @p_monthlyFee IS NULL
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @StartedTransaction = 0;
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Provide a monthly fee or configure an effective monthly rate';
                    RETURN;
                END;
            END;

            IF @p_monthlyFee < 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly fee cannot be negative';
                RETURN;
            END;

            UPDATE dbo.VPMS_PARKING_MONTHLYCONTRACT
            SET VPM_CONTRACT_STATUS = 'E',
                VPM_UPDATED_BY = @p_uid,
                VPM_UPDATED_DATE = @Now
            WHERE VPM_VEHICLE_ID = @p_vehicleID
              AND VPM_CONTRACT_STATUS = 'A'
              AND VPM_END_DATE < @Today;

            DECLARE @ContractSequence BIGINT =
                NEXT VALUE FOR dbo.VPMS_PARKING_MONTHLYCONTRACT_SEQUENCE;

            SET @ContractNumber = 'MC-' + CONVERT(VARCHAR(20), @ContractSequence);

            INSERT INTO dbo.VPMS_PARKING_MONTHLYCONTRACT
            (
                VPM_CONTRACT_NUMBER,
                VPM_CUSTOMER_ID,
                VPM_VEHICLE_ID,
                VPM_MONTHLY_FEE,
                VPM_START_DATE,
                VPM_END_DATE,
                VPM_CONTRACT_STATUS,
                VPM_CREATED_BY,
                VPM_CREATED_DATE
            )
            VALUES
            (
                @ContractNumber,
                @p_customerID,
                @p_vehicleID,
                @p_monthlyFee,
                @p_startDate,
                @p_endDate,
                'A',
                @p_uid,
                @Now
            );

            SET @p_contractID = CONVERT(INT, SCOPE_IDENTITY());
            SET @Result = 'Monthly contract added successfully. Payment is still required';
        END

        /** 4. Update unused monthly contract **/
        ELSE IF @ActionType = 4
        BEGIN
            IF @p_contractID IS NULL OR @p_contractID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid contract ID is required';
                RETURN;
            END;

            IF @p_startDate IS NULL
               OR @p_endDate IS NULL
               OR @p_endDate < @p_startDate
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Valid contract start and end dates are required';
                RETURN;
            END;

            IF @p_monthlyFee IS NULL OR @p_monthlyFee < 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A monthly fee of zero or greater is required';
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

            SET @Now = SYSUTCDATETIME();
            SET @Today = CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

            IF @p_endDate < @Today
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'The updated contract cannot already have ended';
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

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
                WHERE VPM_CONTRACT_ID = @p_contractID
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly contract was not found';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
                WHERE VPM_CONTRACT_ID = @p_contractID
                  AND VPM_CONTRACT_STATUS = 'A'
                  AND VPM_END_DATE >= @Today
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Only an active or upcoming contract can be edited';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_MONTHLY_PAYMENT
                WHERE VPP_CONTRACT_ID = @p_contractID
            )
            OR EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_TICKET
                WHERE VPT_MONTHLY_CONTRACT_ID = @p_contractID
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'A contract with payment or parking history cannot be edited';
                RETURN;
            END;

            UPDATE dbo.VPMS_PARKING_MONTHLYCONTRACT
            SET VPM_MONTHLY_FEE = @p_monthlyFee,
                VPM_START_DATE = @p_startDate,
                VPM_END_DATE = @p_endDate,
                VPM_UPDATED_BY = @p_uid,
                VPM_UPDATED_DATE = @Now
            WHERE VPM_CONTRACT_ID = @p_contractID
              AND VPM_CONTRACT_STATUS = 'A'
              AND VPM_END_DATE >= @Today;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly contract is no longer available for editing';
                RETURN;
            END;

            SELECT @ContractNumber = VPM_CONTRACT_NUMBER
            FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
            WHERE VPM_CONTRACT_ID = @p_contractID;

            SET @Result = 'Monthly contract updated successfully';
        END

        /** 5. Cancel monthly contract **/
        ELSE IF @ActionType = 5
        BEGIN
            IF @p_contractID IS NULL OR @p_contractID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid contract ID is required';
                RETURN;
            END;

            IF @p_cancelledReason IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A cancellation reason is required';
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

            SET @Now = SYSUTCDATETIME();
            SET @Today = CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

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

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
                WHERE VPM_CONTRACT_ID = @p_contractID
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly contract was not found';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
                WHERE VPM_CONTRACT_ID = @p_contractID
                  AND VPM_CONTRACT_STATUS = 'A'
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Only a contract with status A can be cancelled';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_TICKET
                WHERE VPT_MONTHLY_CONTRACT_ID = @p_contractID
                  AND VPT_EXIT_DATE_TIME IS NULL
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Complete the vehicle exit before cancelling its contract';
                RETURN;
            END;

            UPDATE dbo.VPMS_PARKING_MONTHLYCONTRACT
            SET VPM_CONTRACT_STATUS = 'CN',
                VPM_CANCELLED_AT = @Now,
                VPM_CANCELLED_REASON = @p_cancelledReason,
                VPM_UPDATED_BY = @p_uid,
                VPM_UPDATED_DATE = @Now
            WHERE VPM_CONTRACT_ID = @p_contractID
              AND VPM_CONTRACT_STATUS = 'A';

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly contract is no longer available for cancellation';
                RETURN;
            END;

            SELECT @ContractNumber = VPM_CONTRACT_NUMBER
            FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
            WHERE VPM_CONTRACT_ID = @p_contractID;

            SET @ReleaseReservations = 1;
            SET @Result = 'Monthly contract cancelled successfully. Payment history is retained';
        END

        /** 6. Expire ended monthly contract **/
        ELSE IF @ActionType = 6
        BEGIN
            IF @p_contractID IS NULL OR @p_contractID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid contract ID is required';
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

            SET @Now = SYSUTCDATETIME();
            SET @Today = CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

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

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
                WHERE VPM_CONTRACT_ID = @p_contractID
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly contract was not found';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
                WHERE VPM_CONTRACT_ID = @p_contractID
                  AND VPM_CONTRACT_STATUS = 'CN'
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'A cancelled contract cannot be expired';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
                WHERE VPM_CONTRACT_ID = @p_contractID
                  AND VPM_END_DATE >= @Today
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'The contract period has not ended';
                RETURN;
            END;

            UPDATE dbo.VPMS_PARKING_MONTHLYCONTRACT
            SET VPM_CONTRACT_STATUS = 'E',
                VPM_UPDATED_BY = @p_uid,
                VPM_UPDATED_DATE = @Now
            WHERE VPM_CONTRACT_ID = @p_contractID
              AND VPM_CONTRACT_STATUS <> 'CN'
              AND VPM_END_DATE < @Today;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly contract is no longer available for expiry';
                RETURN;
            END;

            SELECT @ContractNumber = VPM_CONTRACT_NUMBER
            FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
            WHERE VPM_CONTRACT_ID = @p_contractID;

            SET @ReleaseReservations = 1;
            SET @Result = 'Monthly contract marked expired successfully';
        END

        /** Invalid action **/
        ELSE
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = 'Invalid action type';
            RETURN;
        END;

        /** Release reservations after cancellation or expiry **/
        IF @ReleaseReservations = 1
        BEGIN
            UPDATE R
            SET VPR_IS_ACTIVE = 'I',
                VPR_UPDATED_BY = @p_uid,
                VPR_UPDATED_DATE = @Now
            FROM dbo.VPMS_MONTHLY_RESERVATION AS R
            INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                ON MP.VPP_MONTHLY_PAYMENT_ID = R.VPR_MONTHLY_PAYMENT_ID
            WHERE MP.VPP_CONTRACT_ID = @p_contractID
              AND R.VPR_IS_ACTIVE = 'A';

            UPDATE S
            SET VPS_SPACE_STATUS = 'AV',
                VPS_UPDATED_BY = @p_uid,
                VPS_UPDATED_DATE = @Now
            FROM dbo.VPMS_PARKING_SPACE AS S
            WHERE S.VPS_SPACE_STATUS = 'RE'
              AND EXISTS
              (
                  SELECT 1
                  FROM dbo.VPMS_MONTHLY_RESERVATION AS R
                  INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                      ON MP.VPP_MONTHLY_PAYMENT_ID = R.VPR_MONTHLY_PAYMENT_ID
                  WHERE R.VPR_SPACE_ID = S.VPS_SPACE_ID
                    AND MP.VPP_CONTRACT_ID = @p_contractID
              )
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
                    AND R.VPR_EFFECTIVE_TO_UTC > @Now
                    AND MP.VPP_PAYMENT_STATUS = 'C'
                    AND MC.VPM_CONTRACT_STATUS = 'A'
                    AND MC.VPM_END_DATE >= @Today
              );
        END;

        IF @StartedTransaction = 1
        BEGIN
            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;
        END;

        IF @ContractNumber IS NOT NULL
        BEGIN
            SELECT
                @p_contractID AS VPM_CONTRACT_ID,
                @ContractNumber AS VPM_CONTRACT_NUMBER;
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