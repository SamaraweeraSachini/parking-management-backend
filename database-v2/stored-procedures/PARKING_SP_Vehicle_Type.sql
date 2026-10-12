USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Vehicle_Type
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

        SET @p_typeName =
            NULLIF(LTRIM(RTRIM(@p_typeName)), N'');

        SET @p_description =
            NULLIF(LTRIM(RTRIM(@p_description)), N'');

        SET @p_includeInactive = ISNULL(@p_includeInactive, 0);

        /* ============================================================
           Shared Input Validation
           ============================================================ */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType NOT BETWEEN 1 AND 5
            SET @ValidationMessage = 'Invalid action type';

        ELSE IF @ActionType IN (2, 4, 5)
             AND
             (
                 @p_vehicleTypeID IS NULL
                 OR @p_vehicleTypeID <= 0
             )
            SET @ValidationMessage = 'A valid vehicle type ID is required';

        ELSE IF @ActionType IN (3, 4)
             AND
             (
                 @p_typeName IS NULL
                 OR @p_wheelCount IS NULL
                 OR @p_wheelCount NOT IN (2, 3, 4)
             )
            SET @ValidationMessage =
                'Type name and wheel count of 2, 3 or 4 are required';

        ELSE IF @ActionType = 5 AND @p_isActive IS NULL
            SET @ValidationMessage = 'Active status is required';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ============================================================
           1. Get Vehicle Types
           2. Get Vehicle Type By ID
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
                VehicleTypeID,
                TypeName,
                WheelCount,
                Description,
                ActiveStatus,
                CreatedAt,
                CreatedBy,
                UpdatedAt,
                UpdatedBy
            FROM dbo.PARKING_VEHICLE_TYPE
            WHERE
                (
                    @ActionType = 1
                    AND
                    (
                        @p_includeInactive = 1
                        OR ActiveStatus = 1
                    )
                )
                OR
                (
                    @ActionType = 2
                    AND VehicleTypeID = @p_vehicleTypeID
                )
            ORDER BY WheelCount DESC;

            IF @@ROWCOUNT = 0 AND @ActionType = 2
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type was not found';
                RETURN;
            END;

            SET @ResultStatusCode = 1;
            SET @Result = 'Vehicle type details retrieved successfully';
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

        DECLARE @CurrentWheels INT;

        IF @ActionType IN (4, 5)
        BEGIN
            SELECT @CurrentWheels = WheelCount
            FROM dbo.PARKING_VEHICLE_TYPE WITH (UPDLOCK, HOLDLOCK)
            WHERE VehicleTypeID = @p_vehicleTypeID;
        END;

        SET @ValidationMessage = NULL;

        IF @ActionType IN (4, 5) AND @CurrentWheels IS NULL
            SET @ValidationMessage = 'Vehicle type was not found';

        ELSE IF @ActionType IN (3, 4)
             AND EXISTS
             (
                 SELECT 1
                 FROM dbo.PARKING_VEHICLE_TYPE WITH (UPDLOCK, HOLDLOCK)
                 WHERE
                     (
                         TypeName = @p_typeName
                         OR WheelCount = @p_wheelCount
                     )
                   AND
                     (
                         @ActionType = 3
                         OR VehicleTypeID <> @p_vehicleTypeID
                     )
             )
            SET @ValidationMessage =
                'The type name or wheel category already exists';

        IF @ValidationMessage IS NULL
           AND
           (
               (@ActionType = 4 AND @p_wheelCount <> @CurrentWheels)
               OR
               (@ActionType = 5 AND @p_isActive = 0)
           )
        BEGIN
            IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_SPACE
                WHERE VehicleTypeID = @p_vehicleTypeID
                  AND (@ActionType = 4 OR ActiveStatus = 1)
            )
            OR EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_RATE
                WHERE VehicleTypeID = @p_vehicleTypeID
                  AND (@ActionType = 4 OR ActiveStatus = 1)
            )
            OR EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_CUSTOMER_VEHICLE
                WHERE VehicleTypeID = @p_vehicleTypeID
                  AND (@ActionType = 4 OR ActiveStatus = 1)
            )
            BEGIN
                SET @ValidationMessage =
                    CASE
                        WHEN @ActionType = 4
                            THEN 'A vehicle type already referenced by spaces, rates or vehicles cannot change its wheel category'
                        ELSE 'Deactivate the active spaces, rates and vehicles before deactivating this vehicle type'
                    END;
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

        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

        /* ============================================================
           3. Create Vehicle Type
           ============================================================ */

        IF @ActionType = 3
        BEGIN
            INSERT INTO dbo.PARKING_VEHICLE_TYPE
            (
                TypeName,
                WheelCount,
                Description,
                CreatedAt,
                CreatedBy
            )
            VALUES
            (
                @p_typeName,
                @p_wheelCount,
                @p_description,
                @Now,
                @p_uid
            );

            SET @p_vehicleTypeID =
                CONVERT(INT, SCOPE_IDENTITY());

            SET @Result = 'Vehicle type created successfully';
        END

        /* ============================================================
           4. Update Vehicle Type
           ============================================================ */

        ELSE IF @ActionType = 4
        BEGIN
            UPDATE dbo.PARKING_VEHICLE_TYPE
            SET
                TypeName = @p_typeName,
                WheelCount = @p_wheelCount,
                Description = @p_description,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE VehicleTypeID = @p_vehicleTypeID;

            SET @Result = 'Vehicle type updated successfully';
        END

        /* ============================================================
           5. Activate / Deactivate Vehicle Type
           ============================================================ */

        ELSE IF @ActionType = 5
        BEGIN
            UPDATE dbo.PARKING_VEHICLE_TYPE
            SET
                ActiveStatus = @p_isActive,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE VehicleTypeID = @p_vehicleTypeID;

            SET @Result =
                CASE
                    WHEN @p_isActive = 1
                        THEN 'Vehicle type activated successfully'
                    ELSE 'Vehicle type deactivated successfully'
                END;
        END;

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;

        SELECT @p_vehicleTypeID AS VehicleTypeID;

    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while processing vehicle type details';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO