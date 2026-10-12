USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Monthly_Attendance
(
    @ActionType         INT,

    @p_vehicleNumber    VARCHAR(30) = NULL,
    @p_ticketID         INT = NULL,
    @p_entryDescription NVARCHAR(500) = NULL,
    @p_searchTerm       NVARCHAR(200) = NULL,
    @p_fromDate         DATE = NULL,
    @p_toDate           DATE = NULL,
    @p_onlyCurrent      BIT = 0,
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

        SET @p_vehicleNumber =
            UPPER(NULLIF(LTRIM(RTRIM(@p_vehicleNumber)), ''));

        SET @p_entryDescription =
            NULLIF(LTRIM(RTRIM(@p_entryDescription)), N'');

        SET @p_searchTerm =
            NULLIF(LTRIM(RTRIM(@p_searchTerm)), N'');

        SET @p_onlyCurrent = ISNULL(@p_onlyCurrent, 0);

        /* ============================================================
           Shared Input Validation
           ============================================================ */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType NOT BETWEEN 1 AND 5
            SET @ValidationMessage = 'Invalid action type';

        ELSE IF @ActionType IN (1, 2)
             AND @p_vehicleNumber IS NULL
            SET @ValidationMessage = 'Vehicle number is required';

        ELSE IF @ActionType = 3
             AND (@p_ticketID IS NULL OR @p_ticketID <= 0)
            SET @ValidationMessage = 'A valid ticket ID is required';

        ELSE IF @ActionType = 4
             AND @p_ticketID IS NOT NULL
             AND @p_ticketID <= 0
            SET @ValidationMessage =
                'Ticket ID must be positive or NULL';

        ELSE IF @ActionType = 4
             AND @p_fromDate IS NOT NULL
             AND @p_toDate IS NOT NULL
             AND @p_toDate < @p_fromDate
            SET @ValidationMessage =
                'End date cannot be earlier than start date';

        ELSE IF @ActionType = 4
             AND @p_toDate = CONVERT(DATE, '99991231', 112)
            SET @ValidationMessage =
                'The selected end date is outside the supported report range';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ============================================================
           4. Get / Search Monthly Visit History
           ============================================================ */

        IF @ActionType = 4
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

            DECLARE @FromUTC DATETIME2(0) =
                CASE
                    WHEN @p_fromDate IS NOT NULL
                    THEN DATEADD
                    (
                        MINUTE,
                        -330,
                        CONVERT(DATETIME2(0), @p_fromDate)
                    )
                END;

            DECLARE @ToUTC DATETIME2(0) =
                CASE
                    WHEN @p_toDate IS NOT NULL
                    THEN DATEADD
                    (
                        MINUTE,
                        -330,
                        DATEADD
                        (
                            DAY,
                            1,
                            CONVERT(DATETIME2(0), @p_toDate)
                        )
                    )
                END;

            SELECT
                T.TicketID,
                T.TicketNumber,
                T.VehicleID,
                V.VehicleNumber,
                VT.TypeName AS VehicleType,
                T.MonthlyContractID AS ContractID,
                MC.ContractNumber,
                MC.CustomerID,
                COALESCE(T.CustomerName, C.CustomerName)
                    AS CustomerName,
                COALESCE(T.MobileNumber, C.MobileNumber)
                    AS MobileNumber,
                T.SpaceID,
                S.SpaceCode,
                T.ParkingType,
                T.EntryDateTime,
                T.ExitDateTime,
                T.TicketStatus,
                T.EntryDescription,
                T.EntryOperatorID,
                T.ExitOperatorID,
                T.CalculatedAmount
            FROM dbo.PARKING_TICKET AS T
            INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS V
                ON V.VehicleID = T.VehicleID
            INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
                ON VT.VehicleTypeID = V.VehicleTypeID
            INNER JOIN dbo.PARKING_SPACE AS S
                ON S.SpaceID = T.SpaceID
            INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS MC
                ON MC.ContractID = T.MonthlyContractID
            INNER JOIN dbo.PARKING_CUSTOMER AS C
                ON C.CustomerID = MC.CustomerID
            WHERE T.ParkingType = 'MONTHLY'
              AND
              (
                  @p_ticketID IS NULL
                  OR T.TicketID = @p_ticketID
              )
              AND
              (
                  @p_vehicleNumber IS NULL
                  OR V.VehicleNumber = @p_vehicleNumber
              )
              AND (@p_onlyCurrent = 0 OR T.ExitDateTime IS NULL)
              AND (@FromUTC IS NULL OR T.EntryDateTime >= @FromUTC)
              AND (@ToUTC IS NULL OR T.EntryDateTime < @ToUTC)
              AND
              (
                  @p_searchTerm IS NULL
                  OR CHARINDEX
                     (
                         UPPER(@p_searchTerm),
                         UPPER(T.TicketNumber)
                     ) > 0
                  OR CHARINDEX
                     (
                         UPPER(@p_searchTerm),
                         UPPER(V.VehicleNumber)
                     ) > 0
                  OR CHARINDEX
                     (
                         UPPER(@p_searchTerm),
                         UPPER(COALESCE(T.CustomerName, C.CustomerName))
                     ) > 0
                  OR CHARINDEX
                     (
                         @p_searchTerm,
                         COALESCE(T.MobileNumber, C.MobileNumber)
                     ) > 0
              )
            ORDER BY T.EntryDateTime DESC, T.TicketID DESC;

            SET @ResultStatusCode = 1;
            SET @Result =
                'Monthly attendance details retrieved successfully';
            RETURN;
        END;

        /* ============================================================
           Shared Transaction And Caller Validation
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
            SET @Result = 'Parking operations are busy. Please retry';
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

        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

        DECLARE @Today DATE =
            CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

        DECLARE
            @VehicleID INT,
            @VehicleTypeID INT,
            @ContractID INT,
            @SpaceID INT,
            @SpaceCode VARCHAR(30),
            @SpaceStatus VARCHAR(20),
            @CustomerName NVARCHAR(200),
            @MobileNumber VARCHAR(20),
            @TicketNumber VARCHAR(40);

        /* ============================================================
           1. Check Monthly Entry Eligibility
           2. Register Monthly Entry
           ============================================================ */

        IF @ActionType IN (1, 2)
        BEGIN
            SET @ValidationMessage = NULL;

            SELECT
                @VehicleID = V.VehicleID,
                @VehicleTypeID = V.VehicleTypeID
            FROM dbo.PARKING_CUSTOMER_VEHICLE AS V
                WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.PARKING_CUSTOMER AS C
                WITH (HOLDLOCK)
                ON C.CustomerID = V.CustomerID
            INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
                WITH (HOLDLOCK)
                ON VT.VehicleTypeID = V.VehicleTypeID
            WHERE V.VehicleNumber = @p_vehicleNumber
              AND V.ActiveStatus = 1
              AND C.ActiveStatus = 1
              AND VT.ActiveStatus = 1;

            IF @VehicleID IS NULL
                SET @ValidationMessage =
                    'An active registered monthly customer vehicle was not found';

            IF @ValidationMessage IS NULL
            BEGIN
                DECLARE @CoverageCount INT;

                SELECT
                    @CoverageCount = COUNT(*),
                    @ContractID = MIN(MC.ContractID),
                    @SpaceID = MIN(R.SpaceID),
                    @CustomerName = MIN(C.CustomerName),
                    @MobileNumber = MIN(C.MobileNumber)
                FROM dbo.PARKING_MONTHLY_CONTRACT AS MC
                    WITH (HOLDLOCK)
                INNER JOIN dbo.PARKING_CUSTOMER AS C
                    ON C.CustomerID = MC.CustomerID
                INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS V
                    ON V.VehicleID = MC.VehicleID
                   AND V.CustomerID = MC.CustomerID
                INNER JOIN dbo.PARKING_MONTHLY_PAYMENT AS MP
                    WITH (HOLDLOCK)
                    ON MP.ContractID = MC.ContractID
                INNER JOIN dbo.PARKING_MONTHLY_RESERVATION AS R
                    WITH (HOLDLOCK)
                    ON R.MonthlyPaymentID = MP.MonthlyPaymentID
                WHERE MC.VehicleID = @VehicleID
                  AND MC.ContractStatus = 'ACTIVE'
                  AND MC.CancelledAt IS NULL
                  AND MC.StartDate <= @Today
                  AND MC.EndDate >= @Today
                  AND C.ActiveStatus = 1
                  AND MP.PaymentStatus = 'COMPLETED'
                  AND MP.PeriodStartDate <= @Today
                  AND MP.PeriodEndDate >= @Today
                  AND R.EffectiveFromUTC <= @Now
                  AND R.EffectiveToUTC > @Now;

                IF @CoverageCount = 0
                    SET @ValidationMessage =
                        'No valid paid monthly reservation is effective now';

                ELSE IF @CoverageCount > 1
                    SET @ValidationMessage =
                        'Multiple effective reservations exist. An administrator must resolve them';
            END;

            IF @ValidationMessage IS NULL
            BEGIN
                SELECT
                    @SpaceCode = SpaceCode,
                    @SpaceStatus = SpaceStatus
                FROM dbo.PARKING_SPACE WITH (UPDLOCK, HOLDLOCK)
                WHERE SpaceID = @SpaceID
                  AND VehicleTypeID = @VehicleTypeID
                  AND ActiveStatus = 1;

                IF @SpaceStatus IS NULL
                    SET @ValidationMessage =
                        'The reserved space is inactive or incompatible';
            END;

            IF @ValidationMessage IS NOT NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;

                SET @ResultStatusCode = -1;
                SET @Result = @ValidationMessage;
                RETURN;
            END;

            DECLARE @CanEnter BIT = 1;
            DECLARE @EligibilityMessage VARCHAR(500) =
                'Valid paid monthly reservation found';

            IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_TICKET
                WHERE VehicleID = @VehicleID
                  AND ExitDateTime IS NULL
            )
            BEGIN
                SET @CanEnter = 0;
                SET @EligibilityMessage =
                    'This vehicle is already parked';
            END;
            ELSE IF @SpaceStatus NOT IN ('AVAILABLE', 'RESERVED')
                 OR EXISTS
                 (
                     SELECT 1
                     FROM dbo.PARKING_TICKET
                     WHERE SpaceID = @SpaceID
                       AND ExitDateTime IS NULL
                 )
            BEGIN
                SET @CanEnter = 0;
                SET @EligibilityMessage =
                    'The reserved space is occupied or blocked';
            END;

            IF @ActionType = 1
            BEGIN
                COMMIT TRANSACTION;
                SET @StartedTransaction = 0;

                SET @ResultStatusCode = 1;
                SET @Result = @EligibilityMessage;

                SELECT
                    @CanEnter AS CanEnter,
                    @VehicleID AS VehicleID,
                    @p_vehicleNumber AS VehicleNumber,
                    @VehicleTypeID AS VehicleTypeID,
                    @CustomerName AS CustomerName,
                    @MobileNumber AS MobileNumber,
                    @ContractID AS ContractID,
                    @SpaceID AS SpaceID,
                    @SpaceCode AS SpaceCode;

                RETURN;
            END;

            IF @CanEnter = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;

                SET @ResultStatusCode = -1;
                SET @Result = @EligibilityMessage;
                RETURN;
            END;

            DECLARE @TicketSequence BIGINT =
                NEXT VALUE FOR dbo.PARKING_TICKET_SEQUENCE;

            SET @TicketNumber =
                'M-' + CONVERT(VARCHAR(20), @TicketSequence);

            INSERT INTO dbo.PARKING_TICKET
            (
                TicketNumber,
                VehicleID,
                SpaceID,
                ParkingType,
                MonthlyContractID,
                CustomerName,
                MobileNumber,
                EntryDescription,
                EntryDateTime,
                CalculatedAmount,
                EntryOperatorID,
                CreatedAt,
                CreatedBy
            )
            VALUES
            (
                @TicketNumber,
                @VehicleID,
                @SpaceID,
                'MONTHLY',
                @ContractID,
                @CustomerName,
                @MobileNumber,
                @p_entryDescription,
                @Now,
                0,
                @p_uid,
                @Now,
                @p_uid
            );

            SET @p_ticketID = CONVERT(INT, SCOPE_IDENTITY());

            UPDATE dbo.PARKING_SPACE
            SET
                SpaceStatus = 'OCCUPIED',
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE SpaceID = @SpaceID
              AND SpaceStatus IN ('AVAILABLE', 'RESERVED')
              AND ActiveStatus = 1;

            IF @@ROWCOUNT <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;

                SET @ResultStatusCode = -1;
                SET @Result = 'Could not occupy the reserved space';
                RETURN;
            END;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = 1;
            SET @Result = 'Monthly vehicle entered successfully';

            SELECT
                @p_ticketID AS TicketID,
                @TicketNumber AS TicketNumber,
                @VehicleID AS VehicleID,
                @ContractID AS ContractID,
                @SpaceID AS SpaceID,
                @SpaceCode AS SpaceCode,
                @Now AS EntryDateTime;

            RETURN;
        END;

        /* ============================================================
           3. Register Monthly Exit
           ============================================================ */

        IF @ActionType = 3
        BEGIN
            DECLARE
                @TicketStatus VARCHAR(30),
                @ParkingType VARCHAR(20),
                @EntryDateTime DATETIME2(0),
                @ExistingExit DATETIME2(0);

            SELECT
                @TicketNumber = TicketNumber,
                @VehicleID = VehicleID,
                @ContractID = MonthlyContractID,
                @SpaceID = SpaceID,
                @TicketStatus = TicketStatus,
                @ParkingType = ParkingType,
                @EntryDateTime = EntryDateTime,
                @ExistingExit = ExitDateTime
            FROM dbo.PARKING_TICKET WITH (UPDLOCK, HOLDLOCK)
            WHERE TicketID = @p_ticketID;

            SET @ValidationMessage = NULL;

            IF @TicketNumber IS NULL
                SET @ValidationMessage =
                    'Parking ticket was not found';

            ELSE IF @ParkingType <> 'MONTHLY'
                 OR @TicketStatus <> 'OPEN'
                 OR @ExistingExit IS NOT NULL
                SET @ValidationMessage =
                    'Only an open monthly visit can use this exit operation';

            ELSE IF @EntryDateTime > @Now
                SET @ValidationMessage =
                    'Entry time is later than server time';

            IF @ValidationMessage IS NOT NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;

                SET @ResultStatusCode = -1;
                SET @Result = @ValidationMessage;
                RETURN;
            END;

            DECLARE @ExitSpaceStatus VARCHAR(20) = 'AVAILABLE';

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
                  AND MC.StartDate <= @Today
                  AND MC.EndDate >= @Today
                  AND MP.PeriodStartDate <= @Today
                  AND MP.PeriodEndDate >= @Today
                  AND R.EffectiveFromUTC <= @Now
                  AND R.EffectiveToUTC > @Now
            )
                SET @ExitSpaceStatus = 'RESERVED';

            UPDATE dbo.PARKING_TICKET
            SET
                ExitDateTime = @Now,
                ExitOperatorID = @p_uid,
                TicketStatus = 'CLOSED',
                CalculatedAmount = 0,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE TicketID = @p_ticketID
              AND TicketStatus = 'OPEN'
              AND ExitDateTime IS NULL;

            IF @@ROWCOUNT <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;

                SET @ResultStatusCode = -1;
                SET @Result = 'Could not close the monthly visit';
                RETURN;
            END;

            UPDATE dbo.PARKING_SPACE
            SET
                SpaceStatus = @ExitSpaceStatus,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE SpaceID = @SpaceID
              AND SpaceStatus = 'OCCUPIED';

            IF @@ROWCOUNT <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;

                SET @ResultStatusCode = -1;
                SET @Result =
                    'Could not release the occupied monthly space';
                RETURN;
            END;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = 1;
            SET @Result = 'Monthly vehicle exited successfully';

            SELECT
                @p_ticketID AS TicketID,
                @TicketNumber AS TicketNumber,
                @SpaceID AS SpaceID,
                @ExitSpaceStatus AS SpaceStatus,
                @Now AS ExitDateTime;

            RETURN;
        END;

        /* ============================================================
           5. Reconcile Expired Contracts And Reservation Statuses
           ============================================================ */

        UPDATE dbo.PARKING_MONTHLY_CONTRACT
        SET
            ContractStatus = 'EXPIRED',
            UpdatedAt = @Now,
            UpdatedBy = @p_uid
        WHERE ContractStatus = 'ACTIVE'
          AND EndDate < @Today;

        DECLARE @ExpiredContracts INT = @@ROWCOUNT;

        UPDATE S
        SET
            SpaceStatus = StateNow.NewStatus,
            UpdatedAt = @Now,
            UpdatedBy = @p_uid
        FROM dbo.PARKING_SPACE AS S
        CROSS APPLY
        (
            SELECT
                CASE
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
                          AND MP.PeriodStartDate <= @Today
                          AND MP.PeriodEndDate >= @Today
                          AND R.EffectiveFromUTC <= @Now
                          AND R.EffectiveToUTC > @Now
                    )
                        THEN 'RESERVED'
                    ELSE 'AVAILABLE'
                END AS NewStatus
        ) AS StateNow
        WHERE S.SpaceStatus IN ('AVAILABLE', 'RESERVED')
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.PARKING_TICKET AS T
              WHERE T.SpaceID = S.SpaceID
                AND T.ExitDateTime IS NULL
          )
          AND S.SpaceStatus <> StateNow.NewStatus;

        DECLARE @UpdatedSpaces INT = @@ROWCOUNT;

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;
        SET @Result = 'Monthly statuses reconciled successfully';

        SELECT
            @ExpiredContracts AS ExpiredContracts,
            @UpdatedSpaces AS UpdatedSpaces;

    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while processing monthly attendance';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO