USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Daily_Fee_Calculate
(
    @ActionType         INT,

    @p_ticketID         INT = NULL,
    @p_atUTC            DATETIME2(0) = NULL,
    @p_amount           DECIMAL(12,2) OUTPUT,
    @p_durationSeconds  BIGINT OUTPUT,
    @p_hourlyRateID     INT OUTPUT,
    @p_dailyRateID      INT OUTPUT,
    @p_hourlyRate       DECIMAL(12,2) OUTPUT,
    @p_dailyRate        DECIMAL(12,2) OUTPUT,
    @p_thresholdHours   INT OUTPUT,
    @p_uid              BIGINT = NULL,

    @ResultStatusCode   INT OUTPUT,
    @Result             VARCHAR(500) OUTPUT,
    @ExceptionMessage   VARCHAR(MAX) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        SET @ResultStatusCode = 0;
        SET @Result = '';
        SET @ExceptionMessage = '';

        SET @p_amount = NULL;
        SET @p_durationSeconds = NULL;
        SET @p_hourlyRateID = NULL;
        SET @p_dailyRateID = NULL;
        SET @p_hourlyRate = NULL;
        SET @p_dailyRate = NULL;
        SET @p_thresholdHours = NULL;

        /* ====================================================
           1. Validate inputs and caller
           ==================================================== */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType <> 1
            SET @ValidationMessage =
                'Invalid action type. Use 1 to calculate the daily fee.';
        ELSE IF @p_ticketID IS NULL OR @p_ticketID <= 0
            SET @ValidationMessage = 'A valid ticket ID is required.';
        ELSE IF @p_atUTC IS NULL
            SET @ValidationMessage = 'Calculation time is required.';
        ELSE IF @p_atUTC > SYSUTCDATETIME()
            SET @ValidationMessage =
                'Calculation time cannot be in the future.';
        ELSE IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER
            WHERE UserID = @p_uid
              AND ActiveStatus = 1
              AND UserRole IN ('A', 'O')
        )
            SET @ValidationMessage =
                'An active administrator or operator is required.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           2. Check the daily ticket
           ==================================================== */

        DECLARE
            @EntryDateTime DATETIME2(0),
            @VehicleTypeID INT,
            @TicketStatus VARCHAR(30),
            @ExitDateTime DATETIME2(0);

        SELECT
            @EntryDateTime = T.EntryDateTime,
            @VehicleTypeID = V.VehicleTypeID,
            @TicketStatus = T.TicketStatus,
            @ExitDateTime = T.ExitDateTime
        FROM dbo.PARKING_TICKET AS T
        INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS V
            ON V.VehicleID = T.VehicleID
        WHERE T.TicketID = @p_ticketID
          AND T.ParkingType = 'DAILY';

        IF @EntryDateTime IS NULL
            SET @ValidationMessage =
                'Daily parking ticket was not found.';
        ELSE IF @TicketStatus <> 'OPEN' OR @ExitDateTime IS NOT NULL
            SET @ValidationMessage =
                'Only an open unpaid daily ticket can be calculated.';
        ELSE IF EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_PAYMENT
            WHERE TicketID = @p_ticketID
        )
            SET @ValidationMessage =
                'This ticket already has a payment record.';
        ELSE IF @p_atUTC < @EntryDateTime
            SET @ValidationMessage =
                'Calculation time is earlier than entry.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           3. Read the billing threshold and effective rates
           ==================================================== */

        DECLARE
            @ThresholdHours INT,
            @HourlyRateID INT,
            @DailyRateID INT,
            @HourlyRate DECIMAL(12,2),
            @DailyRate DECIMAL(12,2),
            @HourlyCount INT,
            @DailyCount INT;

        SELECT @ThresholdHours = DailyThresholdHours
        FROM dbo.PARKING_APP_SETTINGS
        WHERE SettingsID = 1;

        IF @ThresholdHours IS NULL
           OR @ThresholdHours NOT BETWEEN 1 AND 24
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result =
                'A daily billing threshold between 1 and 24 hours is required.';
            RETURN;
        END;

        SELECT
            @HourlyRateID =
                MAX(CASE WHEN RateUnit = 'HOURLY' THEN RateID END),
            @DailyRateID =
                MAX(CASE WHEN RateUnit = 'DAILY' THEN RateID END),
            @HourlyRate =
                MAX(CASE WHEN RateUnit = 'HOURLY' THEN RateAmount END),
            @DailyRate =
                MAX(CASE WHEN RateUnit = 'DAILY' THEN RateAmount END),
            @HourlyCount =
                COUNT(CASE WHEN RateUnit = 'HOURLY' THEN 1 END),
            @DailyCount =
                COUNT(CASE WHEN RateUnit = 'DAILY' THEN 1 END)
        FROM dbo.PARKING_RATE
        WHERE VehicleTypeID = @VehicleTypeID
          AND RateUnit IN ('HOURLY', 'DAILY')
          AND ActiveStatus = 1
          AND EffectiveFrom <= @p_atUTC
          AND (EffectiveTo IS NULL OR EffectiveTo > @p_atUTC);

        IF @HourlyCount <> 1 OR @DailyCount <> 1
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result =
                'Exactly one effective hourly and daily rate is required.';
            RETURN;
        END;

        /* ====================================================
           4. Calculate the fee
           Each full 24 hours uses the daily rate.
           The remainder uses hourly billing below the threshold,
           otherwise one additional daily charge.
           ==================================================== */

        DECLARE @DurationSeconds BIGINT =
            DATEDIFF_BIG(SECOND, @EntryDateTime, @p_atUTC);

        DECLARE @FullDays BIGINT = @DurationSeconds / 86400;
        DECLARE @RemainingSeconds BIGINT = @DurationSeconds % 86400;

        DECLARE @Charge DECIMAL(28,6) =
            CONVERT(DECIMAL(10,0), @FullDays) * @DailyRate
            +
            CASE
                WHEN @RemainingSeconds < @ThresholdHours * 3600
                    THEN CONVERT(DECIMAL(10,0), @RemainingSeconds)
                         * @HourlyRate / 3600.0
                ELSE @DailyRate
            END;

        DECLARE @Amount DECIMAL(12,2) =
            TRY_CONVERT(DECIMAL(12,2), ROUND(@Charge, 2));

        IF @Amount IS NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result =
                'The calculated fee exceeds the supported amount range.';
            RETURN;
        END;

        -- Return calculation values only after all checks succeed.
        SET @p_amount = @Amount;
        SET @p_durationSeconds = @DurationSeconds;
        SET @p_hourlyRateID = @HourlyRateID;
        SET @p_dailyRateID = @DailyRateID;
        SET @p_hourlyRate = @HourlyRate;
        SET @p_dailyRate = @DailyRate;
        SET @p_thresholdHours = @ThresholdHours;

        SET @ResultStatusCode = 1;
        SET @Result = 'Daily parking fee calculated successfully';
    END TRY
    BEGIN CATCH
        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while calculating the daily parking fee';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO