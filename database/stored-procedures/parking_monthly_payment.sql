USE [VehicleParkingManagementDB];
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Monthly_Payment
(
    @ActionType          INT,

    @MonthlyPaymentID    INT = NULL,
    @ContractID          INT = NULL,

    @PaymentNumber       NVARCHAR(50) = NULL,

    @PeriodStartDate     DATE = NULL,
    @PeriodEndDate       DATE = NULL,

    @PaymentMethod       VARCHAR(20) = NULL,

    @Remarks             NVARCHAR(500) = NULL,

    @PerformedByUserID   INT = NULL,

    @IncludeInactive     BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;


    SET @PaymentNumber = NULLIF(LTRIM(RTRIM(@PaymentNumber)), N'');
    SET @Remarks = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    SET @PaymentMethod =
        UPPER(NULLIF(LTRIM(RTRIM(@PaymentMethod)), ''));


    /* ============================================================
       VALID ACTION
       ============================================================ */
    IF @ActionType NOT BETWEEN 1 AND 5
    BEGIN
        SELECT
            400 AS StatusCode,
            N'Invalid ActionType.' AS Message;
        RETURN;
    END;


    /* ============================================================
       ACTION 1
       LIST MONTHLY PAYMENTS
       ============================================================ */
    IF @ActionType = 1
    BEGIN

        SELECT
            mp.MonthlyPaymentID,
            mp.PaymentNumber,

            mp.ContractID,
            mc.ContractNumber,

            c.CustomerID,
            c.CustomerName,

            v.VehicleNumber,

            mp.PeriodStartDate,
            mp.PeriodEndDate,

            mp.Amount,
            mp.PaymentMethod,
            mp.PaymentStatus,

            mp.PaymentDateTime,
            mp.ReceivedByUserID,

            mp.ReceiptNumber,
            mp.Remarks

        FROM dbo.PARKING_MONTHLY_PAYMENT AS mp

        INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS mc
            ON mc.ContractID = mp.ContractID

        INNER JOIN dbo.PARKING_CUSTOMER AS c
            ON c.CustomerID = mc.CustomerID

        INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS v
            ON v.VehicleID = mc.VehicleID

        WHERE
            @IncludeInactive = 1
            OR mp.PaymentStatus = 'COMPLETED'

        ORDER BY
            mp.PaymentDateTime DESC;

        RETURN;
    END;


    /* ============================================================
       ACTION 2
       GET PAYMENT BY ID
       ============================================================ */
    IF @ActionType = 2
    BEGIN

        IF @MonthlyPaymentID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'MonthlyPaymentID is required.' AS Message;
            RETURN;
        END;


        SELECT
            mp.MonthlyPaymentID,
            mp.PaymentNumber,

            mp.ContractID,
            mc.ContractNumber,

            c.CustomerID,
            c.CustomerName,

            v.VehicleNumber,

            mp.PeriodStartDate,
            mp.PeriodEndDate,

            mp.Amount,
            mp.PaymentMethod,
            mp.PaymentStatus,

            mp.PaymentDateTime,
            mp.ReceivedByUserID,

            mp.ReceiptNumber,
            mp.Remarks

        FROM dbo.PARKING_MONTHLY_PAYMENT AS mp

        INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS mc
            ON mc.ContractID = mp.ContractID

        INNER JOIN dbo.PARKING_CUSTOMER AS c
            ON c.CustomerID = mc.CustomerID

        INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS v
            ON v.VehicleID = mc.VehicleID

        WHERE mp.MonthlyPaymentID = @MonthlyPaymentID;

        RETURN;
    END;


    /* ============================================================
       ADMIN / OPERATOR VALIDATION
       ============================================================ */
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.PARKING_USER
        WHERE UserID = @PerformedByUserID
          AND ActiveStatus = 1
          AND UserRole IN ('A','O')
    )
    BEGIN
        SELECT
            403 AS StatusCode,
            N'An active parking system user is required.' AS Message;
        RETURN;
    END;


    /* ============================================================
       ACTION 3
       CREATE MONTHLY PAYMENT
       ============================================================ */
    IF @ActionType = 3
    BEGIN

        IF @ContractID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'ContractID is required.' AS Message;
            RETURN;
        END;


        IF @PeriodStartDate IS NULL
           OR @PeriodEndDate IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Payment period dates are required.' AS Message;
            RETURN;
        END;


        IF @PeriodEndDate < @PeriodStartDate
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Payment period end date cannot be before start date.' AS Message;
            RETURN;
        END;


        IF @PaymentMethod NOT IN ('CASH','CARD')
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Payment method must be CASH or CARD.' AS Message;
            RETURN;
        END;


        BEGIN TRY

            BEGIN TRANSACTION;


            /* ----------------------------------------------------
               Get active contract and monthly fee
               ---------------------------------------------------- */
            DECLARE @MonthlyFee DECIMAL(12,2);
            DECLARE @ContractStatus VARCHAR(20);


            SELECT
                @MonthlyFee = MonthlyFee,
                @ContractStatus = ContractStatus

            FROM dbo.PARKING_MONTHLY_CONTRACT WITH (UPDLOCK, HOLDLOCK)

            WHERE ContractID = @ContractID;


            IF @MonthlyFee IS NULL
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    404 AS StatusCode,
                    N'Monthly contract not found.' AS Message;
                RETURN;
            END;


            IF @ContractStatus <> 'ACTIVE'
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    409 AS StatusCode,
                    N'Payment cannot be created for an inactive monthly contract.' AS Message;
                RETURN;
            END;


            /* ----------------------------------------------------
               Check payment period does not overlap
               an existing completed payment
               ---------------------------------------------------- */
            IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_MONTHLY_PAYMENT WITH (UPDLOCK, HOLDLOCK)

                WHERE ContractID = @ContractID

                  AND PaymentStatus = 'COMPLETED'

                  AND PeriodStartDate <= @PeriodEndDate
                  AND PeriodEndDate >= @PeriodStartDate
            )
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    409 AS StatusCode,
                    N'This payment period overlaps an existing completed monthly payment.' AS Message;
                RETURN;
            END;


            /* ----------------------------------------------------
               Generate payment number
               ---------------------------------------------------- */
            IF @PaymentNumber IS NULL
            BEGIN
                SET @PaymentNumber =
                    N'MP-' +
                    CONVERT(NVARCHAR(8), GETDATE(), 112) +
                    N'-' +
                    RIGHT(
                        N'000000' +
                        CONVERT(
                            NVARCHAR(20),
                            ISNULL(
                                (
                                    SELECT MAX(MonthlyPaymentID) + 1
                                    FROM dbo.PARKING_MONTHLY_PAYMENT
                                ),
                                1
                            )
                        ),
                        6
                    );
            END;


            /* ----------------------------------------------------
               Check payment number
               ---------------------------------------------------- */
            IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_MONTHLY_PAYMENT
                WHERE PaymentNumber = @PaymentNumber
            )
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    409 AS StatusCode,
                    N'Payment number already exists.' AS Message;
                RETURN;
            END;


            /* ----------------------------------------------------
               Generate receipt number
               ---------------------------------------------------- */
            DECLARE @ReceiptNumber NVARCHAR(50);


            SET @ReceiptNumber =
                N'REC-M-' +
                CONVERT(NVARCHAR(8), GETDATE(), 112) +
                N'-' +
                RIGHT(
                    N'000000' +
                    CONVERT(
                        NVARCHAR(20),
                        ISNULL(
                            (
                                SELECT MAX(MonthlyPaymentID) + 1
                                FROM dbo.PARKING_MONTHLY_PAYMENT
                            ),
                            1
                        )
                    ),
                    6
                );


            /* ----------------------------------------------------
               Insert monthly payment
               
               IMPORTANT:
               Amount comes from contract.MonthlyFee.
               It is NOT received from frontend.
               ---------------------------------------------------- */
            INSERT INTO dbo.PARKING_MONTHLY_PAYMENT
            (
                PaymentNumber,
                ContractID,
                PeriodStartDate,
                PeriodEndDate,
                Amount,
                PaymentMethod,
                PaymentStatus,
                PaymentDateTime,
                ReceivedByUserID,
                ReceiptNumber,
                Remarks
            )
            VALUES
            (
                @PaymentNumber,
                @ContractID,
                @PeriodStartDate,
                @PeriodEndDate,
                @MonthlyFee,
                @PaymentMethod,
                'COMPLETED',
                SYSUTCDATETIME(),
                @PerformedByUserID,
                @ReceiptNumber,
                @Remarks
            );


            DECLARE @NewMonthlyPaymentID INT =
                CONVERT(INT, SCOPE_IDENTITY());


            COMMIT TRANSACTION;


            SELECT
                201 AS StatusCode,
                N'Monthly payment recorded successfully.' AS Message,

                @NewMonthlyPaymentID AS MonthlyPaymentID,
                @PaymentNumber AS PaymentNumber,
                @ReceiptNumber AS ReceiptNumber,
                @MonthlyFee AS Amount;

            RETURN;

        END TRY

        BEGIN CATCH

            IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;

            THROW;

        END CATCH
    END;


    /* ============================================================
       ACTION 4
       CANCEL MONTHLY PAYMENT
       ============================================================ */
    IF @ActionType = 4
    BEGIN

        IF @MonthlyPaymentID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'MonthlyPaymentID is required.' AS Message;
            RETURN;
        END;


        BEGIN TRY

            BEGIN TRANSACTION;


            UPDATE dbo.PARKING_MONTHLY_PAYMENT
            SET
                PaymentStatus = 'CANCELLED',
                UpdatedAt = SYSUTCDATETIME(),
                UpdatedBy = @PerformedByUserID
            WHERE MonthlyPaymentID = @MonthlyPaymentID
              AND PaymentStatus = 'COMPLETED';


            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    404 AS StatusCode,
                    N'Completed monthly payment not found.' AS Message;
                RETURN;
            END;


            COMMIT TRANSACTION;


            SELECT
                200 AS StatusCode,
                N'Monthly payment cancelled successfully.' AS Message;

            RETURN;

        END TRY

        BEGIN CATCH

            IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;

            THROW;

        END CATCH
    END;


    /* ============================================================
       ACTION 5
       GET PAYMENTS FOR A CONTRACT
       ============================================================ */
    IF @ActionType = 5
    BEGIN

        IF @ContractID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'ContractID is required.' AS Message;
            RETURN;
        END;


        SELECT
            MonthlyPaymentID,
            PaymentNumber,
            ContractID,

            PeriodStartDate,
            PeriodEndDate,

            Amount,
            PaymentMethod,
            PaymentStatus,

            PaymentDateTime,
            ReceivedByUserID,

            ReceiptNumber,
            Remarks

        FROM dbo.PARKING_MONTHLY_PAYMENT

        WHERE ContractID = @ContractID

        ORDER BY
            PeriodStartDate DESC;

        RETURN;
    END;

END;
GO