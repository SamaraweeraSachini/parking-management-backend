USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Daily_Exit
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
                'Invalid action type. Use 1 for daily exit.';
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

        IF @ValidationMessage IS NOT NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           3. Find the paid ticket awaiting exit
           ==================================================== */

        DECLARE
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @SpaceID INT,
            @TicketNumber VARCHAR(40),
            @EntryDateTime DATETIME2(0),
            @SavedAmount DECIMAL(12,2),
            @PaidAmount DECIMAL(12,2);

        SELECT
            @SpaceID = SpaceID,
            @TicketNumber = TicketNumber,
            @EntryDateTime = EntryDateTime,
            @SavedAmount = CalculatedAmount
        FROM dbo.PARKING_TICKET WITH (UPDLOCK, HOLDLOCK)
        WHERE TicketID = @p_ticketID
          AND ParkingType = 'DAILY'
          AND TicketStatus = 'PAYMENT_PENDING'
          AND ExitDateTime IS NULL;

        IF @SpaceID IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result =
                'A paid daily ticket awaiting exit is required.';
            RETURN;
        END;

        /* ====================================================
           4. Verify the completed payment
           ==================================================== */

        SELECT @PaidAmount = Amount
        FROM dbo.PARKING_PAYMENT WITH (HOLDLOCK)
        WHERE TicketID = @p_ticketID
          AND PaymentStatus = 'COMPLETED';

        IF @PaidAmount IS NULL
           OR @SavedAmount IS NULL
           OR @PaidAmount <> @SavedAmount
            SET @ValidationMessage =
                'A matching completed payment is required before exit.';
        ELSE IF @EntryDateTime > @Now
            SET @ValidationMessage =
                'Entry time is later than server time.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           5. Determine the space status after exit
           ==================================================== */

        DECLARE @SpaceStatus VARCHAR(20) = 'AVAILABLE';

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

        /* ====================================================
           6. Close the ticket and release the space
           ==================================================== */

        UPDATE dbo.PARKING_TICKET
        SET
            ExitDateTime = @Now,
            ExitOperatorID = @p_uid,
            TicketStatus = 'CLOSED',
            UpdatedAt = @Now,
            UpdatedBy = @p_uid
        WHERE TicketID = @p_ticketID
          AND ParkingType = 'DAILY'
          AND TicketStatus = 'PAYMENT_PENDING'
          AND ExitDateTime IS NULL;

        IF @@ROWCOUNT <> 1
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = 'Could not close the daily visit.';
            RETURN;
        END;

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

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;
        SET @Result = 'Daily vehicle exited successfully';

        SELECT
            @p_ticketID AS TicketID,
            @TicketNumber AS TicketNumber,
            @SpaceID AS SpaceID,
            @SpaceStatus AS SpaceStatus,
            @Now AS ExitDateTime;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while processing daily vehicle exit';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO