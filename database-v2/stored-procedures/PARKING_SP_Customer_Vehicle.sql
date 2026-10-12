USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Customer_Vehicle
(
    @ActionType         INT,

    @p_vehicleID        INT = NULL,
    @p_customerID       INT = NULL,
    @p_vehicleTypeID    INT = NULL,
    @p_vehicleNumber    VARCHAR(30) = NULL,
    @p_vehicleMake      NVARCHAR(100) = NULL,
    @p_vehicleModel     NVARCHAR(100) = NULL,
    @p_vehicleColour    NVARCHAR(50) = NULL,
    @p_isActive         BIT = NULL,
    @p_searchTerm       NVARCHAR(200) = NULL,
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

        SET @p_vehicleNumber =
            UPPER(NULLIF(LTRIM(RTRIM(@p_vehicleNumber)), ''));

        SET @p_vehicleMake =
            NULLIF(LTRIM(RTRIM(@p_vehicleMake)), N'');

        SET @p_vehicleModel =
            NULLIF(LTRIM(RTRIM(@p_vehicleModel)), N'');

        SET @p_vehicleColour =
            NULLIF(LTRIM(RTRIM(@p_vehicleColour)), N'');

        SET @p_searchTerm =
            NULLIF(LTRIM(RTRIM(@p_searchTerm)), N'');

        SET @p_includeInactive = ISNULL(@p_includeInactive, 0);

        /* ============================================================
           Shared Input Validation
           ============================================================ */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType NOT BETWEEN 1 AND 5
            SET @ValidationMessage = 'Invalid action type';

        ELSE IF @ActionType IN (2, 4, 5)
             AND (@p_vehicleID IS NULL OR @p_vehicleID <= 0)
            SET @ValidationMessage = 'A valid vehicle ID is required';

        ELSE IF @p_customerID IS NOT NULL AND @p_customerID <= 0
            SET @ValidationMessage =
                'Customer ID must be a positive ID or NULL';

        ELSE IF @ActionType IN (3, 4)
             AND
             (
                 @p_vehicleNumber IS NULL
                 OR @p_vehicleTypeID IS NULL
                 OR @p_vehicleTypeID <= 0
             )
            SET @ValidationMessage =
                'Vehicle number and a valid vehicle type are required';

        ELSE IF @ActionType = 5 AND @p_isActive IS NULL
            SET @ValidationMessage = 'Active status is required';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ============================================================
           1. Get / Search Vehicles
           2. Get Vehicle By ID
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
                V.VehicleID,
                V.CustomerID,
                C.CustomerName,
                C.MobileNumber,
                V.VehicleTypeID,
                VT.TypeName AS VehicleType,
                VT.WheelCount,
                V.VehicleNumber,
                V.VehicleMake,
                V.VehicleModel,
                V.VehicleColour,
                V.ActiveStatus,
                V.CreatedAt,
                V.CreatedBy,
                V.UpdatedAt,
                V.UpdatedBy
            FROM dbo.PARKING_CUSTOMER_VEHICLE AS V
            INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
                ON VT.VehicleTypeID = V.VehicleTypeID
            LEFT JOIN dbo.PARKING_CUSTOMER AS C
                ON C.CustomerID = V.CustomerID
            WHERE
                (
                    @ActionType = 1
                    AND
                    (
                        @p_includeInactive = 1
                        OR V.ActiveStatus = 1
                    )
                    AND
                    (
                        @p_customerID IS NULL
                        OR V.CustomerID = @p_customerID
                    )
                    AND
                    (
                        @p_vehicleTypeID IS NULL
                        OR V.VehicleTypeID = @p_vehicleTypeID
                    )
                    AND
                    (
                        @p_searchTerm IS NULL
                        OR CHARINDEX
                           (
                               UPPER(@p_searchTerm),
                               UPPER(V.VehicleNumber)
                           ) > 0
                        OR CHARINDEX
                           (
                               UPPER(@p_searchTerm),
                               UPPER(C.CustomerName)
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
                    AND V.VehicleID = @p_vehicleID
                )
            ORDER BY V.VehicleNumber, V.VehicleID;

            IF @@ROWCOUNT = 0 AND @ActionType = 2
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle was not found';
                RETURN;
            END;

            SET @ResultStatusCode = 1;
            SET @Result = 'Vehicle details retrieved successfully';
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
            SET @Result = 'Vehicle management is busy. Please retry';
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

        DECLARE
            @StoredCustomerID INT,
            @StoredTypeID INT,
            @StoredNumber VARCHAR(30),
            @IdentityChanged BIT = 0;

        SET @ValidationMessage = NULL;

        IF @ActionType IN (4, 5)
        BEGIN
            SELECT
                @StoredCustomerID = CustomerID,
                @StoredTypeID = VehicleTypeID,
                @StoredNumber = VehicleNumber
            FROM dbo.PARKING_CUSTOMER_VEHICLE WITH (UPDLOCK, HOLDLOCK)
            WHERE VehicleID = @p_vehicleID;

            IF @StoredTypeID IS NULL
                SET @ValidationMessage = 'Vehicle was not found';
        END;

        IF @ValidationMessage IS NULL
           AND @ActionType = 4
           AND
           (
               @StoredTypeID <> @p_vehicleTypeID
               OR @StoredNumber <> @p_vehicleNumber
               OR ISNULL(@StoredCustomerID, 0)
                  <> ISNULL(@p_customerID, 0)
           )
            SET @IdentityChanged = 1;

        IF @ValidationMessage IS NULL
           AND
           (
               @IdentityChanged = 1
               OR (@ActionType = 5 AND @p_isActive = 0)
           )
        BEGIN
            IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_TICKET
                WHERE VehicleID = @p_vehicleID
                  AND ExitDateTime IS NULL
            )
                SET @ValidationMessage =
                    'The vehicle has an open parking visit';

            ELSE IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_MONTHLY_CONTRACT
                WHERE VehicleID = @p_vehicleID
                  AND ContractStatus = 'ACTIVE'
            )
                SET @ValidationMessage =
                    'Resolve the active monthly contract before changing vehicle identity or deactivating it';
        END;

        -- Preserve the vehicle number and category used by history.
        IF @ValidationMessage IS NULL
           AND @ActionType = 4
           AND
           (
               @StoredTypeID <> @p_vehicleTypeID
               OR @StoredNumber <> @p_vehicleNumber
           )
           AND
           (
               EXISTS
               (
                   SELECT 1
                   FROM dbo.PARKING_TICKET
                   WHERE VehicleID = @p_vehicleID
               )
               OR EXISTS
               (
                   SELECT 1
                   FROM dbo.PARKING_MONTHLY_CONTRACT
                   WHERE VehicleID = @p_vehicleID
               )
           )
            SET @ValidationMessage =
                'A vehicle with parking or contract history cannot change its number or category';

        IF @ValidationMessage IS NULL
           AND @ActionType IN (3, 4)
           AND EXISTS
           (
               SELECT 1
               FROM dbo.PARKING_CUSTOMER_VEHICLE
                   WITH (UPDLOCK, HOLDLOCK)
               WHERE VehicleNumber = @p_vehicleNumber
                 AND
                 (
                     @ActionType = 3
                     OR VehicleID <> @p_vehicleID
                 )
           )
            SET @ValidationMessage = 'Vehicle number already exists';

        -- Reactivation validates the vehicle's saved relationships.
        IF @ValidationMessage IS NULL
           AND @ActionType = 5
           AND @p_isActive = 1
        BEGIN
            SET @p_vehicleTypeID = @StoredTypeID;
            SET @p_customerID = @StoredCustomerID;
        END;

        IF @ValidationMessage IS NULL
           AND
           (
               @ActionType IN (3, 4)
               OR (@ActionType = 5 AND @p_isActive = 1)
           )
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

            ELSE IF @p_customerID IS NOT NULL
                 AND NOT EXISTS
                 (
                     SELECT 1
                     FROM dbo.PARKING_CUSTOMER WITH (HOLDLOCK)
                     WHERE CustomerID = @p_customerID
                       AND ActiveStatus = 1
                 )
                SET @ValidationMessage =
                    'Active customer was not found';
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
           3. Create Vehicle
           ============================================================ */

        IF @ActionType = 3
        BEGIN
            INSERT INTO dbo.PARKING_CUSTOMER_VEHICLE
            (
                CustomerID,
                VehicleTypeID,
                VehicleNumber,
                VehicleMake,
                VehicleModel,
                VehicleColour,
                CreatedAt,
                CreatedBy
            )
            VALUES
            (
                @p_customerID,
                @p_vehicleTypeID,
                @p_vehicleNumber,
                @p_vehicleMake,
                @p_vehicleModel,
                @p_vehicleColour,
                @Now,
                @p_uid
            );

            SET @p_vehicleID = CONVERT(INT, SCOPE_IDENTITY());
            SET @Result = 'Vehicle created successfully';
        END

        /* ============================================================
           4. Update Vehicle
           ============================================================ */

        ELSE IF @ActionType = 4
        BEGIN
            UPDATE dbo.PARKING_CUSTOMER_VEHICLE
            SET
                CustomerID = @p_customerID,
                VehicleTypeID = @p_vehicleTypeID,
                VehicleNumber = @p_vehicleNumber,
                VehicleMake = @p_vehicleMake,
                VehicleModel = @p_vehicleModel,
                VehicleColour = @p_vehicleColour,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE VehicleID = @p_vehicleID;

            SET @Result = 'Vehicle updated successfully';
        END

        /* ============================================================
           5. Activate / Deactivate Vehicle
           ============================================================ */

        ELSE IF @ActionType = 5
        BEGIN
            UPDATE dbo.PARKING_CUSTOMER_VEHICLE
            SET
                ActiveStatus = @p_isActive,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE VehicleID = @p_vehicleID;

            SET @Result =
                CASE
                    WHEN @p_isActive = 1
                        THEN 'Vehicle activated successfully'
                    ELSE 'Vehicle deactivated successfully'
                END;
        END;

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;

        SELECT @p_vehicleID AS VehicleID;

    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while processing vehicle details';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO