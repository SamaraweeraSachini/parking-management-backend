USE [VehicleParkingManagementDB];
GO

/* DAILY vehicle entry. @SpaceID is optional: NULL allocates the first
   available, active space assigned to the vehicle type. Customers can be
   linked separately; casual daily vehicles may have CustomerID = NULL.
   The API must pass the authenticated operator's ID. */
CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Daily_Entry
    @VehicleNumber VARCHAR(30),
    @VehicleTypeID INT,
    @OperatorUserID INT,
    @SpaceID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @VehicleNumber = UPPER(NULLIF(LTRIM(RTRIM(@VehicleNumber)), ''));

    IF @VehicleNumber IS NULL OR @VehicleTypeID IS NULL OR @OperatorUserID IS NULL
    BEGIN
        SELECT 400 AS StatusCode,
               N'Vehicle number, vehicle type, and operator are required.' AS Message;
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
        IF NOT EXISTS (SELECT 1 FROM dbo.PARKING_VEHICLE_TYPE
                       WHERE VehicleTypeID = @VehicleTypeID AND ActiveStatus = 1)
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 404 AS StatusCode, N'Active vehicle type not found.' AS Message;
            RETURN;
        END;

        DECLARE @VehicleID INT, @ExistingTypeID INT, @VehicleActive BIT;
        SELECT @VehicleID = VehicleID, @ExistingTypeID = VehicleTypeID,
               @VehicleActive = ActiveStatus
        FROM dbo.PARKING_CUSTOMER_VEHICLE WITH (UPDLOCK, HOLDLOCK)
        WHERE VehicleNumber = @VehicleNumber;

        IF @VehicleID IS NOT NULL AND (@ExistingTypeID <> @VehicleTypeID OR @VehicleActive = 0)
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 409 AS StatusCode,
                   N'Existing vehicle is inactive or its registered vehicle type differs.' AS Message;
            RETURN;
        END;
        IF @VehicleID IS NULL
        BEGIN
            INSERT dbo.PARKING_CUSTOMER_VEHICLE
                (CustomerID, VehicleTypeID, VehicleNumber, CreatedAt, CreatedBy)
            VALUES (NULL, @VehicleTypeID, @VehicleNumber, SYSUTCDATETIME(), @OperatorUserID);
            SET @VehicleID = CONVERT(INT, SCOPE_IDENTITY());
        END;

        IF EXISTS (SELECT 1 FROM dbo.PARKING_TICKET WITH (UPDLOCK, HOLDLOCK)
                   WHERE VehicleID = @VehicleID AND ExitDateTime IS NULL)
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 409 AS StatusCode, N'Vehicle already has an open parking visit.' AS Message;
            RETURN;
        END;

        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
        DECLARE @HourlyRateID INT, @DailyRateID INT,
                @HourlyRate DECIMAL(12,2), @DailyRate DECIMAL(12,2);

        SELECT @HourlyRateID = RateID, @HourlyRate = RateAmount
        FROM dbo.PARKING_RATE WITH (HOLDLOCK)
        WHERE VehicleTypeID = @VehicleTypeID AND RateUnit = 'HOURLY'
          AND ActiveStatus = 1 AND EffectiveFrom <= @Now
          AND (EffectiveTo IS NULL OR EffectiveTo > @Now);
        SELECT @DailyRateID = RateID, @DailyRate = RateAmount
        FROM dbo.PARKING_RATE WITH (HOLDLOCK)
        WHERE VehicleTypeID = @VehicleTypeID AND RateUnit = 'DAILY'
          AND ActiveStatus = 1 AND EffectiveFrom <= @Now
          AND (EffectiveTo IS NULL OR EffectiveTo > @Now);

        IF @HourlyRateID IS NULL OR @DailyRateID IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 409 AS StatusCode,
                   N'Configure an active hourly and daily rate for this vehicle type first.' AS Message;
            RETURN;
        END;

        IF @SpaceID IS NULL
            SELECT TOP (1) @SpaceID = SpaceID
            FROM dbo.PARKING_SPACE WITH (UPDLOCK, READPAST, ROWLOCK)
            WHERE VehicleTypeID = @VehicleTypeID AND ActiveStatus = 1
              AND SpaceStatus = 'AVAILABLE'
            ORDER BY SpaceCode;

        IF @SpaceID IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 409 AS StatusCode, N'No matching available parking space.' AS Message;
            RETURN;
        END;

        UPDATE dbo.PARKING_SPACE
        SET SpaceStatus = 'OCCUPIED', UpdatedAt = @Now, UpdatedBy = @OperatorUserID
        WHERE SpaceID = @SpaceID AND VehicleTypeID = @VehicleTypeID
          AND ActiveStatus = 1 AND SpaceStatus = 'AVAILABLE';
        IF @@ROWCOUNT <> 1
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 409 AS StatusCode,
                   N'Selected space is occupied, blocked, inactive, or for a different vehicle type.' AS Message;
            RETURN;
        END;

        DECLARE @TicketNumber VARCHAR(40) = 'T-' + CONVERT(VARCHAR(36), NEWID());
        INSERT dbo.PARKING_TICKET
            (TicketNumber, VehicleID, SpaceID,
             HourlyRateID, DailyRateID, AppliedHourlyRate, AppliedDailyRate,
             MonthlyContractID, ParkingType, EntryDateTime, TicketStatus,
             EntryOperatorID, CreatedAt, CreatedBy)
        VALUES
            (@TicketNumber, @VehicleID, @SpaceID,
             @HourlyRateID, @DailyRateID, @HourlyRate, @DailyRate,
             NULL, 'DAILY', @Now, 'OPEN',
             @OperatorUserID, @Now, @OperatorUserID);

        DECLARE @TicketID INT = CONVERT(INT, SCOPE_IDENTITY());
        COMMIT TRANSACTION;

        SELECT 201 AS StatusCode, N'Vehicle entered.' AS Message,
               @TicketID AS TicketID, @TicketNumber AS TicketNumber,
               @VehicleID AS VehicleID, @VehicleNumber AS VehicleNumber,
               @SpaceID AS SpaceID, @Now AS EntryDateTime,
               @HourlyRateID AS HourlyRateID, @DailyRateID AS DailyRateID,
               @HourlyRate AS AppliedHourlyRate, @DailyRate AS AppliedDailyRate;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
