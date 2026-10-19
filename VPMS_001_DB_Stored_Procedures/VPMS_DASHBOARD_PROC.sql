USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_DASHBOARD_PROC
    @ActionType INT,

    @p_parkingType VARCHAR(20) = 'ALL',
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
    DECLARE @LockResult INT;

    BEGIN TRY
        SET @ResultStatusCode = 1;
        SET @Result = 'Success';
        SET @ExceptionMessage = NULL;

        SET @p_parkingType = ISNULL(UPPER(NULLIF(LTRIM(RTRIM(@p_parkingType)), '')), 'ALL');
        SET @p_searchTerm = NULLIF(LTRIM(RTRIM(@p_searchTerm)), '');

        /** 1. Administrator dashboard summary **/
        IF @ActionType = 1
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
                @LockMode = N'Shared',
                @LockOwner = N'Transaction',
                @LockTimeout = 10000;

            IF @LockResult < 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Dashboard is busy. Please retry';
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

            DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
            DECLARE @Today DATE = CONVERT(DATE, DATEADD(MINUTE, 330, @Now));
            DECLARE @TodayStartUTC DATETIME2(0) = DATEADD(MINUTE, -330, CONVERT(DATETIME2(0), @Today));
            DECLARE @TomorrowStartUTC DATETIME2(0) = DATEADD(DAY, 1, @TodayStartUTC);

            ;WITH Spaces AS
            (
                SELECT
                    CASE
                        WHEN EXISTS
                        (
                            SELECT 1
                            FROM dbo.VPMS_PARKING_TICKET AS T
                            WHERE T.VPT_SPACE_ID = S.VPS_SPACE_ID
                              AND T.VPT_EXIT_DATE_TIME IS NULL
                              AND T.VPT_TICKET_STATUS IN ('O', 'PP')
                        ) THEN 'OC'
                        WHEN S.VPS_SPACE_STATUS = 'B' THEN 'B'
                        WHEN S.VPS_SPACE_STATUS = 'OC' THEN 'OC'
                        WHEN S.VPS_SPACE_STATUS = 'OP' THEN 'OP'
                        WHEN EXISTS
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
                              AND MC.VPM_START_DATE <= @Today
                              AND MC.VPM_END_DATE >= @Today
                              AND MP.VPP_PERIOD_START_DATE <= @Today
                              AND MP.VPP_PERIOD_END_DATE >= @Today
                              AND R.VPR_EFFECTIVE_FROM_UTC <= @Now
                              AND R.VPR_EFFECTIVE_TO_UTC > @Now
                        ) THEN 'RE'
                        ELSE 'AV'
                    END AS SpaceStatus
                FROM dbo.VPMS_PARKING_SPACE AS S
            )
            SELECT
                COUNT(*) AS TotalSpaces,
                COUNT(CASE WHEN SpaceStatus = 'OC' THEN 1 END) AS OccupiedSpaces,
                COUNT(CASE WHEN SpaceStatus = 'AV' THEN 1 END) AS AvailableSpaces,
                COUNT(CASE WHEN SpaceStatus = 'RE' THEN 1 END) AS ReservedSpaces,
                COUNT(CASE WHEN SpaceStatus = 'B' THEN 1 END) AS BlockedSpaces,
                COUNT(CASE WHEN SpaceStatus = 'OP' THEN 1 END) AS OtherSpaces,

                (
                    SELECT COUNT(*)
                    FROM dbo.VPMS_PARKING_TICKET
                    WHERE VPT_PARKING_TYPE = 'D'
                      AND VPT_TICKET_STATUS <> 'CN'
                      AND VPT_ENTRY_DATE_TIME >= @TodayStartUTC
                      AND VPT_ENTRY_DATE_TIME < @TomorrowStartUTC
                ) AS TodayDailyVehicles,

                (
                    SELECT COUNT(*)
                    FROM dbo.VPMS_PARKING_TICKET
                    WHERE VPT_PARKING_TYPE = 'M'
                      AND VPT_TICKET_STATUS <> 'CN'
                      AND VPT_ENTRY_DATE_TIME >= @TodayStartUTC
                      AND VPT_ENTRY_DATE_TIME < @TomorrowStartUTC
                ) AS TodayMonthlyVehicles,

                (
                    SELECT ISNULL(SUM(VPP_AMOUNT), 0)
                    FROM dbo.VPMS_PARKING_PAYMENT
                    WHERE VPP_PAYMENT_STATUS = 'C'
                      AND VPP_PAYMENT_DATE_TIME >= @TodayStartUTC
                      AND VPP_PAYMENT_DATE_TIME < @TomorrowStartUTC
                ) AS TodayDailyRevenue,

                (
                    SELECT ISNULL(SUM(VPP_AMOUNT), 0)
                    FROM dbo.VPMS_MONTHLY_PAYMENT
                    WHERE VPP_PAYMENT_STATUS = 'C'
                      AND VPP_PAYMENT_DATE >= @TodayStartUTC
                      AND VPP_PAYMENT_DATE < @TomorrowStartUTC
                ) AS TodayMonthlyRevenue,

                (
                    SELECT COUNT(*)
                    FROM dbo.VPMS_PARKING_TICKET
                    WHERE VPT_EXIT_DATE_TIME IS NULL
                      AND VPT_TICKET_STATUS IN ('O', 'PP')
                ) AS CurrentlyParkedVehicles,

                @Today AS BusinessDate,
                @Now AS UpdatedAtUTC
            FROM Spaces;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SET @Result = 'Dashboard summary retrieved successfully';
        END

        /** 2. Currently parked vehicles **/
        ELSE IF @ActionType = 2
        BEGIN
            DECLARE @SearchAction INT =
                CASE WHEN @p_searchTerm IS NULL THEN 1 ELSE 2 END;

            EXEC dbo.VPMS_PARKING_TICKET_SEARCH_PROC
                @ActionType = @SearchAction,
                @p_searchTerm = @p_searchTerm,
                @p_parkingType = @p_parkingType,
                @p_onlyCurrent = 1,
                @p_uid = @p_uid,
                @ResultStatusCode = @ResultStatusCode OUTPUT,
                @Result = @Result OUTPUT,
                @ExceptionMessage = @ExceptionMessage OUTPUT;
        END

        /** 3. Parking space board **/
        ELSE IF @ActionType = 3
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
                @LockMode = N'Shared',
                @LockOwner = N'Transaction',
                @LockTimeout = 10000;

            IF @LockResult < 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Dashboard is busy. Please retry';
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
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An active user is required';
                RETURN;
            END;

            DECLARE @BoardNow DATETIME2(0) = SYSUTCDATETIME();
            DECLARE @BoardToday DATE = CONVERT(DATE, DATEADD(MINUTE, 330, @BoardNow));

            SELECT
                S.VPS_SPACE_ID AS SpaceID,
                S.VPS_SPACE_CODE AS SpaceCode,
                S.VPS_SPACE_NAME AS SpaceName,
                VT.VVT_TYPE_NAME AS VehicleType,
                VT.VVT_WHEEL_COUNT AS WheelCount,
                CASE
                    WHEN T.VPT_TICKET_ID IS NOT NULL THEN 'OC'
                    WHEN S.VPS_SPACE_STATUS = 'B' THEN 'B'
                    WHEN S.VPS_SPACE_STATUS = 'OC' THEN 'OC'
                    WHEN S.VPS_SPACE_STATUS = 'OP' THEN 'OP'
                    WHEN EXISTS
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
                          AND MC.VPM_START_DATE <= @BoardToday
                          AND MC.VPM_END_DATE >= @BoardToday
                          AND MP.VPP_PERIOD_START_DATE <= @BoardToday
                          AND MP.VPP_PERIOD_END_DATE >= @BoardToday
                          AND R.VPR_EFFECTIVE_FROM_UTC <= @BoardNow
                          AND R.VPR_EFFECTIVE_TO_UTC > @BoardNow
                    ) THEN 'RE'
                    ELSE 'AV'
                END AS SpaceStatus,
                S.VPS_BLOCK_REASON AS BlockReason,
                T.VPT_TICKET_NUMBER AS TicketNumber,
                V.VPV_VEHICLE_NUMBER AS VehicleNumber,
                T.VPT_ENTRY_DATE_TIME AS EntryDateTime
            FROM dbo.VPMS_PARKING_SPACE AS S
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = S.VPS_VEHICLE_TYPE_ID
            LEFT JOIN dbo.VPMS_PARKING_TICKET AS T
                ON T.VPT_SPACE_ID = S.VPS_SPACE_ID
               AND T.VPT_EXIT_DATE_TIME IS NULL
               AND T.VPT_TICKET_STATUS IN ('O', 'PP')
            LEFT JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                ON V.VPV_VEHICLE_ID = T.VPT_VEHICLE_ID
            ORDER BY S.VPS_SPACE_CODE, S.VPS_SPACE_ID;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SET @Result = 'Parking space board retrieved successfully';
        END

        /** Invalid action **/
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