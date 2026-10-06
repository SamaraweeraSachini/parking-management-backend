USE [VehicleParkingManagementDB];
GO

/* Action 1: list rates (active by default; set @IncludeInactive=1 for admin).
   Action 2: get by ID.
   Action 3: create rate.
   Action 4: update rate; existing ticket amounts must be snapshotted separately.
   Action 5: deactivate rate.
   Action 6: reactivate rate.
   Action 7: fetch active HOURLY and DAILY rates for a vehicle type. */

CREATE PROCEDURE dbo.PARKING_SP_Rate
    @ActionType INT,
    @RateID INT = NULL,
    @VehicleTypeID INT = NULL,
    @RateName NVARCHAR(100) = NULL,
    @RateAmount DECIMAL(12,2) = NULL,
    @RateUnit VARCHAR(20) = NULL,
    @EffectiveFrom DATETIME2(0) = NULL,
    @EffectiveTo DATETIME2(0) = NULL,
    @PerformedByUserID INT = NULL,
    @IncludeInactive BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @RateName = NULLIF(LTRIM(RTRIM(@RateName)), N'');
    SET @RateUnit = UPPER(NULLIF(LTRIM(RTRIM(@RateUnit)), ''));

    IF @ActionType NOT BETWEEN 1 AND 7
    BEGIN
        SELECT 400 AS StatusCode, N'Invalid ActionType.' AS Message;
        RETURN;
    END;

    IF @ActionType = 1
    BEGIN
        SELECT RateID, VehicleTypeID, RateName, RateAmount, RateUnit,
               EffectiveFrom, EffectiveTo, ActiveStatus,
               CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
        FROM dbo.PARKING_RATE
        WHERE (@IncludeInactive = 1 OR ActiveStatus = 1)
          AND (@VehicleTypeID IS NULL OR VehicleTypeID = @VehicleTypeID)
        ORDER BY VehicleTypeID, RateUnit, RateID;
        RETURN;
    END;

    IF @ActionType = 2
    BEGIN
        IF @RateID IS NULL
        BEGIN
            SELECT 400 AS StatusCode, N'RateID is required.' AS Message;
            RETURN;
        END;
        SELECT RateID, VehicleTypeID, RateName, RateAmount, RateUnit,
               EffectiveFrom, EffectiveTo, ActiveStatus,
               CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
        FROM dbo.PARKING_RATE WHERE RateID = @RateID;
        RETURN;
    END;

    IF @ActionType = 7
    BEGIN
        IF @VehicleTypeID IS NULL
        BEGIN
            SELECT 400 AS StatusCode, N'VehicleTypeID is required.' AS Message;
            RETURN;
        END;
        SELECT RateID, VehicleTypeID, RateName, RateAmount, RateUnit,
               EffectiveFrom, EffectiveTo
        FROM dbo.PARKING_RATE
        WHERE VehicleTypeID = @VehicleTypeID
          AND ActiveStatus = 1
          AND EffectiveFrom <= SYSUTCDATETIME()
          AND (EffectiveTo IS NULL OR EffectiveTo > SYSUTCDATETIME())
        ORDER BY RateUnit;
        RETURN;
    END;

    /* Writes require an active administrator. The API must independently
       authorize the caller and derive this ID from its authenticated identity. */
    IF NOT EXISTS (SELECT 1 FROM dbo.PARKING_USER
                   WHERE UserID = @PerformedByUserID
                     AND UserRole = 'A' AND ActiveStatus = 1)
    BEGIN
        SELECT 403 AS StatusCode, N'An active administrator is required.' AS Message;
        RETURN;
    END;

    IF @ActionType IN (3, 4)
    BEGIN
        IF @VehicleTypeID IS NULL OR @RateName IS NULL OR @RateAmount IS NULL
           OR @RateUnit NOT IN ('HOURLY', 'DAILY') OR @RateUnit IS NULL
        BEGIN
            SELECT 400 AS StatusCode,
                   N'Vehicle type, rate name, amount, and HOURLY/DAILY unit are required.' AS Message;
            RETURN;
        END;
        IF @RateAmount < 0 OR (@EffectiveTo IS NOT NULL AND
                              @EffectiveTo <= COALESCE(@EffectiveFrom,
                                  (SELECT EffectiveFrom FROM dbo.PARKING_RATE WHERE RateID = @RateID),
                                  SYSUTCDATETIME()))
        BEGIN
            SELECT 400 AS StatusCode, N'Invalid amount or effective period.' AS Message;
            RETURN;
        END;
        IF NOT EXISTS (SELECT 1 FROM dbo.PARKING_VEHICLE_TYPE
                       WHERE VehicleTypeID = @VehicleTypeID AND ActiveStatus = 1)
        BEGIN
            SELECT 404 AS StatusCode, N'Active vehicle type not found.' AS Message;
            RETURN;
        END;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @ActionType = 3
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.PARKING_RATE WITH (UPDLOCK, HOLDLOCK)
                       WHERE VehicleTypeID = @VehicleTypeID
                         AND RateUnit = @RateUnit AND ActiveStatus = 1)
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT 409 AS StatusCode, N'An active rate already exists for this vehicle type and unit.' AS Message;
                RETURN;
            END;
            INSERT dbo.PARKING_RATE
                (VehicleTypeID, RateName, RateAmount, RateUnit,
                 EffectiveFrom, EffectiveTo, ActiveStatus, CreatedAt, CreatedBy)
            VALUES
                (@VehicleTypeID, @RateName, @RateAmount, @RateUnit,
                 COALESCE(@EffectiveFrom, SYSUTCDATETIME()), @EffectiveTo,
                 1, SYSUTCDATETIME(), @PerformedByUserID);
            DECLARE @NewRateID INT = CONVERT(INT, SCOPE_IDENTITY());
            COMMIT TRANSACTION;
            SELECT 201 AS StatusCode, N'Rate created.' AS Message, @NewRateID AS RateID;
            RETURN;
        END;

        IF @RateID IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 400 AS StatusCode, N'RateID is required.' AS Message;
            RETURN;
        END;

        DECLARE @CurrentStatus BIT;
        SELECT @CurrentStatus = ActiveStatus
        FROM dbo.PARKING_RATE WITH (UPDLOCK, HOLDLOCK)
        WHERE RateID = @RateID;
        IF @CurrentStatus IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 404 AS StatusCode, N'Rate not found.' AS Message;
            RETURN;
        END;

        IF @ActionType = 4
        BEGIN
            IF @CurrentStatus = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT 409 AS StatusCode, N'Reactivate the rate before editing.' AS Message;
                RETURN;
            END;
            IF EXISTS (SELECT 1 FROM dbo.PARKING_RATE WITH (UPDLOCK, HOLDLOCK)
                       WHERE VehicleTypeID = @VehicleTypeID AND RateUnit = @RateUnit
                         AND ActiveStatus = 1 AND RateID <> @RateID)
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT 409 AS StatusCode, N'An active rate already exists for this vehicle type and unit.' AS Message;
                RETURN;
            END;
            UPDATE dbo.PARKING_RATE
            SET VehicleTypeID = @VehicleTypeID, RateName = @RateName,
                RateAmount = @RateAmount, RateUnit = @RateUnit,
                EffectiveFrom = COALESCE(@EffectiveFrom, EffectiveFrom),
                EffectiveTo = @EffectiveTo,
                UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @PerformedByUserID
            WHERE RateID = @RateID;
            COMMIT TRANSACTION;
            SELECT 200 AS StatusCode, N'Rate updated.' AS Message;
            RETURN;
        END;

        IF @ActionType = 5
        BEGIN
            IF @CurrentStatus = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT 409 AS StatusCode, N'Rate is already inactive.' AS Message;
                RETURN;
            END;
            UPDATE dbo.PARKING_RATE
            SET ActiveStatus = 0, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @PerformedByUserID
            WHERE RateID = @RateID;
            COMMIT TRANSACTION;
            SELECT 200 AS StatusCode, N'Rate deactivated.' AS Message;
            RETURN;
        END;

        IF @CurrentStatus = 1
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 409 AS StatusCode, N'Rate is already active.' AS Message;
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM dbo.PARKING_RATE AS r WITH (UPDLOCK, HOLDLOCK)
                   JOIN dbo.PARKING_RATE AS chosen ON chosen.RateID = @RateID
                   WHERE r.VehicleTypeID = chosen.VehicleTypeID
                     AND r.RateUnit = chosen.RateUnit
                     AND r.ActiveStatus = 1)
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 409 AS StatusCode, N'Another active rate exists for this vehicle type and unit.' AS Message;
            RETURN;
        END;
        UPDATE dbo.PARKING_RATE
        SET ActiveStatus = 1, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @PerformedByUserID
        WHERE RateID = @RateID;
        COMMIT TRANSACTION;
        SELECT 200 AS StatusCode, N'Rate reactivated.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

