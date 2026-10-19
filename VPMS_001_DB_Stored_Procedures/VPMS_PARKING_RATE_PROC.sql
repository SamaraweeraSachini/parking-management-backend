USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_PARKING_RATE_PROC
    @ActionType INT,

    @p_rateID VARCHAR(10) = NULL,
    @p_vehicleTypeID VARCHAR(10) = NULL,
    @p_rateName VARCHAR(100) = NULL,
    @p_rateAmount DECIMAL(12,2) = NULL,
    @p_rateUnit VARCHAR(20) = NULL,
    @p_effectiveFrom DATETIME2(0) = NULL,
    @p_effectiveTo DATETIME2(0) = NULL,
    @p_isActive CHAR(1) = NULL,
    @p_includeInactive BIT = 0,
    @p_uid INT = NULL,

    @ResultStatusCode INT OUTPUT,
    @Result VARCHAR(MAX) OUTPUT,
    @ExceptionMessage VARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        SET @ResultStatusCode = 1;
        SET @Result = 'Success';
        SET @ExceptionMessage = NULL;

        SET @p_rateID = NULLIF(LTRIM(RTRIM(@p_rateID)), '');
        SET @p_vehicleTypeID = NULLIF(LTRIM(RTRIM(@p_vehicleTypeID)), '');
        SET @p_rateName = NULLIF(LTRIM(RTRIM(@p_rateName)), '');
        SET @p_rateUnit = UPPER(NULLIF(LTRIM(RTRIM(@p_rateUnit)), ''));

        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

        /** 1. Get parking rates **/
        IF @ActionType = 1
        BEGIN
            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An active user is required';
                RETURN;
            END;

            SELECT
                R.VPR_RATE_ID,
                R.VPR_VEHICLE_TYPE_ID,
                VT.VVT_TYPE_NAME,
                VT.VVT_WHEEL_COUNT,
                R.VPR_RATE_NAME,
                R.VPR_RATE_AMOUNT,
                R.VPR_RATE_UNIT,
                R.VPR_EFFECTIVE_FROM,
                R.VPR_EFFECTIVE_TO,
                R.VPR_IS_ACTIVE
            FROM dbo.VPMS_PARKING_RATE AS R
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = R.VPR_VEHICLE_TYPE_ID
            WHERE (ISNULL(@p_includeInactive, 0) = 1 OR R.VPR_IS_ACTIVE = 'A')
              AND (@p_vehicleTypeID IS NULL OR R.VPR_VEHICLE_TYPE_ID = @p_vehicleTypeID)
              AND (@p_rateUnit IS NULL OR R.VPR_RATE_UNIT = @p_rateUnit)
            ORDER BY R.VPR_VEHICLE_TYPE_ID, R.VPR_RATE_UNIT, R.VPR_RATE_ID;

            SET @Result = 'Parking rate list retrieved successfully';
        END

        /** 2. Get parking rate by ID **/
        ELSE IF @ActionType = 2
        BEGIN
            IF @p_rateID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking rate ID is required';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An active user is required';
                RETURN;
            END;

            SELECT
                R.VPR_RATE_ID,
                R.VPR_VEHICLE_TYPE_ID,
                VT.VVT_TYPE_NAME,
                VT.VVT_WHEEL_COUNT,
                R.VPR_RATE_NAME,
                R.VPR_RATE_AMOUNT,
                R.VPR_RATE_UNIT,
                R.VPR_EFFECTIVE_FROM,
                R.VPR_EFFECTIVE_TO,
                R.VPR_IS_ACTIVE
            FROM dbo.VPMS_PARKING_RATE AS R
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = R.VPR_VEHICLE_TYPE_ID
            WHERE R.VPR_RATE_ID = @p_rateID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking rate was not found';
                RETURN;
            END;

            SET @Result = 'Parking rate retrieved successfully';
        END

        /** 3. Add parking rate **/
        ELSE IF @ActionType = 3
        BEGIN
            IF @p_rateID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking rate ID is required';
                RETURN;
            END;

            IF @p_vehicleTypeID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type ID is required';
                RETURN;
            END;

            IF @p_rateName IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking rate name is required';
                RETURN;
            END;

            IF @p_rateAmount IS NULL OR @p_rateAmount < 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A parking rate amount of zero or greater is required';
                RETURN;
            END;

            IF @p_rateUnit IS NULL
               OR @p_rateUnit NOT IN ('H', 'D', 'M')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Rate unit must be H - Hourly / D - Daily / M - Monthly';
                RETURN;
            END;

            IF @p_isActive IS NOT NULL
               AND @p_isActive NOT IN ('A', 'I')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Status must be A - Active / I - Inactive';
                RETURN;
            END;

            SET @p_effectiveFrom = ISNULL(@p_effectiveFrom, @Now);

            IF @p_effectiveTo IS NOT NULL
               AND @p_effectiveTo <= @p_effectiveFrom
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Effective end time must be later than effective start time';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_USER_ROLE = 'AD'
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator is required';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_RATE
                WHERE VPR_RATE_ID = @p_rateID
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking rate ID already exists';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_VEHICLE_TYPE
                WHERE VVT_VEHICLE_TYPE_ID = @p_vehicleTypeID
                  AND VVT_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Active vehicle type was not found';
                RETURN;
            END;

            IF ISNULL(@p_isActive, 'A') = 'A'
            BEGIN
                IF @p_effectiveTo IS NOT NULL
                   AND @p_effectiveTo <= @Now
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'An ended rate cannot be active';
                    RETURN;
                END;

                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_RATE
                    WHERE VPR_VEHICLE_TYPE_ID = @p_vehicleTypeID
                      AND VPR_RATE_UNIT = @p_rateUnit
                      AND VPR_IS_ACTIVE = 'A'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'An active rate already exists for this vehicle type and unit';
                    RETURN;
                END;
            END;

            INSERT INTO dbo.VPMS_PARKING_RATE
            (
                VPR_RATE_ID,
                VPR_VEHICLE_TYPE_ID,
                VPR_RATE_NAME,
                VPR_RATE_AMOUNT,
                VPR_RATE_UNIT,
                VPR_EFFECTIVE_FROM,
                VPR_EFFECTIVE_TO,
                VPR_IS_ACTIVE,
                VPR_CREATED_BY,
                VPR_CREATED_DATE
            )
            VALUES
            (
                @p_rateID,
                @p_vehicleTypeID,
                @p_rateName,
                @p_rateAmount,
                @p_rateUnit,
                @p_effectiveFrom,
                @p_effectiveTo,
                ISNULL(@p_isActive, 'A'),
                @p_uid,
                @Now
            );

            SET @Result = 'Parking rate added successfully';
            SELECT @p_rateID AS VPR_RATE_ID;
        END

        /** 4. Update parking rate **/
        ELSE IF @ActionType = 4
        BEGIN
            IF @p_rateID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking rate ID is required';
                RETURN;
            END;

            IF @p_rateName IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking rate name is required';
                RETURN;
            END;

            IF @p_rateAmount IS NULL OR @p_rateAmount < 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A parking rate amount of zero or greater is required';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_USER_ROLE = 'AD'
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator is required';
                RETURN;
            END;

            DECLARE @StoredEffectiveFrom DATETIME2(0);
            DECLARE @StoredRateStatus CHAR(1);

            SELECT
                @p_vehicleTypeID = VPR_VEHICLE_TYPE_ID,
                @StoredEffectiveFrom = VPR_EFFECTIVE_FROM,
                @StoredRateStatus = VPR_IS_ACTIVE
            FROM dbo.VPMS_PARKING_RATE
            WHERE VPR_RATE_ID = @p_rateID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking rate was not found';
                RETURN;
            END;

            SET @p_effectiveFrom = ISNULL(@p_effectiveFrom, @StoredEffectiveFrom);

            IF @p_effectiveTo IS NOT NULL
               AND @p_effectiveTo <= @p_effectiveFrom
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Effective end time must be later than effective start time';
                RETURN;
            END;

            IF @StoredRateStatus = 'A'
               AND @p_effectiveTo IS NOT NULL
               AND @p_effectiveTo <= @Now
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Deactivate the rate before setting an end time in the past';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_VEHICLE_TYPE
                WHERE VVT_VEHICLE_TYPE_ID = @p_vehicleTypeID
                  AND VVT_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Active vehicle type was not found';
                RETURN;
            END;

            UPDATE dbo.VPMS_PARKING_RATE
            SET VPR_RATE_NAME = @p_rateName,
                VPR_RATE_AMOUNT = @p_rateAmount,
                VPR_EFFECTIVE_FROM = @p_effectiveFrom,
                VPR_EFFECTIVE_TO = @p_effectiveTo,
                VPR_UPDATED_BY = @p_uid,
                VPR_UPDATED_DATE = @Now
            WHERE VPR_RATE_ID = @p_rateID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking rate was not found';
                RETURN;
            END;

            SET @Result = 'Parking rate updated successfully';
        END

        /** 5. Activate or deactivate parking rate **/
        ELSE IF @ActionType = 5
        BEGIN
            IF @p_rateID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking rate ID is required';
                RETURN;
            END;

            IF @p_isActive IS NULL
               OR @p_isActive NOT IN ('A', 'I')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Status is required : A - Active / I - Inactive';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_USER_ROLE = 'AD'
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator is required';
                RETURN;
            END;

            SELECT
                @p_vehicleTypeID = VPR_VEHICLE_TYPE_ID,
                @p_rateUnit = VPR_RATE_UNIT,
                @p_effectiveTo = VPR_EFFECTIVE_TO
            FROM dbo.VPMS_PARKING_RATE
            WHERE VPR_RATE_ID = @p_rateID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking rate was not found';
                RETURN;
            END;

            IF @p_isActive = 'A'
            BEGIN
                IF @p_rateUnit NOT IN ('H', 'D', 'M')
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Rate unit must be H - Hourly / D - Daily / M - Monthly';
                    RETURN;
                END;

                IF @p_effectiveTo IS NOT NULL
                   AND @p_effectiveTo <= @Now
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'An ended rate cannot be activated. Update its dates or add a new rate';
                    RETURN;
                END;

                IF NOT EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_VEHICLE_TYPE
                    WHERE VVT_VEHICLE_TYPE_ID = @p_vehicleTypeID
                      AND VVT_IS_ACTIVE = 'A'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Activate the vehicle type before activating this rate';
                    RETURN;
                END;

                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_RATE
                    WHERE VPR_VEHICLE_TYPE_ID = @p_vehicleTypeID
                      AND VPR_RATE_UNIT = @p_rateUnit
                      AND VPR_RATE_ID <> @p_rateID
                      AND VPR_IS_ACTIVE = 'A'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'An active rate already exists for this vehicle type and unit';
                    RETURN;
                END;
            END;

            UPDATE dbo.VPMS_PARKING_RATE
            SET VPR_IS_ACTIVE = @p_isActive,
                VPR_UPDATED_BY = @p_uid,
                VPR_UPDATED_DATE = @Now
            WHERE VPR_RATE_ID = @p_rateID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking rate was not found';
                RETURN;
            END;

            SET @Result = 'Parking rate status updated successfully';
        END

        /** 6. Get currently effective parking rates **/
        ELSE IF @ActionType = 6
        BEGIN
            IF @p_vehicleTypeID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type ID is required';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An active user is required';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_VEHICLE_TYPE
                WHERE VVT_VEHICLE_TYPE_ID = @p_vehicleTypeID
                  AND VVT_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Active vehicle type was not found';
                RETURN;
            END;

            SELECT
                VPR_RATE_ID,
                VPR_VEHICLE_TYPE_ID,
                VPR_RATE_NAME,
                VPR_RATE_AMOUNT,
                VPR_RATE_UNIT,
                VPR_EFFECTIVE_FROM,
                VPR_EFFECTIVE_TO,
                VPR_IS_ACTIVE
            FROM dbo.VPMS_PARKING_RATE
            WHERE VPR_VEHICLE_TYPE_ID = @p_vehicleTypeID
              AND VPR_IS_ACTIVE = 'A'
              AND VPR_RATE_UNIT IN ('H', 'D', 'M')
              AND VPR_EFFECTIVE_FROM <= @Now
              AND (VPR_EFFECTIVE_TO IS NULL OR VPR_EFFECTIVE_TO > @Now)
              AND (@p_rateUnit IS NULL OR VPR_RATE_UNIT = @p_rateUnit)
            ORDER BY VPR_RATE_UNIT;

            SET @Result = 'Currently effective parking rates retrieved successfully';
        END

        /** Invalid action **/
        ELSE
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = 'Invalid action type';
        END;
    END TRY
    BEGIN CATCH
        SET @ResultStatusCode = -1;
        SET @Result = 'Error occurred';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO