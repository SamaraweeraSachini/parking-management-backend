USE [VehicleParkingManagementDB];
GO

/* Charges current active rates at the instant of exit. A daily ticket must
   already exist with TicketStatus=OPEN, RateID and AppliedRate set at entry.
   The final calculation uses BOTH hourly and daily rates; RateID/AppliedRate
   on the current ticket schema cannot preserve both components historically.
   PaymentAmount and CalculatedAmount preserve the final charged total.

   This operation is atomic: completed payment, closed ticket, and released
   space commit together. The API must authorize its caller and supply the
   authenticated operator's UserID, never a user-selected ID. */
CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Daily_Exit_Payment
    @TicketID INT,
    @PaymentMethod VARCHAR(20),
    @OperatorUserID INT,
    @Remarks NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @PaymentMethod = UPPER(NULLIF(LTRIM(RTRIM(@PaymentMethod)), ''));
    SET @Remarks = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF @TicketID IS NULL OR @OperatorUserID IS NULL
       OR @PaymentMethod IS NULL OR @PaymentMethod NOT IN ('CASH', 'CARD')
    BEGIN
        SELECT 400 AS StatusCode, N'Ticket, operator and CASH/CARD payment method are required.' AS Message;
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM dbo.PARKING_USER
                       WHERE UserID = @OperatorUserID AND ActiveStatus = 1
                         AND UserRole IN ('A', 'O'))
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 403 AS StatusCode, N'Active administrator or operator required.' AS Message;
            RETURN;
        END;

        DECLARE @SpaceID INT, @VehicleTypeID INT,
                @EntryDateTime DATETIME2(0), @TicketNumber VARCHAR(40),
                @VehicleNumber VARCHAR(30), @ParkingType VARCHAR(20),
                @TicketStatus VARCHAR(30), @ExitDateTime DATETIME2(0);

        SELECT @SpaceID = t.SpaceID, @VehicleTypeID = v.VehicleTypeID,
               @EntryDateTime = t.EntryDateTime,
               @TicketNumber = t.TicketNumber,
               @VehicleNumber = v.VehicleNumber,
               @ParkingType = t.ParkingType,
               @TicketStatus = t.TicketStatus,
               @ExitDateTime = t.ExitDateTime
        FROM dbo.PARKING_TICKET AS t WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS v ON v.VehicleID = t.VehicleID
        WHERE t.TicketID = @TicketID;

        IF @SpaceID IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 404 AS StatusCode, N'Ticket not found.' AS Message;
            RETURN;
        END;
        IF @ParkingType <> 'DAILY' OR @TicketStatus <> 'OPEN' OR @ExitDateTime IS NOT NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 409 AS StatusCode, N'Only an open daily ticket can be paid and exited.' AS Message;
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM dbo.PARKING_PAYMENT WHERE TicketID = @TicketID)
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 409 AS StatusCode, N'Ticket already has a payment.' AS Message;
            RETURN;
        END;

        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
        DECLARE @Seconds BIGINT = DATEDIFF_BIG(SECOND, @EntryDateTime, @Now);
        IF @Seconds < 0
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 409 AS StatusCode, N'Entry time is later than server time.' AS Message;
            RETURN;
        END;

        DECLARE @HourlyRate DECIMAL(12,2), @DailyRate DECIMAL(12,2);
        SELECT @HourlyRate = RateAmount
        FROM dbo.PARKING_RATE WITH (HOLDLOCK)
        WHERE VehicleTypeID = @VehicleTypeID AND RateUnit = 'HOURLY'
          AND ActiveStatus = 1 AND EffectiveFrom <= @Now
          AND (EffectiveTo IS NULL OR EffectiveTo > @Now);

        SELECT @DailyRate = RateAmount
        FROM dbo.PARKING_RATE WITH (HOLDLOCK)
        WHERE VehicleTypeID = @VehicleTypeID AND RateUnit = 'DAILY'
          AND ActiveStatus = 1 AND EffectiveFrom <= @Now
          AND (EffectiveTo IS NULL OR EffectiveTo > @Now);

        IF @HourlyRate IS NULL OR @DailyRate IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 409 AS StatusCode, N'Both active hourly and daily rates are required for this vehicle type.' AS Message;
            RETURN;
        END;

        /* Full 24-hour blocks cost daily rate. Exact remainder of 6 hours is
           hourly; a remainder greater than 6 hours costs one daily rate. */
        DECLARE @FullDays BIGINT = @Seconds / 86400;
        DECLARE @RemainingSeconds BIGINT = @Seconds % 86400;
        DECLARE @Charge DECIMAL(38,6) =
            CONVERT(DECIMAL(38,6), @FullDays) * @DailyRate +
            CASE WHEN @RemainingSeconds <= 21600
                 THEN CONVERT(DECIMAL(38,6), @RemainingSeconds)
                      * @HourlyRate / CONVERT(DECIMAL(38,6), 3600)
                 ELSE CONVERT(DECIMAL(38,6), @DailyRate) END;
        DECLARE @Amount DECIMAL(12,2) = CONVERT(DECIMAL(12,2), ROUND(@Charge, 2));
        DECLARE @BillableHours DECIMAL(10,2) =
            CONVERT(DECIMAL(10,2),
                    ROUND(CONVERT(DECIMAL(18,6), @Seconds) / 3600, 2));

        DECLARE @PaymentNumber VARCHAR(40) = 'PAY-' + CONVERT(VARCHAR(36), NEWID());
        DECLARE @ReceiptNumber VARCHAR(40) = 'REC-' + CONVERT(VARCHAR(36), NEWID());

        INSERT dbo.PARKING_PAYMENT
            (PaymentNumber, TicketID, Amount, PaymentMethod, PaymentStatus,
             PaymentDateTime, ReceivedByUserID, ReceiptNumber, Remarks,
             CreatedAt, CreatedBy)
        VALUES
            (@PaymentNumber, @TicketID, @Amount, @PaymentMethod, 'COMPLETED',
             @Now, @OperatorUserID, @ReceiptNumber, @Remarks,
             @Now, @OperatorUserID);
        DECLARE @PaymentID INT = CONVERT(INT, SCOPE_IDENTITY());

        UPDATE dbo.PARKING_TICKET
        SET ExitDateTime = @Now, ExitOperatorID = @OperatorUserID,
            BillableHours = @BillableHours, CalculatedAmount = @Amount,
            TicketStatus = 'CLOSED', UpdatedAt = @Now, UpdatedBy = @OperatorUserID
        WHERE TicketID = @TicketID AND TicketStatus = 'OPEN' AND ExitDateTime IS NULL;
        IF @@ROWCOUNT <> 1
            THROW 51030, 'Could not close ticket.', 1;

        UPDATE dbo.PARKING_SPACE
        SET SpaceStatus = 'AVAILABLE', UpdatedAt = @Now, UpdatedBy = @OperatorUserID
        WHERE SpaceID = @SpaceID AND SpaceStatus = 'OCCUPIED';
        IF @@ROWCOUNT <> 1
            THROW 51031, 'Could not release occupied space.', 1;

        COMMIT TRANSACTION;
        SELECT 200 AS StatusCode, N'Payment completed and vehicle exited.' AS Message,
               @TicketID AS TicketID, @TicketNumber AS TicketNumber,
               @VehicleNumber AS VehicleNumber, @SpaceID AS SpaceID,
               @PaymentID AS PaymentID, @PaymentNumber AS PaymentNumber,
               @ReceiptNumber AS ReceiptNumber, @PaymentMethod AS PaymentMethod,
               @EntryDateTime AS EntryDateTime, @Now AS ExitDateTime,
               @HourlyRate AS HourlyRate, @DailyRate AS DailyRate,
               @FullDays AS FullDays, @RemainingSeconds AS RemainingSeconds,
               @Amount AS Amount;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
