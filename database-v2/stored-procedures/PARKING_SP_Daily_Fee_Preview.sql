USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Daily_Fee_Preview
(
    @ActionType         INT,

    @p_ticketID         INT = NULL,
    @p_uid              BIGINT = NULL,

    @ResultStatusCode   INT OUTPUT,
    @Result             VARCHAR(500) OUTPUT,
    @ExceptionMessage   VARCHAR(MAX) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;

    BEGIN TRY
        SET @ResultStatusCode = 0;
        SET @Result = '';
        SET @ExceptionMessage = '';

        /* ====================================================
           1. Validate inputs
           ==================================================== */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType <> 1
            SET @ValidationMessage =
                'Invalid action type. Use 1 to preview the daily fee.';
        ELSE IF @p_ticketID IS NULL OR @p_ticketID <= 0
            SET @ValidationMessage = 'A valid ticket ID is required.';
        ELSE IF @@TRANCOUNT <> 0
            SET @ValidationMessage =
                'Call this procedure without an existing transaction.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           2. Lock parking operations and validate access
           ==================================================== */

        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;

        DECLARE @LockResult INT;

        EXEC @LockResult = sys.sp_getapplock
            @Resource = N'ParkingV2Configuration',
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 10000;

        IF @LockResult < 0
            SET @ValidationMessage =
                'Parking operations are busy. Please retry.';
        ELSE IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER WITH (HOLDLOCK)
            WHERE UserID = @p_uid
              AND ActiveStatus = 1
              AND UserRole IN ('A', 'O')
        )
            SET @ValidationMessage =
                'An active administrator or operator is required.';
        ELSE IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_TICKET
            WHERE TicketID = @p_ticketID
              AND ParkingType = 'DAILY'
        )
            SET @ValidationMessage =
                'Daily parking ticket was not found.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           3. Read a completed payment, if one exists
           ==================================================== */

        DECLARE
            @Amount DECIMAL(12,2),
            @Seconds BIGINT,
            @HourlyRateID INT,
            @DailyRateID INT,
            @HourlyRate DECIMAL(12,2),
            @DailyRate DECIMAL(12,2),
            @ThresholdHours INT,
            @AtUTC DATETIME2(0) = SYSUTCDATETIME(),
            @PaymentID INT;

        SELECT
            @PaymentID = PaymentID,
            @Amount = Amount
        FROM dbo.PARKING_PAYMENT
        WHERE TicketID = @p_ticketID
          AND PaymentStatus = 'COMPLETED';

        IF @PaymentID IS NOT NULL
        BEGIN
            -- Use the billing details recorded when payment was made.
            SELECT
                @AtUTC = FeeCalculatedAtUTC,
                @HourlyRateID = HourlyRateID,
                @DailyRateID = DailyRateID,
                @HourlyRate = AppliedHourlyRate,
                @DailyRate = AppliedDailyRate,
                @ThresholdHours = AppliedDailyThresholdHours,
                @Seconds = DATEDIFF_BIG
                (
                    SECOND,
                    EntryDateTime,
                    FeeCalculatedAtUTC
                )
            FROM dbo.PARKING_TICKET
            WHERE TicketID = @p_ticketID;
        END;
        ELSE
        BEGIN
            /* ================================================
               4. Calculate the unpaid ticket's current fee
               ================================================ */

            DECLARE
                @CalculationStatus INT,
                @CalculationResult VARCHAR(500),
                @CalculationException VARCHAR(MAX);

            EXEC dbo.PARKING_SP_Daily_Fee_Calculate
                @ActionType = 1,
                @p_ticketID = @p_ticketID,
                @p_atUTC = @AtUTC,
                @p_amount = @Amount OUTPUT,
                @p_durationSeconds = @Seconds OUTPUT,
                @p_hourlyRateID = @HourlyRateID OUTPUT,
                @p_dailyRateID = @DailyRateID OUTPUT,
                @p_hourlyRate = @HourlyRate OUTPUT,
                @p_dailyRate = @DailyRate OUTPUT,
                @p_thresholdHours = @ThresholdHours OUTPUT,
                @p_uid = @p_uid,
                @ResultStatusCode = @CalculationStatus OUTPUT,
                @Result = @CalculationResult OUTPUT,
                @ExceptionMessage = @CalculationException OUTPUT;

            IF ISNULL(@CalculationStatus, 0) <> 1
            BEGIN
                IF XACT_STATE() <> 0
                    ROLLBACK TRANSACTION;

                SET @StartedTransaction = 0;

                SET @ResultStatusCode = -1;
                SET @Result = COALESCE
                (
                    NULLIF(@CalculationResult, ''),
                    'Daily parking fee could not be calculated.'
                );
                SET @ExceptionMessage =
                    ISNULL(@CalculationException, '');

                RETURN;
            END;
        END;

        /* ====================================================
           5. Return the preview
           ==================================================== */

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;
        SET @Result = 'Daily parking fee preview retrieved successfully';

        SELECT
            @p_ticketID AS TicketID,
            CONVERT
            (
                BIT,
                CASE WHEN @PaymentID IS NULL THEN 0 ELSE 1 END
            ) AS AlreadyPaid,
            @PaymentID AS PaymentID,
            @Amount AS Amount,
            @Seconds AS DurationSeconds,
            @HourlyRate AS HourlyRate,
            @DailyRate AS DailyRate,
            @ThresholdHours AS DailyThresholdHours,
            @AtUTC AS CalculationTimeUTC;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while retrieving the daily parking fee preview';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO