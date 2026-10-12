USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Daily_Payment
(
    @ActionType          INT,

    @p_ticketID          INT = NULL,
    @p_paymentMethod     VARCHAR(20) = NULL,
    @p_expectedAmount    DECIMAL(12,2) = NULL,
    @p_calculationTimeUTC DATETIME2(0) = NULL,
    @p_exitNow           BIT = 0,
    @p_remarks           NVARCHAR(500) = NULL,
    @p_uid               BIGINT = NULL,

    @ResultStatusCode    INT OUTPUT,
    @Result              VARCHAR(500) OUTPUT,
    @ExceptionMessage    VARCHAR(MAX) OUTPUT
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

        SET @p_paymentMethod =
            UPPER(NULLIF(LTRIM(RTRIM(@p_paymentMethod)), ''));

        SET @p_remarks =
            NULLIF(LTRIM(RTRIM(@p_remarks)), N'');

        /* ====================================================
           1. Validate inputs
           ==================================================== */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType <> 1
            SET @ValidationMessage =
                'Invalid action type. Use 1 to record daily payment.';
        ELSE IF @p_ticketID IS NULL OR @p_ticketID <= 0
            SET @ValidationMessage = 'A valid ticket ID is required.';
        ELSE IF @p_expectedAmount IS NULL OR @p_expectedAmount < 0
            SET @ValidationMessage =
                'A nonnegative confirmed preview amount is required.';
        ELSE IF @p_calculationTimeUTC IS NULL
            SET @ValidationMessage =
                'The confirmed preview calculation time is required.';
        ELSE IF @p_paymentMethod IS NULL
            OR @p_paymentMethod NOT IN ('CASH', 'CARD')
            SET @ValidationMessage =
                'Payment method must be CASH or CARD.';
        ELSE IF @p_exitNow IS NULL
            SET @ValidationMessage = 'The exit choice is required.';
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

        IF @ValidationMessage IS NOT NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           3. Check preview validity and the unpaid ticket
           ==================================================== */

        DECLARE
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @SpaceID INT,
            @TicketNumber VARCHAR(40);

        IF @p_calculationTimeUTC > @Now
           OR @p_calculationTimeUTC < DATEADD(MINUTE, -2, @Now)
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result =
                'Fee preview expired. Refresh and confirm again.';
            RETURN;
        END;

        SELECT
            @SpaceID = SpaceID,
            @TicketNumber = TicketNumber
        FROM dbo.PARKING_TICKET WITH (UPDLOCK, HOLDLOCK)
        WHERE TicketID = @p_ticketID
          AND ParkingType = 'DAILY'
          AND TicketStatus = 'OPEN'
          AND ExitDateTime IS NULL;

        IF @SpaceID IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = 'An open unpaid daily ticket is required.';
            RETURN;
        END;

        /* ====================================================
           4. Recalculate and verify the confirmed amount
           ==================================================== */

        DECLARE
            @Amount DECIMAL(12,2),
            @Seconds BIGINT,
            @HourlyRateID INT,
            @DailyRateID INT,
            @HourlyRate DECIMAL(12,2),
            @DailyRate DECIMAL(12,2),
            @ThresholdHours INT,
            @CalculationStatus INT,
            @CalculationResult VARCHAR(500),
            @CalculationException VARCHAR(MAX);

        EXEC dbo.PARKING_SP_Daily_Fee_Calculate
            @ActionType = 1,
            @p_ticketID = @p_ticketID,
            @p_atUTC = @p_calculationTimeUTC,
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

        DECLARE @Hours DECIMAL(10,2) =
            TRY_CONVERT(DECIMAL(10,2), @Seconds / 3600.0);

        IF @Amount IS NULL OR @Amount <> @p_expectedAmount
            SET @ValidationMessage =
                'Fee changed. Refresh the preview and confirm the new amount.';
        ELSE IF @Hours IS NULL
            SET @ValidationMessage =
                'Parking duration exceeds the supported range.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           5. Record payment and receipt numbers
           ==================================================== */

        DECLARE @PaymentSequence BIGINT =
            NEXT VALUE FOR dbo.PARKING_PAYMENT_SEQUENCE;

        DECLARE @PaymentNumber VARCHAR(40) =
            'PD-' + CONVERT(VARCHAR(20), @PaymentSequence);

        DECLARE @ReceiptNumber VARCHAR(40) =
            'RD-' + CONVERT(VARCHAR(20), @PaymentSequence);

        INSERT dbo.PARKING_PAYMENT
        (
            PaymentNumber,
            TicketID,
            Amount,
            PaymentMethod,
            PaymentDateTime,
            ReceivedByUserID,
            ReceiptNumber,
            Remarks,
            CreatedAt,
            CreatedBy
        )
        VALUES
        (
            @PaymentNumber,
            @p_ticketID,
            @Amount,
            @p_paymentMethod,
            @Now,
            @p_uid,
            @ReceiptNumber,
            @p_remarks,
            @Now,
            @p_uid
        );

        DECLARE @PaymentID INT =
            CONVERT(INT, SCOPE_IDENTITY());

        /* ====================================================
           6. Save billing details and optional exit
           ==================================================== */

        UPDATE dbo.PARKING_TICKET
        SET
            HourlyRateID = @HourlyRateID,
            DailyRateID = @DailyRateID,
            AppliedHourlyRate = @HourlyRate,
            AppliedDailyRate = @DailyRate,
            AppliedDailyThresholdHours = @ThresholdHours,
            FeeCalculatedAtUTC = @p_calculationTimeUTC,
            BillableHours = @Hours,
            CalculatedAmount = @Amount,
            TicketStatus =
                CASE WHEN @p_exitNow = 1
                     THEN 'CLOSED' ELSE 'PAYMENT_PENDING' END,
            ExitDateTime =
                CASE WHEN @p_exitNow = 1 THEN @Now ELSE NULL END,
            ExitOperatorID =
                CASE WHEN @p_exitNow = 1 THEN @p_uid ELSE NULL END,
            UpdatedAt = @Now,
            UpdatedBy = @p_uid
        WHERE TicketID = @p_ticketID
          AND ParkingType = 'DAILY'
          AND TicketStatus = 'OPEN'
          AND ExitDateTime IS NULL;

        IF @@ROWCOUNT <> 1
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = 'Could not update the paid ticket.';
            RETURN;
        END;

        /* ====================================================
           7. Release the space when exiting immediately
           ==================================================== */

        DECLARE @SpaceStatus VARCHAR(20) = 'OCCUPIED';

        IF @p_exitNow = 1
        BEGIN
            SET @SpaceStatus = 'AVAILABLE';

            IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_MONTHLY_RESERVATION AS R
                INNER JOIN dbo.PARKING_MONTHLY_PAYMENT AS MP
                    ON MP.MonthlyPaymentID = R.MonthlyPaymentID
                INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS MC
                    ON MC.ContractID = MP.ContractID
                WHERE R.SpaceID = @SpaceID
                  AND MP.PaymentStatus = 'COMPLETED'
                  AND MC.ContractStatus = 'ACTIVE'
                  AND MC.CancelledAt IS NULL
                  AND R.EffectiveFromUTC <= @Now
                  AND R.EffectiveToUTC > @Now
            )
                SET @SpaceStatus = 'RESERVED';

            UPDATE dbo.PARKING_SPACE
            SET
                SpaceStatus = @SpaceStatus,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE SpaceID = @SpaceID
              AND SpaceStatus = 'OCCUPIED';

            IF @@ROWCOUNT <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;

                SET @ResultStatusCode = -1;
                SET @Result = 'Could not release the occupied space.';
                RETURN;
            END;
        END;

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;
        SET @Result =
            CASE WHEN @p_exitNow = 1
                 THEN 'Payment recorded and vehicle exited.'
                 ELSE 'Payment recorded. Vehicle exit remains pending.'
            END;

        SELECT
            @p_ticketID AS TicketID,
            @TicketNumber AS TicketNumber,
            @PaymentID AS PaymentID,
            @PaymentNumber AS PaymentNumber,
            @ReceiptNumber AS ReceiptNumber,
            @Amount AS Amount,
            @SpaceID AS SpaceID,
            @SpaceStatus AS SpaceStatus,
            @p_calculationTimeUTC AS FeeCalculatedAtUTC,
            @Now AS PaymentDateTime;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while processing daily parking payment';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO