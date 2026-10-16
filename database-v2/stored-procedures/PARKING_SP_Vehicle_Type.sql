USE [VPMS_001_DB];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_VEHICLE_TYPE_PROC
(
    @ActionType         INT,

    @p_vehicleTypeID    INT = NULL,
    @p_typeName         NVARCHAR(100) = NULL,
    @p_wheelCount       INT = NULL,
    @p_description      NVARCHAR(500) = NULL,
    @p_isActive         BIT = NULL,
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

        SET @p_typeName = NULLIF(LTRIM(RTRIM(@p_typeName)), N'');
        SET @p_description = NULLIF(LTRIM(RTRIM(@p_description)), N'');
        SET @p_includeInactive = ISNULL(@p_includeInactive, 0);

        DECLARE
            @LockResult INT,
            @CurrentWheels INT,
            @Now DATETIME2(0),
            @ValidationMessage VARCHAR(500);

        /* 1. Get Vehicle Types */
        IF @ActionType = 1
        BEGIN
            IF NOT EXISTS
            (
                SELECT 1 FROM dbo.PARKING_USER
                WHERE UserID = @p_uid AND ActiveStatus = 1
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An authenticated active user is required';
                RETURN;
            END;

            SELECT
                VehicleTypeID, TypeName, WheelCount, Description,
                ActiveStatus, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
            FROM dbo.PARKING_VEHICLE_TYPE
            WHERE @p_includeInactive = 1 OR ActiveStatus = 1
            ORDER BY WheelCount DESC;

            SET @ResultStatusCode = 1;
            SET @Result = 'Vehicle type list retrieved successfully';
        END

        /* 2. Get Vehicle Type By ID */
        ELSE IF @ActionType = 2
        BEGIN
            IF @p_vehicleTypeID IS NULL OR @p_vehicleTypeID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid vehicle type ID is required';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1 FROM dbo.PARKING_USER
                WHERE UserID = @p_uid AND ActiveStatus = 1
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An authenticated active user is required';
                RETURN;
            END;

            SELECT
                VehicleTypeID, TypeName, WheelCount, Description,
                ActiveStatus, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
            FROM dbo.PARKING_VEHICLE_TYPE
            WHERE VehicleTypeID = @p_vehicleTypeID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type was not found';
                RETURN;
            END;

            SET @ResultStatusCode = 1;
            SET @Result = 'Vehicle type details retrieved successfully';
        END

        /* 3. Create Vehicle Type */
        ELSE IF @ActionType = 3
        BEGIN
            IF @p_typeName IS NULL OR @p_wheelCount IS NULL
               OR @p_wheelCount NOT IN (2, 3, 4)
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Type name and wheel count of 2, 3 or 4 are required';
                RETURN;
            END;

            IF @@TRANCOUNT <> 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Call this procedure without an existing transaction';
                RETURN;
            END;

            BEGIN TRANSACTION;
            SET @StartedTransaction = 1;
            EXEC @LockResult = sys.sp_getapplock
                @Resource = N'ParkingV2Configuration',
                @LockMode = N'Exclusive',
                @LockOwner = N'Transaction',
                @LockTimeout = 10000;

            IF @LockResult < 0
                SET @ValidationMessage = 'Parking configuration is busy. Please retry';
            ELSE IF NOT EXISTS
            (
                SELECT 1 FROM dbo.PARKING_USER WITH (HOLDLOCK)
                WHERE UserID = @p_uid AND UserRole = 'A' AND ActiveStatus = 1
            )
                SET @ValidationMessage = 'An active administrator is required';
            ELSE IF EXISTS
            (
                SELECT 1 FROM dbo.PARKING_VEHICLE_TYPE WITH (UPDLOCK, HOLDLOCK)
                WHERE TypeName = @p_typeName OR WheelCount = @p_wheelCount
            )
                SET @ValidationMessage = 'The type name or wheel category already exists';

            IF @ValidationMessage IS NOT NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = @ValidationMessage;
                RETURN;
            END;

            SET @Now = SYSUTCDATETIME();
            INSERT INTO dbo.PARKING_VEHICLE_TYPE
                (TypeName, WheelCount, Description, CreatedAt, CreatedBy)
            VALUES
                (@p_typeName, @p_wheelCount, @p_description, @Now, @p_uid);

            SET @p_vehicleTypeID = CONVERT(INT, SCOPE_IDENTITY());
            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;
            SET @ResultStatusCode = 1;
            SET @Result = 'Vehicle type created successfully';
            SELECT @p_vehicleTypeID AS VehicleTypeID;
        END

        /* 4. Update Vehicle Type */
        ELSE IF @ActionType = 4
        BEGIN
            IF @p_vehicleTypeID IS NULL OR @p_vehicleTypeID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid vehicle type ID is required';
                RETURN;
            END;

            IF @p_typeName IS NULL OR @p_wheelCount IS NULL
               OR @p_wheelCount NOT IN (2, 3, 4)
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Type name and wheel count of 2, 3 or 4 are required';
                RETURN;
            END;

            IF @@TRANCOUNT <> 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Call this procedure without an existing transaction';
                RETURN;
            END;

            BEGIN TRANSACTION;
            SET @StartedTransaction = 1;
            EXEC @LockResult = sys.sp_getapplock
                @Resource = N'ParkingV2Configuration',
                @LockMode = N'Exclusive',
                @LockOwner = N'Transaction',
                @LockTimeout = 10000;

            IF @LockResult < 0
                SET @ValidationMessage = 'Parking configuration is busy. Please retry';
            ELSE IF NOT EXISTS
            (
                SELECT 1 FROM dbo.PARKING_USER WITH (HOLDLOCK)
                WHERE UserID = @p_uid AND UserRole = 'A' AND ActiveStatus = 1
            )
                SET @ValidationMessage = 'An active administrator is required';

            IF @ValidationMessage IS NULL
            BEGIN
                SELECT @CurrentWheels = WheelCount
                FROM dbo.PARKING_VEHICLE_TYPE WITH (UPDLOCK, HOLDLOCK)
                WHERE VehicleTypeID = @p_vehicleTypeID;

                IF @CurrentWheels IS NULL
                    SET @ValidationMessage = 'Vehicle type was not found';
                ELSE IF EXISTS
                (
                    SELECT 1 FROM dbo.PARKING_VEHICLE_TYPE WITH (UPDLOCK, HOLDLOCK)
                    WHERE (TypeName = @p_typeName OR WheelCount = @p_wheelCount)
                      AND VehicleTypeID <> @p_vehicleTypeID
                )
                    SET @ValidationMessage = 'The type name or wheel category already exists';
                ELSE IF @p_wheelCount <> @CurrentWheels AND
                (
                    EXISTS
                    (
                        SELECT 1 FROM dbo.PARKING_SPACE
                        WHERE VehicleTypeID = @p_vehicleTypeID
                    )
                    OR EXISTS
                    (
                        SELECT 1 FROM dbo.PARKING_RATE
                        WHERE VehicleTypeID = @p_vehicleTypeID
                    )
                    OR EXISTS
                    (
                        SELECT 1 FROM dbo.PARKING_CUSTOMER_VEHICLE
                        WHERE VehicleTypeID = @p_vehicleTypeID
                    )
                )
                    SET @ValidationMessage = 'A vehicle type already referenced by spaces, rates or vehicles cannot change its wheel category';
            END;

            IF @ValidationMessage IS NOT NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = @ValidationMessage;
                RETURN;
            END;

            SET @Now = SYSUTCDATETIME();
            UPDATE dbo.PARKING_VEHICLE_TYPE
            SET TypeName = @p_typeName,
                WheelCount = @p_wheelCount,
                Description = @p_description,
                UpdatedAt = @Now, UpdatedBy = @p_uid
            WHERE VehicleTypeID = @p_vehicleTypeID;

            IF @@ROWCOUNT <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Could not update the vehicle type';
                RETURN;
            END;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;
            SET @ResultStatusCode = 1;
            SET @Result = 'Vehicle type updated successfully';
            SELECT @p_vehicleTypeID AS VehicleTypeID;
        END

        /* 5. Activate / Deactivate Vehicle Type */
        ELSE IF @ActionType = 5
        BEGIN
            IF @p_vehicleTypeID IS NULL OR @p_vehicleTypeID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid vehicle type ID is required';
                RETURN;
            END;

            IF @p_isActive IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Active status is required';
                RETURN;
            END;

            IF @@TRANCOUNT <> 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Call this procedure without an existing transaction';
                RETURN;
            END;

            BEGIN TRANSACTION;
            SET @StartedTransaction = 1;
            EXEC @LockResult = sys.sp_getapplock
                @Resource = N'ParkingV2Configuration',
                @LockMode = N'Exclusive',
                @LockOwner = N'Transaction',
                @LockTimeout = 10000;

            IF @LockResult < 0
                SET @ValidationMessage = 'Parking configuration is busy. Please retry';
            ELSE IF NOT EXISTS
            (
                SELECT 1 FROM dbo.PARKING_USER WITH (HOLDLOCK)
                WHERE UserID = @p_uid AND UserRole = 'A' AND ActiveStatus = 1
            )
                SET @ValidationMessage = 'An active administrator is required';

            IF @ValidationMessage IS NULL
            BEGIN
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.PARKING_VEHICLE_TYPE WITH (UPDLOCK, HOLDLOCK)
                    WHERE VehicleTypeID = @p_vehicleTypeID
                )
                    SET @ValidationMessage = 'Vehicle type was not found';
                ELSE IF @p_isActive = 0 AND
                (
                    EXISTS
                    (
                        SELECT 1 FROM dbo.PARKING_SPACE
                        WHERE VehicleTypeID = @p_vehicleTypeID AND ActiveStatus = 1
                    )
                    OR EXISTS
                    (
                        SELECT 1 FROM dbo.PARKING_RATE
                        WHERE VehicleTypeID = @p_vehicleTypeID AND ActiveStatus = 1
                    )
                    OR EXISTS
                    (
                        SELECT 1 FROM dbo.PARKING_CUSTOMER_VEHICLE
                        WHERE VehicleTypeID = @p_vehicleTypeID AND ActiveStatus = 1
                    )
                )
                    SET @ValidationMessage = 'Deactivate the active spaces, rates and vehicles before deactivating this vehicle type';
            END;

            IF @ValidationMessage IS NOT NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = @ValidationMessage;
                RETURN;
            END;

            SET @Now = SYSUTCDATETIME();
            UPDATE dbo.PARKING_VEHICLE_TYPE
            SET ActiveStatus = @p_isActive,
                UpdatedAt = @Now, UpdatedBy = @p_uid
            WHERE VehicleTypeID = @p_vehicleTypeID;

            IF @@ROWCOUNT <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Could not update the vehicle type active status';
                RETURN;
            END;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;
            SET @ResultStatusCode = 1;
            SET @Result = CASE WHEN @p_isActive = 1
                THEN 'Vehicle type activated successfully'
                ELSE 'Vehicle type deactivated successfully' END;
            SELECT @p_vehicleTypeID AS VehicleTypeID;
        END

        /* Invalid Action */
        ELSE
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = 'Invalid action type';
        END;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result = 'An error occurred while processing vehicle type details';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO
