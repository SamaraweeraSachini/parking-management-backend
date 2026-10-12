USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Monthly_Payment
(
    @ActionType         INT,

    @p_monthlyPaymentID INT = NULL,
    @p_contractID       INT = NULL,
    @p_periodStartDate  DATE = NULL,
    @p_periodEndDate    DATE = NULL,
    @p_amount           DECIMAL(12,2) = NULL,
    @p_paymentMethod    VARCHAR(20) = NULL,
    @p_spaceID          INT = NULL,
    @p_remarks          NVARCHAR(500) = NULL,
    @p_searchTerm       NVARCHAR(200) = NULL,
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

        SET @p_paymentMethod =
            UPPER(NULLIF(LTRIM(RTRIM(@p_paymentMethod)), ''));

        SET @p_remarks =
            NULLIF(LTRIM(RTRIM(@p_remarks)), N'');

        SET @p_searchTerm =
            NULLIF(LTRIM(RTRIM(@p_searchTerm)), N'');

        /* ============================================================
           Shared Input Validation
           ============================================================ */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType NOT BETWEEN 1 AND 3
            SET @ValidationMessage = 'Invalid action type';

        ELSE IF @ActionType = 2
             AND
             (
                 @p_monthlyPaymentID IS NULL
                 OR @p_monthlyPaymentID <= 0
             )
            SET @ValidationMessage =
                'A valid monthly payment ID is required';

        ELSE IF @ActionType = 3
             AND (@p_contractID IS NULL OR @p_contractID <= 0)
            SET @ValidationMessage = 'A valid contract ID is required';

        ELSE IF @ActionType = 3
             AND
             (
                 @p_periodStartDate IS NULL
                 OR @p_periodEndDate IS NULL
                 OR @p_periodEndDate < @p_periodStartDate
                 OR @p_periodEndDate =
                    CONVERT(DATE, '99991231', 112)
             )
            SET @ValidationMessage =
                'A valid payment coverage period is required';

        ELSE IF @ActionType = 3
             AND (@p_amount IS NULL OR @p_amount < 0)
            SET @ValidationMessage =
                'A nonnegative confirmed payment amount is required';

        ELSE IF @ActionType = 3
             AND
             (
                 @p_paymentMethod IS NULL
                 OR @p_paymentMethod NOT IN ('CASH', 'CARD')
             )
            SET @ValidationMessage =
                'Payment method must be CASH or CARD';

        ELSE IF @ActionType = 3
             AND @p_spaceID IS NOT NULL
             AND @p_spaceID <= 0
            SET @ValidationMessage =
                'Space ID must be a positive ID or NULL';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ============================================================
           1. Get / Search Monthly Payments
           2. Get Monthly Payment And Receipt By ID
           ============================================================ */

        IF @ActionType IN (1, 2)
        BEGIN
            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_USER
                WHERE UserID = @p_uid
                  AND ActiveStatus = 1
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An authenticated active user is required';
                RETURN;
            END;

            SELECT
                'MONTHLY' AS PaymentType,
                MP.MonthlyPaymentID,
                MP.PaymentNumber,
                MP.ReceiptNumber,
                MP.ContractID,
                MC.ContractNumber,
                MC.MonthlyFee AS AgreedMonthlyFee,
                MC.CustomerID,
                C.CustomerName,
                C.MobileNumber,
                MC.VehicleID,
                V.VehicleNumber,
                VT.TypeName AS VehicleType,
                MP.PeriodStartDate,
                MP.PeriodEndDate,
                MP.Amount,
                MP.PaymentMethod,
                MP.PaymentStatus,
                MP.PaymentDateTime,
                MP.ReceivedByUserID,
                U.FullName AS ReceivedBy,
                MP.Remarks,
                R.ReservationID,
                R.SpaceID,
                S.SpaceCode,
                R.EffectiveFromUTC,
                R.EffectiveToUTC,
                A.FacilityName,
                A.Address AS FacilityAddress,
                A.ContactNumber AS FacilityContactNumber,
                A.ReceiptMessage
            FROM dbo.PARKING_MONTHLY_PAYMENT AS MP
            INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS MC
                ON MC.ContractID = MP.ContractID
            INNER JOIN dbo.PARKING_CUSTOMER AS C
                ON C.CustomerID = MC.CustomerID
            INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS V
                ON V.VehicleID = MC.VehicleID
            INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
                ON VT.VehicleTypeID = V.VehicleTypeID
            INNER JOIN dbo.PARKING_USER AS U
                ON U.UserID = MP.ReceivedByUserID
            LEFT JOIN dbo.PARKING_MONTHLY_RESERVATION AS R
                ON R.MonthlyPaymentID = MP.MonthlyPaymentID
            LEFT JOIN dbo.PARKING_SPACE AS S
                ON S.SpaceID = R.SpaceID
            LEFT JOIN dbo.PARKING_APP_SETTINGS AS A
                ON A.SettingsID = 1
            WHERE
                (
                    @ActionType = 1
                    AND
                    (
                        @p_contractID IS NULL
                        OR MP.ContractID = @p_contractID
                    )
                    AND
                    (
                        @p_searchTerm IS NULL
                        OR CHARINDEX
                           (
                               UPPER(@p_searchTerm),
                               UPPER(MP.PaymentNumber)
                           ) > 0
                        OR CHARINDEX
                           (
                               UPPER(@p_searchTerm),
                               UPPER(MP.ReceiptNumber)
                           ) > 0
                        OR CHARINDEX
                           (
                               UPPER(@p_searchTerm),
                               UPPER(MC.ContractNumber)
                           ) > 0
                        OR CHARINDEX
                           (
                               UPPER(@p_searchTerm),
                               UPPER(C.CustomerName)
                           ) > 0
                        OR CHARINDEX
                           (
                               UPPER(@p_searchTerm),
                               UPPER(V.VehicleNumber)
                           ) > 0
                        OR CHARINDEX
                           (
                               @p_searchTerm,
                               C.MobileNumber
                           ) > 0
                    )
                )
                OR
                (
                    @ActionType = 2
                    AND MP.MonthlyPaymentID = @p_monthlyPaymentID
                )
            ORDER BY
                MP.PaymentDateTime DESC,
                MP.MonthlyPaymentID DESC;

            IF @@ROWCOUNT = 0 AND @ActionType = 2
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly payment was not found';
                RETURN;
            END;

            SET @ResultStatusCode = 1;
            SET @Result = 'Monthly payment details retrieved successfully';
            RETURN;
        END;

        /* ============================================================
           3. Receive Monthly Payment And Reserve Space
           ============================================================ */

        IF @@TRANCOUNT <> 0
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result =
                'Call this procedure without an existing transaction';
            RETURN;
        END;

        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;

        DECLARE @LockResult INT;

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
            SET @Result =
                'Monthly payment processing is busy. Please retry';
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER WITH (HOLDLOCK)
            WHERE UserID = @p_uid
              AND ActiveStatus = 1
              AND UserRole IN ('A', 'O')
        )
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result =
                'An active administrator or operator is required';
            RETURN;
        END;

        DECLARE
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @Today DATE,
            @CustomerID INT,
            @VehicleID INT,
            @VehicleTypeID INT,
            @ContractStartDate DATE,
            @ContractEndDate DATE,
            @ContractStatus VARCHAR(20),
            @CancelledAt DATETIME2(0),
            @EffectiveFromUTC DATETIME2(0),
            @EffectiveToUTC DATETIME2(0);

        SET @Today =
            CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

        SELECT
            @CustomerID = CustomerID,
            @VehicleID = VehicleID,
            @ContractStartDate = StartDate,
            @ContractEndDate = EndDate,
            @ContractStatus = ContractStatus,
            @CancelledAt = CancelledAt
        FROM dbo.PARKING_MONTHLY_CONTRACT
            WITH (UPDLOCK, HOLDLOCK)
        WHERE ContractID = @p_contractID;

        SET @ValidationMessage = NULL;

        IF @ContractStatus IS NULL
            SET @ValidationMessage = 'Monthly contract was not found';

        ELSE IF @ContractStatus <> 'ACTIVE'
             OR @CancelledAt IS NOT NULL
             OR @ContractEndDate < @Today
            SET @ValidationMessage =
                'A valid active or upcoming monthly contract is required';

        ELSE IF @p_periodStartDate < @ContractStartDate
             OR @p_periodEndDate > @ContractEndDate
            SET @ValidationMessage =
                'Payment coverage must be within the contract dates';

        IF @ValidationMessage IS NULL
        BEGIN
            SELECT @VehicleTypeID = V.VehicleTypeID
            FROM dbo.PARKING_CUSTOMER_VEHICLE AS V
                WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.PARKING_CUSTOMER AS C
                WITH (HOLDLOCK)
                ON C.CustomerID = V.CustomerID
            INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
                WITH (HOLDLOCK)
                ON VT.VehicleTypeID = V.VehicleTypeID
            WHERE V.VehicleID = @VehicleID
              AND V.CustomerID = @CustomerID
              AND V.ActiveStatus = 1
              AND C.ActiveStatus = 1
              AND VT.ActiveStatus = 1;

            IF @VehicleTypeID IS NULL
                SET @ValidationMessage =
                    'An active matching customer, vehicle and vehicle type are required';
        END;

        IF @ValidationMessage IS NULL
        BEGIN
            -- Coverage includes the entire Sri Lankan end day.
            -- The UTC end boundary is exclusive.
            SET @EffectiveFromUTC =
                DATEADD
                (
                    MINUTE,
                    -330,
                    CONVERT(DATETIME2(0), @p_periodStartDate)
                );

            SET @EffectiveToUTC =
                DATEADD
                (
                    MINUTE,
                    -330,
                    DATEADD
                    (
                        DAY,
                        1,
                        CONVERT(DATETIME2(0), @p_periodEndDate)
                    )
                );

            IF @EffectiveToUTC <= @Now
                SET @ValidationMessage =
                    'The selected coverage period has already ended';

            ELSE IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_MONTHLY_PAYMENT
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE ContractID = @p_contractID
                  AND PaymentStatus = 'COMPLETED'
                  AND PeriodStartDate <= @p_periodEndDate
                  AND PeriodEndDate >= @p_periodStartDate
            )
                SET @ValidationMessage =
                    'A completed payment already overlaps this coverage period';
        END;

        IF @ValidationMessage IS NOT NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ============================================================
           Allocate A Compatible Space
           ============================================================ */

        DECLARE @SelectedSpaceID INT;

        SELECT TOP (1)
            @SelectedSpaceID = S.SpaceID
        FROM dbo.PARKING_SPACE AS S WITH (UPDLOCK, HOLDLOCK)
        WHERE S.VehicleTypeID = @VehicleTypeID
          AND S.ActiveStatus = 1
          AND S.SpaceStatus IN ('AVAILABLE', 'RESERVED', 'OCCUPIED')
          AND (@p_spaceID IS NULL OR S.SpaceID = @p_spaceID)
          AND
          (
              S.SpaceStatus <> 'OCCUPIED'
              OR EXISTS
              (
                  SELECT 1
                  FROM dbo.PARKING_TICKET AS T
                  WHERE T.SpaceID = S.SpaceID
                    AND T.VehicleID = @VehicleID
                    AND T.MonthlyContractID = @p_contractID
                    AND T.ParkingType = 'MONTHLY'
                    AND T.ExitDateTime IS NULL
              )
          )
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.PARKING_TICKET AS T
              WHERE T.SpaceID = S.SpaceID
                AND T.ExitDateTime IS NULL
                AND
                (
                    T.VehicleID <> @VehicleID
                    OR T.ParkingType <> 'MONTHLY'
                    OR T.MonthlyContractID IS NULL
                    OR T.MonthlyContractID <> @p_contractID
                )
          )
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.PARKING_MONTHLY_RESERVATION AS R
              INNER JOIN dbo.PARKING_MONTHLY_PAYMENT AS MP
                  ON MP.MonthlyPaymentID = R.MonthlyPaymentID
              INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS MC
                  ON MC.ContractID = MP.ContractID
              WHERE R.SpaceID = S.SpaceID
                AND MP.PaymentStatus = 'COMPLETED'
                AND MC.ContractStatus = 'ACTIVE'
                AND MC.CancelledAt IS NULL
                AND R.EffectiveFromUTC < @EffectiveToUTC
                AND R.EffectiveToUTC > @EffectiveFromUTC
          )
        ORDER BY
            CASE
                WHEN EXISTS
                (
                    SELECT 1
                    FROM dbo.PARKING_TICKET AS T
                    WHERE T.SpaceID = S.SpaceID
                      AND T.VehicleID = @VehicleID
                      AND T.MonthlyContractID = @p_contractID
                      AND T.ParkingType = 'MONTHLY'
                      AND T.ExitDateTime IS NULL
                )
                    THEN 0
                WHEN EXISTS
                (
                    SELECT 1
                    FROM dbo.PARKING_MONTHLY_RESERVATION AS R
                    INNER JOIN dbo.PARKING_MONTHLY_PAYMENT AS MP
                        ON MP.MonthlyPaymentID = R.MonthlyPaymentID
                    WHERE R.SpaceID = S.SpaceID
                      AND MP.ContractID = @p_contractID
                      AND MP.PaymentStatus = 'COMPLETED'
                )
                    THEN 1
                ELSE 2
            END,
            S.SpaceCode,
            S.SpaceID;

        IF @SelectedSpaceID IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result =
                'No compatible space is available for the selected coverage period';
            RETURN;
        END;

        SET @p_spaceID = @SelectedSpaceID;

        /* ============================================================
           Save Payment And Reservation
           ============================================================ */

        DECLARE @PaymentSequence BIGINT =
            NEXT VALUE FOR dbo.PARKING_PAYMENT_SEQUENCE;

        DECLARE @PaymentNumber VARCHAR(40) =
            'PM-' + CONVERT(VARCHAR(20), @PaymentSequence);

        DECLARE @ReceiptNumber VARCHAR(40) =
            'RM-' + CONVERT(VARCHAR(20), @PaymentSequence);

        INSERT INTO dbo.PARKING_MONTHLY_PAYMENT
        (
            PaymentNumber,
            ContractID,
            PeriodStartDate,
            PeriodEndDate,
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
            @p_contractID,
            @p_periodStartDate,
            @p_periodEndDate,
            @p_amount,
            @p_paymentMethod,
            @Now,
            @p_uid,
            @ReceiptNumber,
            @p_remarks,
            @Now,
            @p_uid
        );

        SET @p_monthlyPaymentID =
            CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.PARKING_MONTHLY_RESERVATION
        (
            MonthlyPaymentID,
            SpaceID,
            EffectiveFromUTC,
            EffectiveToUTC,
            CreatedAt,
            CreatedBy
        )
        VALUES
        (
            @p_monthlyPaymentID,
            @p_spaceID,
            @EffectiveFromUTC,
            @EffectiveToUTC,
            @Now,
            @p_uid
        );

        DECLARE @ReservationID INT =
            CONVERT(INT, SCOPE_IDENTITY());

        /* ============================================================
           Update Current Physical Space Status
           ============================================================ */

        UPDATE S
        SET
            SpaceStatus =
                CASE
                    WHEN EXISTS
                    (
                        SELECT 1
                        FROM dbo.PARKING_TICKET AS T
                        WHERE T.SpaceID = S.SpaceID
                          AND T.ExitDateTime IS NULL
                    )
                        THEN 'OCCUPIED'
                    WHEN EXISTS
                    (
                        SELECT 1
                        FROM dbo.PARKING_MONTHLY_RESERVATION AS R
                        INNER JOIN dbo.PARKING_MONTHLY_PAYMENT AS MP
                            ON MP.MonthlyPaymentID = R.MonthlyPaymentID
                        INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS MC
                            ON MC.ContractID = MP.ContractID
                        WHERE R.SpaceID = S.SpaceID
                          AND MP.PaymentStatus = 'COMPLETED'
                          AND MC.ContractStatus = 'ACTIVE'
                          AND MC.CancelledAt IS NULL
                          AND MC.StartDate <= @Today
                          AND MC.EndDate >= @Today
                          AND R.EffectiveFromUTC <= @Now
                          AND R.EffectiveToUTC > @Now
                    )
                        THEN 'RESERVED'
                    ELSE 'AVAILABLE'
                END,
            UpdatedAt = @Now,
            UpdatedBy = @p_uid
        FROM dbo.PARKING_SPACE AS S
        WHERE S.SpaceID = @p_spaceID;

        IF @@ROWCOUNT <> 1
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = 'Could not update the reserved parking space';
            RETURN;
        END;

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;
        SET @Result =
            'Monthly payment and space reservation recorded successfully';

        SELECT
            @p_monthlyPaymentID AS MonthlyPaymentID,
            @PaymentNumber AS PaymentNumber,
            @ReceiptNumber AS ReceiptNumber,
            @p_contractID AS ContractID,
            @ReservationID AS ReservationID,
            @p_spaceID AS SpaceID,
            @p_periodStartDate AS PeriodStartDate,
            @p_periodEndDate AS PeriodEndDate,
            @EffectiveFromUTC AS EffectiveFromUTC,
            @EffectiveToUTC AS EffectiveToUTC,
            @p_amount AS Amount,
            @p_paymentMethod AS PaymentMethod,
            @Now AS PaymentDateTime;

    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while processing monthly payments';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO