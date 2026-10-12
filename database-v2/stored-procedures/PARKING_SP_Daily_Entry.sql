USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Daily_Entry
(
    @ActionType         INT,

    @p_vehicleNumber    VARCHAR(30) = NULL,
    @p_vehicleTypeID    INT = NULL,
    @p_spaceID          INT = NULL,
    @p_customerName     NVARCHAR(200) = NULL,
    @p_mobileNumber     VARCHAR(20) = NULL,
    @p_entryDescription NVARCHAR(500) = NULL,
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

        SET @p_customerName =
            NULLIF(LTRIM(RTRIM(@p_customerName)), N'');

        SET @p_mobileNumber =
            NULLIF(LTRIM(RTRIM(@p_mobileNumber)), '');

        SET @p_entryDescription =
            NULLIF(LTRIM(RTRIM(@p_entryDescription)), N'');

        /* ====================================================
           1. Validate inputs
           ==================================================== */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType <> 1
            SET @ValidationMessage =
                'Invalid action type. Use 1 for daily entry.';
        ELSE IF @p_vehicleNumber IS NULL
            SET @ValidationMessage = 'Vehicle number is required.';
        ELSE IF @p_vehicleTypeID IS NULL OR @p_vehicleTypeID <= 0
            SET @ValidationMessage =
                'A valid vehicle type ID is required.';
        ELSE IF @p_spaceID IS NOT NULL AND @p_spaceID <= 0
            SET @ValidationMessage =
                'Space ID must be positive or NULL.';
        ELSE IF @p_mobileNumber IS NOT NULL
            AND LEN(@p_mobileNumber) NOT BETWEEN 7 AND 20
            SET @ValidationMessage =
                'Mobile number must contain 7-20 characters.';
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
           2. Lock parking operations and check permissions
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
            FROM dbo.PARKING_VEHICLE_TYPE WITH (HOLDLOCK)
            WHERE VehicleTypeID = @p_vehicleTypeID
              AND ActiveStatus = 1
        )
            SET @ValidationMessage =
                'Active vehicle type was not found.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           3. Check the vehicle and monthly coverage
           ==================================================== */

        DECLARE
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @Today DATE,
            @VehicleID INT,
            @StoredTypeID INT,
            @VehicleActive BIT;

        SET @Today =
            CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

        SELECT
            @VehicleID = VehicleID,
            @StoredTypeID = VehicleTypeID,
            @VehicleActive = ActiveStatus
        FROM dbo.PARKING_CUSTOMER_VEHICLE WITH (UPDLOCK, HOLDLOCK)
        WHERE VehicleNumber = @p_vehicleNumber;

        IF @VehicleID IS NOT NULL
           AND
           (
               @VehicleActive = 0
               OR @StoredTypeID <> @p_vehicleTypeID
           )
            SET @ValidationMessage =
                'Existing vehicle is inactive or belongs to another vehicle category.';
        ELSE IF EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_TICKET
            WHERE VehicleID = @VehicleID
              AND ExitDateTime IS NULL
        )
            SET @ValidationMessage = 'This vehicle is already parked.';
        ELSE IF EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_MONTHLY_CONTRACT AS MC
            INNER JOIN dbo.PARKING_MONTHLY_PAYMENT AS MP
                ON MP.ContractID = MC.ContractID
            INNER JOIN dbo.PARKING_MONTHLY_RESERVATION AS R
                ON R.MonthlyPaymentID = MP.MonthlyPaymentID
            INNER JOIN dbo.PARKING_CUSTOMER AS C
                ON C.CustomerID = MC.CustomerID
            INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS V
                ON V.VehicleID = MC.VehicleID
               AND V.CustomerID = MC.CustomerID
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
              AND R.EffectiveToUTC > @Now
        )
            SET @ValidationMessage =
                'This vehicle has valid paid monthly coverage. Use monthly entry.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           4. Find effective hourly and daily rates
           ==================================================== */

        DECLARE
            @HourlyRateID INT,
            @DailyRateID INT,
            @HourlyRate DECIMAL(12,2),
            @DailyRate DECIMAL(12,2),
            @HourlyCount INT,
            @DailyCount INT;

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
        FROM dbo.PARKING_RATE WITH (HOLDLOCK)
        WHERE VehicleTypeID = @p_vehicleTypeID
          AND RateUnit IN ('HOURLY', 'DAILY')
          AND ActiveStatus = 1
          AND EffectiveFrom <= @Now
          AND (EffectiveTo IS NULL OR EffectiveTo > @Now);

        IF @HourlyCount <> 1 OR @DailyCount <> 1
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result =
                'Configure one effective hourly and daily rate first.';
            RETURN;
        END;

        /* ====================================================
           5. Select a compatible parking space
           Exclude current and future paid monthly bookings.
           ==================================================== */

        DECLARE @SelectedSpaceID INT;

        SELECT TOP (1)
            @SelectedSpaceID = S.SpaceID
        FROM dbo.PARKING_SPACE AS S WITH (UPDLOCK, HOLDLOCK)
        WHERE S.VehicleTypeID = @p_vehicleTypeID
          AND S.ActiveStatus = 1
          AND S.SpaceStatus IN ('AVAILABLE', 'RESERVED')
          AND (@p_spaceID IS NULL OR S.SpaceID = @p_spaceID)
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.PARKING_TICKET AS T
              WHERE T.SpaceID = S.SpaceID
                AND T.ExitDateTime IS NULL
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
                AND R.EffectiveToUTC > @Now
                AND MP.PaymentStatus = 'COMPLETED'
                AND MC.ContractStatus = 'ACTIVE'
                AND MC.CancelledAt IS NULL
          )
        ORDER BY S.SpaceCode, S.SpaceID;

        IF @SelectedSpaceID IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result =
                'No compatible unoccupied space without a paid monthly booking is available.';
            RETURN;
        END;

        SET @p_spaceID = @SelectedSpaceID;

        /* ====================================================
           6. Register a new vehicle if needed
           ==================================================== */

        IF @VehicleID IS NULL
        BEGIN
            INSERT dbo.PARKING_CUSTOMER_VEHICLE
            (
                VehicleTypeID,
                VehicleNumber,
                CreatedAt,
                CreatedBy
            )
            VALUES
            (
                @p_vehicleTypeID,
                @p_vehicleNumber,
                @Now,
                @p_uid
            );

            SET @VehicleID = CONVERT(INT, SCOPE_IDENTITY());
        END;

        -- Use registered contact details when none were supplied.
        SELECT
            @p_customerName =
                COALESCE(@p_customerName, C.CustomerName),
            @p_mobileNumber =
                COALESCE(@p_mobileNumber, C.MobileNumber)
        FROM dbo.PARKING_CUSTOMER_VEHICLE AS V
        LEFT JOIN dbo.PARKING_CUSTOMER AS C
            ON C.CustomerID = V.CustomerID
        WHERE V.VehicleID = @VehicleID;

        /* ====================================================
           7. Create the ticket and occupy the space
           ==================================================== */

        DECLARE @TicketSequence BIGINT =
            NEXT VALUE FOR dbo.PARKING_TICKET_SEQUENCE;

        DECLARE @TicketNumber VARCHAR(40) =
            'D-' + CONVERT(VARCHAR(20), @TicketSequence);

        INSERT dbo.PARKING_TICKET
        (
            TicketNumber,
            VehicleID,
            SpaceID,
            ParkingType,
            HourlyRateID,
            DailyRateID,
            AppliedHourlyRate,
            AppliedDailyRate,
            CustomerName,
            MobileNumber,
            EntryDescription,
            EntryDateTime,
            EntryOperatorID,
            CreatedAt,
            CreatedBy
        )
        VALUES
        (
            @TicketNumber,
            @VehicleID,
            @p_spaceID,
            'DAILY',
            @HourlyRateID,
            @DailyRateID,
            @HourlyRate,
            @DailyRate,
            @p_customerName,
            @p_mobileNumber,
            @p_entryDescription,
            @Now,
            @p_uid,
            @Now,
            @p_uid
        );

        DECLARE @TicketID INT =
            CONVERT(INT, SCOPE_IDENTITY());

        UPDATE dbo.PARKING_SPACE
        SET
            SpaceStatus = 'OCCUPIED',
            BlockReason = NULL,
            UpdatedAt = @Now,
            UpdatedBy = @p_uid
        WHERE SpaceID = @p_spaceID
          AND SpaceStatus IN ('AVAILABLE', 'RESERVED')
          AND ActiveStatus = 1;

        IF @@ROWCOUNT <> 1
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = 'Could not allocate the parking space.';
            RETURN;
        END;

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;
        SET @Result = 'Daily vehicle entered successfully';

        SELECT
            @TicketID AS TicketID,
            @TicketNumber AS TicketNumber,
            @VehicleID AS VehicleID,
            @p_vehicleNumber AS VehicleNumber,
            @p_spaceID AS SpaceID,
            @Now AS EntryDateTime;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while processing daily vehicle entry';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO