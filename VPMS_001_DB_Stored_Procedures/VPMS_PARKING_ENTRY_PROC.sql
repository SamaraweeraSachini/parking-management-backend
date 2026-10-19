USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_PARKING_ENTRY_PROC
    @ActionType INT,

    @p_parkingType VARCHAR(20) = NULL,
    @p_vehicleID VARCHAR(10) = NULL,
    @p_vehicleNumber VARCHAR(30) = NULL,
    @p_vehicleTypeID VARCHAR(10) = NULL,
    @p_spaceID VARCHAR(10) = NULL,
    @p_customerName VARCHAR(200) = NULL,
    @p_mobileNumber VARCHAR(20) = NULL,
    @p_entryDescription VARCHAR(500) = NULL,
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

        SET @p_parkingType = UPPER(NULLIF(LTRIM(RTRIM(@p_parkingType)), ''));
        SET @p_vehicleID = NULLIF(LTRIM(RTRIM(@p_vehicleID)), '');
        SET @p_vehicleNumber = UPPER(NULLIF(LTRIM(RTRIM(@p_vehicleNumber)), ''));
        SET @p_vehicleTypeID = NULLIF(LTRIM(RTRIM(@p_vehicleTypeID)), '');
        SET @p_spaceID = NULLIF(LTRIM(RTRIM(@p_spaceID)), '');
        SET @p_customerName = NULLIF(LTRIM(RTRIM(@p_customerName)), '');
        SET @p_mobileNumber = NULLIF(LTRIM(RTRIM(@p_mobileNumber)), '');
        SET @p_entryDescription = NULLIF(LTRIM(RTRIM(@p_entryDescription)), '');

        /** 1. Register daily or monthly vehicle entry **/
        IF @ActionType = 1
        BEGIN
            IF @p_parkingType IS NULL
               OR @p_parkingType NOT IN ('D', 'M')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking type must be D - Daily / M - Monthly';
                RETURN;
            END;

            IF @p_vehicleNumber IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle number is required';
                RETURN;
            END;

            IF @p_vehicleTypeID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type ID is required';
                RETURN;
            END;

            IF @p_mobileNumber IS NOT NULL
            BEGIN
                IF DATALENGTH(@p_mobileNumber) <> 10
                   OR @p_mobileNumber COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9]%'
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Mobile number must contain exactly 10 digits';
                    RETURN;
                END;
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

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_VEHICLE_TYPE
                WHERE VVT_VEHICLE_TYPE_ID = @p_vehicleTypeID
                  AND VVT_IS_ACTIVE = 'A'
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Active vehicle type was not found';
                RETURN;
            END;

            DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
            DECLARE @Today DATE = CONVERT(DATE, DATEADD(MINUTE, 330, @Now));
            DECLARE @VehicleID VARCHAR(10);
            DECLARE @StoredTypeID VARCHAR(10);
            DECLARE @VehicleStatus CHAR(1);
            DECLARE @ContractID INT;
            DECLARE @SelectedSpaceID VARCHAR(10);
            DECLARE @HourlyRateID VARCHAR(10);
            DECLARE @DailyRateID VARCHAR(10);
            DECLARE @HourlyRate DECIMAL(12,2);
            DECLARE @DailyRate DECIMAL(12,2);
            DECLARE @DailyThresholdHours INT;

            /** Check existing vehicle **/
            SELECT
                @VehicleID = VPV_VEHICLE_ID,
                @StoredTypeID = VPV_VEHICLE_TYPE_ID,
                @VehicleStatus = VPV_IS_ACTIVE
            FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE
            WHERE VPV_VEHICLE_NUMBER = @p_vehicleNumber;

            IF @VehicleID IS NOT NULL
            BEGIN
                IF @VehicleStatus <> 'A'
                   OR @StoredTypeID <> @p_vehicleTypeID
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @StartedTransaction = 0;
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Existing vehicle is inactive or belongs to another vehicle type';
                    RETURN;
                END;

                IF @p_vehicleID IS NOT NULL AND @p_vehicleID <> @VehicleID
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @StartedTransaction = 0;
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Vehicle ID does not match the registered vehicle number';
                    RETURN;
                END;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_TICKET
                WHERE VPT_VEHICLE_ID = @VehicleID
                  AND VPT_EXIT_DATE_TIME IS NULL
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'This vehicle already has an open parking ticket';
                RETURN;
            END;

            /** Daily parking checks **/
            IF @p_parkingType = 'D'
            BEGIN
                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                    INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                        ON MP.VPP_CONTRACT_ID = MC.VPM_CONTRACT_ID
                    INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                        ON V.VPV_VEHICLE_ID = MC.VPM_VEHICLE_ID
                       AND V.VPV_CUSTOMER_ID = MC.VPM_CUSTOMER_ID
                    INNER JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                        ON C.VPC_CUSTOMER_ID = MC.VPM_CUSTOMER_ID
                    WHERE MC.VPM_VEHICLE_ID = @VehicleID
                      AND MC.VPM_CONTRACT_STATUS = 'A'
                      AND MC.VPM_START_DATE <= @Today
                      AND MC.VPM_END_DATE >= @Today
                      AND C.VPC_IS_ACTIVE = 'A'
                      AND MP.VPP_PAYMENT_STATUS = 'C'
                      AND MP.VPP_PERIOD_START_DATE <= @Today
                      AND MP.VPP_PERIOD_END_DATE >= @Today
                )
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @StartedTransaction = 0;
                    SET @ResultStatusCode = -1;
                    SET @Result = 'This vehicle has valid paid monthly coverage. Use monthly entry';
                    RETURN;
                END;

                IF @VehicleID IS NULL
                BEGIN
                    IF @p_vehicleID IS NULL
                    BEGIN
                        ROLLBACK TRANSACTION;
                        SET @StartedTransaction = 0;
                        SET @ResultStatusCode = -1;
                        SET @Result = 'A new vehicle ID is required for an unregistered vehicle';
                        RETURN;
                    END;

                    IF EXISTS
                    (
                        SELECT 1
                        FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE
                        WHERE VPV_VEHICLE_ID = @p_vehicleID
                    )
                    BEGIN
                        ROLLBACK TRANSACTION;
                        SET @StartedTransaction = 0;
                        SET @ResultStatusCode = -1;
                        SET @Result = 'Vehicle ID already belongs to another vehicle';
                        RETURN;
                    END;
                END;

                /** Find effective hourly and daily rates **/
                SELECT
                    @HourlyRateID = VPR_RATE_ID,
                    @HourlyRate = VPR_RATE_AMOUNT
                FROM dbo.VPMS_PARKING_RATE
                WHERE VPR_VEHICLE_TYPE_ID = @p_vehicleTypeID
                  AND VPR_RATE_UNIT = 'H'
                  AND VPR_IS_ACTIVE = 'A'
                  AND VPR_EFFECTIVE_FROM <= @Now
                  AND (VPR_EFFECTIVE_TO IS NULL OR VPR_EFFECTIVE_TO > @Now);

                SELECT
                    @DailyRateID = VPR_RATE_ID,
                    @DailyRate = VPR_RATE_AMOUNT
                FROM dbo.VPMS_PARKING_RATE
                WHERE VPR_VEHICLE_TYPE_ID = @p_vehicleTypeID
                  AND VPR_RATE_UNIT = 'D'
                  AND VPR_IS_ACTIVE = 'A'
                  AND VPR_EFFECTIVE_FROM <= @Now
                  AND (VPR_EFFECTIVE_TO IS NULL OR VPR_EFFECTIVE_TO > @Now);

                IF @HourlyRateID IS NULL
                   OR @DailyRateID IS NULL
                   OR @HourlyRate IS NULL
                   OR @DailyRate IS NULL
                   OR @HourlyRate < 0
                   OR @DailyRate < 0
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @StartedTransaction = 0;
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Configure valid effective hourly and daily rates first';
                    RETURN;
                END;

                SELECT @DailyThresholdHours = VPS_DAILY_THRESHOLD_HOURS
                FROM dbo.VPMS_APP_SETTINGS
                WHERE VPS_SETTINGS_ID = 1
                  AND VPS_IS_ACTIVE = 'A';

                IF @DailyThresholdHours IS NULL
                   OR @DailyThresholdHours NOT BETWEEN 1 AND 24
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @StartedTransaction = 0;
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Configure active parking settings with a valid daily threshold';
                    RETURN;
                END;

                /** Find an available daily space **/
                SELECT TOP (1)
                    @SelectedSpaceID = S.VPS_SPACE_ID
                FROM dbo.VPMS_PARKING_SPACE AS S
                WHERE S.VPS_VEHICLE_TYPE_ID = @p_vehicleTypeID
                  AND S.VPS_SPACE_STATUS = 'AV'
                  AND (@p_spaceID IS NULL OR S.VPS_SPACE_ID = @p_spaceID)
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
                  )
                ORDER BY S.VPS_SPACE_CODE, S.VPS_SPACE_ID;

                IF @SelectedSpaceID IS NULL
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @StartedTransaction = 0;
                    SET @ResultStatusCode = -1;
                    SET @Result = 'No compatible available space without a current or future monthly reservation was found';
                    RETURN;
                END;
            END

            /** Monthly parking checks **/
            ELSE IF @p_parkingType = 'M'
            BEGIN
                IF @VehicleID IS NULL
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @StartedTransaction = 0;
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Register the customer, vehicle and monthly contract before monthly entry';
                    RETURN;
                END;

                /** Find valid paid coverage and its reserved space **/
                SELECT TOP (1)
                    @ContractID = MC.VPM_CONTRACT_ID,
                    @SelectedSpaceID = S.VPS_SPACE_ID
                FROM dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                    ON MP.VPP_CONTRACT_ID = MC.VPM_CONTRACT_ID
                INNER JOIN dbo.VPMS_MONTHLY_RESERVATION AS R
                    ON R.VPR_MONTHLY_PAYMENT_ID = MP.VPP_MONTHLY_PAYMENT_ID
                INNER JOIN dbo.VPMS_PARKING_SPACE AS S
                    ON S.VPS_SPACE_ID = R.VPR_SPACE_ID
                INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                    ON V.VPV_VEHICLE_ID = MC.VPM_VEHICLE_ID
                   AND V.VPV_CUSTOMER_ID = MC.VPM_CUSTOMER_ID
                INNER JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                    ON C.VPC_CUSTOMER_ID = MC.VPM_CUSTOMER_ID
                WHERE MC.VPM_VEHICLE_ID = @VehicleID
                  AND MC.VPM_CONTRACT_STATUS = 'A'
                  AND MC.VPM_START_DATE <= @Today
                  AND MC.VPM_END_DATE >= @Today
                  AND C.VPC_IS_ACTIVE = 'A'
                  AND MP.VPP_PAYMENT_STATUS = 'C'
                  AND MP.VPP_PERIOD_START_DATE <= @Today
                  AND MP.VPP_PERIOD_END_DATE >= @Today
                  AND R.VPR_IS_ACTIVE = 'A'
                  AND R.VPR_EFFECTIVE_FROM_UTC <= @Now
                  AND R.VPR_EFFECTIVE_TO_UTC > @Now
                  AND S.VPS_VEHICLE_TYPE_ID = @p_vehicleTypeID
                  AND S.VPS_SPACE_STATUS IN ('AV', 'RE')
                  AND (@p_spaceID IS NULL OR S.VPS_SPACE_ID = @p_spaceID)
                  AND NOT EXISTS
                  (
                      SELECT 1
                      FROM dbo.VPMS_PARKING_TICKET AS T
                      WHERE T.VPT_SPACE_ID = S.VPS_SPACE_ID
                        AND T.VPT_EXIT_DATE_TIME IS NULL
                  )
                ORDER BY MC.VPM_CONTRACT_ID, R.VPR_RESERVATION_ID;

                IF @SelectedSpaceID IS NULL
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @StartedTransaction = 0;
                    SET @ResultStatusCode = -1;
                    SET @Result = 'No valid paid monthly coverage with an available reserved space was found';
                    RETURN;
                END;
            END;

            /** Register a new daily vehicle when required **/
            IF @VehicleID IS NULL
            BEGIN
                INSERT INTO dbo.VPMS_PARKINGCUSTOMER_VEHICLE
                (
                    VPV_VEHICLE_ID,
                    VPV_VEHICLE_TYPE_ID,
                    VPV_VEHICLE_NUMBER,
                    VPV_IS_ACTIVE,
                    VPV_CREATED_BY,
                    VPV_CREATED_DATE
                )
                VALUES
                (
                    @p_vehicleID,
                    @p_vehicleTypeID,
                    @p_vehicleNumber,
                    'A',
                    @p_uid,
                    @Now
                );

                SET @VehicleID = @p_vehicleID;
            END;

            SET @p_spaceID = @SelectedSpaceID;

            /** Use registered contact details when not supplied **/
            SELECT
                @p_customerName = COALESCE(@p_customerName, C.VPC_CUSTOMER_NAME),
                @p_mobileNumber = COALESCE(@p_mobileNumber, C.VPC_MOBILE_NUMBER)
            FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
            LEFT JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = V.VPV_CUSTOMER_ID
            WHERE V.VPV_VEHICLE_ID = @VehicleID;

            SET @p_mobileNumber = NULLIF(LTRIM(RTRIM(@p_mobileNumber)), '');

            IF @p_mobileNumber IS NOT NULL
            BEGIN
                IF DATALENGTH(@p_mobileNumber) <> 10
                   OR @p_mobileNumber COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9]%'
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @StartedTransaction = 0;
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Registered mobile number must contain exactly 10 digits';
                    RETURN;
                END;
            END;

            /** Generate parking ticket **/
            DECLARE @TicketSequence BIGINT =
                NEXT VALUE FOR dbo.VPMS_PARKING_TICKET_SEQUENCE;

            DECLARE @TicketNumber VARCHAR(40) =
                @p_parkingType + '-' + CONVERT(VARCHAR(20), @TicketSequence);

            INSERT INTO dbo.VPMS_PARKING_TICKET
            (
                VPT_TICKET_NUMBER,
                VPT_VEHICLE_ID,
                VPT_SPACE_ID,
                VPT_PARKING_TYPE,
                VPT_MONTHLY_CONTRACT_ID,
                VPT_HOURLY_RATE_ID,
                VPT_DAILY_RATE_ID,
                VPT_APPLIED_HOURLY_RATE,
                VPT_APPLIED_DAILY_RATE,
                VPT_CUSTOMER_NAME,
                VPT_MOBILE_NUMBER,
                VPT_ENTRY_DESCRIPTION,
                VPT_ENTRY_DATE_TIME,
                VPT_APPLIED_DAILY_THRESHOLD_HOURS,
                VPT_TICKET_STATUS,
                VPT_ENTRY_OPERATOR_ID,
                VPT_CREATED_BY,
                VPT_CREATED_DATE
            )
            VALUES
            (
                @TicketNumber,
                @VehicleID,
                @p_spaceID,
                @p_parkingType,
                @ContractID,
                @HourlyRateID,
                @DailyRateID,
                @HourlyRate,
                @DailyRate,
                @p_customerName,
                @p_mobileNumber,
                @p_entryDescription,
                @Now,
                @DailyThresholdHours,
                'O',
                @p_uid,
                @p_uid,
                @Now
            );

            DECLARE @TicketID INT = CONVERT(INT, SCOPE_IDENTITY());

            /** Mark the allocated space occupied **/
            UPDATE dbo.VPMS_PARKING_SPACE
            SET VPS_SPACE_STATUS = 'OC',
                VPS_BLOCK_REASON = NULL,
                VPS_UPDATED_BY = @p_uid,
                VPS_UPDATED_DATE = @Now
            WHERE VPS_SPACE_ID = @p_spaceID
              AND VPS_VEHICLE_TYPE_ID = @p_vehicleTypeID
              AND VPS_SPACE_STATUS IN ('AV', 'RE');

            IF @@ROWCOUNT <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Could not allocate the parking space';
                RETURN;
            END;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SET @Result =
                CASE
                    WHEN @p_parkingType = 'D'
                        THEN 'Daily vehicle entered successfully'
                    ELSE 'Monthly vehicle entered successfully'
                END;

            SELECT
                @TicketID AS VPT_TICKET_ID,
                @TicketNumber AS VPT_TICKET_NUMBER,
                @VehicleID AS VPT_VEHICLE_ID,
                @p_spaceID AS VPT_SPACE_ID,
                @p_parkingType AS VPT_PARKING_TYPE,
                @Now AS VPT_ENTRY_DATE_TIME;
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