USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Rate
(
    @ActionType         INT,

    @p_rateID           INT = NULL,
    @p_vehicleTypeID    INT = NULL,
    @p_rateName         NVARCHAR(100) = NULL,
    @p_rateAmount       DECIMAL(12,2) = NULL,
    @p_rateUnit         VARCHAR(20) = NULL,
    @p_effectiveFrom    DATETIME2(0) = NULL,
    @p_effectiveTo      DATETIME2(0) = NULL,
    @p_includeInactive  BIT = 0,
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

        SET @p_rateName =
            NULLIF(LTRIM(RTRIM(@p_rateName)), N'');

        SET @p_rateUnit =
            UPPER(NULLIF(LTRIM(RTRIM(@p_rateUnit)), ''));

        SET @p_includeInactive = ISNULL(@p_includeInactive, 0);

        /* ============================================================
           Shared Input Validation
           ============================================================ */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType NOT BETWEEN 1 AND 7
            SET @ValidationMessage = 'Invalid action type';

        ELSE IF @ActionType IN (2, 4, 5, 6)
             AND (@p_rateID IS NULL OR @p_rateID <= 0)
            SET @ValidationMessage = 'A valid rate ID is required';

        ELSE IF @ActionType IN (3, 7)
             AND (@p_vehicleTypeID IS NULL OR @p_vehicleTypeID <= 0)
            SET @ValidationMessage = 'A valid vehicle type ID is required';

        ELSE IF @ActionType IN (3, 4)
             AND
             (
                 @p_rateName IS NULL
                 OR @p_rateAmount IS NULL
                 OR @p_rateAmount < 0
             )
            SET @ValidationMessage =
                'Rate name and a nonnegative amount are required';

        ELSE IF @ActionType = 3
             AND
             (
                 @p_rateUnit IS NULL
                 OR @p_rateUnit NOT IN ('HOURLY', 'DAILY', 'MONTHLY')
             )
            SET @ValidationMessage =
                'Rate unit must be HOURLY, DAILY or MONTHLY';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

        /* ============================================================
           1. Get Rates
           2. Get Rate By ID
           7. Get Currently Effective Rates For Vehicle Type
           ============================================================ */

        IF @ActionType IN (1, 2, 7)
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

            IF @ActionType = 7
               AND NOT EXISTS
               (
                   SELECT 1
                   FROM dbo.PARKING_VEHICLE_TYPE
                   WHERE VehicleTypeID = @p_vehicleTypeID
                     AND ActiveStatus = 1
               )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Active vehicle type was not found';
                RETURN;
            END;

            SELECT
                RateID,
                VehicleTypeID,
                RateName,
                RateAmount,
                RateUnit,
                EffectiveFrom,
                EffectiveTo,
                ActiveStatus,
                CreatedAt,
                CreatedBy,
                UpdatedAt,
                UpdatedBy
            FROM dbo.PARKING_RATE
            WHERE
                (
                    @ActionType = 1
                    AND
                    (
                        @p_includeInactive = 1
                        OR ActiveStatus = 1
                    )
                    AND
                    (
                        @p_vehicleTypeID IS NULL
                        OR VehicleTypeID = @p_vehicleTypeID
                    )
                )
                OR
                (
                    @ActionType = 2
                    AND RateID = @p_rateID
                )
                OR
                (
                    @ActionType = 7
                    AND VehicleTypeID = @p_vehicleTypeID
                    AND ActiveStatus = 1
                    AND EffectiveFrom <= @Now
                    AND
                    (
                        EffectiveTo IS NULL
                        OR EffectiveTo > @Now
                    )
                )
            ORDER BY VehicleTypeID, RateUnit, RateID DESC;

            IF @@ROWCOUNT = 0 AND @ActionType = 2
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Rate was not found';
                RETURN;
            END;

            SET @ResultStatusCode = 1;
            SET @Result = 'Rate details retrieved successfully';
            RETURN;
        END;

        /* ============================================================
           Shared Validation For Write Operations
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
            SET @Result = 'Parking configuration is busy. Please retry';
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER WITH (HOLDLOCK)
            WHERE UserID = @p_uid
              AND UserRole = 'A'
              AND ActiveStatus = 1
        )
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = 'An active administrator is required';
            RETURN;
        END;

        SET @Now = SYSUTCDATETIME();

        DECLARE
            @CurrentActive BIT,
            @StoredTypeID INT,
            @StoredUnit VARCHAR(20),
            @StoredFrom DATETIME2(0),
            @StoredTo DATETIME2(0);

        IF @ActionType IN (4, 5, 6)
        BEGIN
            SELECT
                @CurrentActive = ActiveStatus,
                @StoredTypeID = VehicleTypeID,
                @StoredUnit = RateUnit,
                @StoredFrom = EffectiveFrom,
                @StoredTo = EffectiveTo
            FROM dbo.PARKING_RATE WITH (UPDLOCK, HOLDLOCK)
            WHERE RateID = @p_rateID;
        END;

        SET @ValidationMessage = NULL;

        IF @ActionType IN (4, 5, 6) AND @CurrentActive IS NULL
            SET @ValidationMessage = 'Rate was not found';

        ELSE IF @ActionType = 4 AND @CurrentActive = 0
            SET @ValidationMessage =
                'Only an enabled rate can be replaced';

        ELSE IF @ActionType = 5 AND @CurrentActive = 0
            SET @ValidationMessage = 'Rate is already disabled';

        ELSE IF @ActionType = 6 AND @CurrentActive = 1
            SET @ValidationMessage = 'Rate is already enabled';

        ELSE IF @ActionType = 6
             AND @StoredTo IS NOT NULL
             AND @StoredTo <= @Now
            SET @ValidationMessage =
                'An ended rate cannot be reactivated. Create a new rate';

        IF @ValidationMessage IS NULL
        BEGIN
            -- Replacement/reactivation retain the original category
            -- and rate unit.
            IF @ActionType IN (4, 6)
            BEGIN
                SET @p_vehicleTypeID = @StoredTypeID;
                SET @p_rateUnit = @StoredUnit;
            END;

            IF @ActionType = 4
                SET @p_effectiveFrom = @Now;

            IF @ActionType IN (3, 4)
            BEGIN
                SET @p_effectiveFrom =
                    ISNULL(@p_effectiveFrom, @Now);

                IF @p_effectiveTo IS NOT NULL
                   AND @p_effectiveTo <= @p_effectiveFrom
                    SET @ValidationMessage =
                        'Effective end time must be later than effective start time';
            END;

            IF @ValidationMessage IS NULL
               AND @ActionType IN (3, 4, 6)
            BEGIN
                IF NOT EXISTS
                (
                    SELECT 1
                    FROM dbo.PARKING_VEHICLE_TYPE WITH (HOLDLOCK)
                    WHERE VehicleTypeID = @p_vehicleTypeID
                      AND ActiveStatus = 1
                )
                    SET @ValidationMessage =
                        'Active vehicle type was not found';

                ELSE IF EXISTS
                (
                    SELECT 1
                    FROM dbo.PARKING_RATE WITH (UPDLOCK, HOLDLOCK)
                    WHERE VehicleTypeID = @p_vehicleTypeID
                      AND RateUnit = @p_rateUnit
                      AND ActiveStatus = 1
                      AND
                      (
                          @ActionType = 3
                          OR RateID <> @p_rateID
                      )
                )
                    SET @ValidationMessage =
                        'An enabled rate already exists for this vehicle type and unit';
            END;
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
           3. Create Rate
           4. Replace Rate With New Version
           ============================================================ */

        IF @ActionType IN (3, 4)
        BEGIN
            IF @ActionType = 4
            BEGIN
                UPDATE dbo.PARKING_RATE
                SET
                    ActiveStatus = 0,
                    EffectiveTo =
                        CASE
                            WHEN @StoredFrom < @Now
                                 AND
                                 (
                                     @StoredTo IS NULL
                                     OR @StoredTo > @Now
                                 )
                                THEN @Now
                            ELSE EffectiveTo
                        END,
                    UpdatedAt = @Now,
                    UpdatedBy = @p_uid
                WHERE RateID = @p_rateID;
            END;

            INSERT INTO dbo.PARKING_RATE
            (
                VehicleTypeID,
                RateName,
                RateAmount,
                RateUnit,
                EffectiveFrom,
                EffectiveTo,
                CreatedAt,
                CreatedBy
            )
            VALUES
            (
                @p_vehicleTypeID,
                @p_rateName,
                @p_rateAmount,
                @p_rateUnit,
                @p_effectiveFrom,
                @p_effectiveTo,
                @Now,
                @p_uid
            );

            SET @p_rateID = CONVERT(INT, SCOPE_IDENTITY());

            SET @Result =
                CASE
                    WHEN @ActionType = 3
                        THEN 'Rate created successfully'
                    ELSE 'Rate replaced successfully. Use the returned new rate ID'
                END;
        END

        /* ============================================================
           5. Deactivate Rate
           6. Reactivate Rate
           ============================================================ */

        ELSE IF @ActionType IN (5, 6)
        BEGIN
            UPDATE dbo.PARKING_RATE
            SET
                ActiveStatus =
                    CASE WHEN @ActionType = 6 THEN 1 ELSE 0 END,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE RateID = @p_rateID;

            SET @Result =
                CASE
                    WHEN @ActionType = 5
                        THEN 'Rate deactivated successfully'
                    ELSE 'Rate reactivated successfully'
                END;
        END;

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;

        SELECT @p_rateID AS RateID;

    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result = 'An error occurred while processing parking rates';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO