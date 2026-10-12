USE [VehicleParkingManagementDB_V2];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Customer
(
    @ActionType         INT,

    @p_customerID       INT = NULL,
    @p_customerName     NVARCHAR(200) = NULL,
    @p_mobileNumber     VARCHAR(20) = NULL,
    @p_emailAddress     NVARCHAR(254) = NULL,
    @p_address          NVARCHAR(500) = NULL,
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

        SET @p_customerName = NULLIF(LTRIM(RTRIM(@p_customerName)), N'');
        SET @p_mobileNumber = NULLIF(LTRIM(RTRIM(@p_mobileNumber)), '');
        SET @p_emailAddress = NULLIF(LTRIM(RTRIM(@p_emailAddress)), N'');
        SET @p_address = NULLIF(LTRIM(RTRIM(@p_address)), N'');
        SET @p_searchTerm = NULLIF(LTRIM(RTRIM(@p_searchTerm)), N'');
        SET @p_includeInactive = ISNULL(@p_includeInactive, 0);

        DECLARE @LockResult INT, @Now DATETIME2(0);

        /* 1. Get Customers */
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
                CustomerID, CustomerName, MobileNumber,
                EmailAddress, Address, RegisteredDate, ActiveStatus,
                CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
            FROM dbo.PARKING_CUSTOMER
            WHERE (@p_includeInactive = 1 OR ActiveStatus = 1)
              AND
              (
                  @p_searchTerm IS NULL
                  OR CHARINDEX(UPPER(@p_searchTerm), UPPER(CustomerName)) > 0
                  OR CHARINDEX(@p_searchTerm, MobileNumber) > 0
              )
            ORDER BY CustomerName, CustomerID;

            SET @ResultStatusCode = 1;
            SET @Result = 'Customer details retrieved successfully';
        END

        /* 2. Get Customer By ID */
        ELSE IF @ActionType = 2
        BEGIN
            IF @p_customerID IS NULL OR @p_customerID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid customer ID is required';
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
                CustomerID, CustomerName, MobileNumber,
                EmailAddress, Address, RegisteredDate, ActiveStatus,
                CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
            FROM dbo.PARKING_CUSTOMER
            WHERE CustomerID = @p_customerID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer was not found';
                RETURN;
            END;

            SET @ResultStatusCode = 1;
            SET @Result = 'Customer details retrieved successfully';
        END

        /* 3. Create Customer */
        ELSE IF @ActionType = 3
        BEGIN
            IF @p_customerName IS NULL OR @p_mobileNumber IS NULL
               OR LEN(@p_mobileNumber) NOT BETWEEN 7 AND 20
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result =
                    'Customer name and a mobile number of 7-20 characters are required';
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
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer management is busy. Please retry';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1 FROM dbo.PARKING_USER WITH (HOLDLOCK)
                WHERE UserID = @p_uid
                  AND UserRole = 'A' AND ActiveStatus = 1
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator is required';
                RETURN;
            END;

            SET @Now = SYSUTCDATETIME();
            INSERT INTO dbo.PARKING_CUSTOMER
            (
                CustomerName, MobileNumber, EmailAddress, Address,
                RegisteredDate, CreatedAt, CreatedBy
            )
            VALUES
            (
                @p_customerName, @p_mobileNumber, @p_emailAddress,
                @p_address, @Now, @Now, @p_uid
            );

            SET @p_customerID = CONVERT(INT, SCOPE_IDENTITY());
            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;
            SET @ResultStatusCode = 1;
            SET @Result = 'Customer created successfully';
            SELECT @p_customerID AS CustomerID;
        END

        /* 4. Update Customer */
        ELSE IF @ActionType = 4
        BEGIN
            IF @p_customerID IS NULL OR @p_customerID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid customer ID is required';
                RETURN;
            END;

            IF @p_customerName IS NULL OR @p_mobileNumber IS NULL
               OR LEN(@p_mobileNumber) NOT BETWEEN 7 AND 20
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result =
                    'Customer name and a mobile number of 7-20 characters are required';
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
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer management is busy. Please retry';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1 FROM dbo.PARKING_USER WITH (HOLDLOCK)
                WHERE UserID = @p_uid
                  AND UserRole = 'A' AND ActiveStatus = 1
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator is required';
                RETURN;
            END;

            SET @Now = SYSUTCDATETIME();
            UPDATE dbo.PARKING_CUSTOMER
            SET CustomerName = @p_customerName,
                MobileNumber = @p_mobileNumber,
                EmailAddress = @p_emailAddress,
                Address = @p_address,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE CustomerID = @p_customerID;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer was not found';
                RETURN;
            END;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;
            SET @ResultStatusCode = 1;
            SET @Result = 'Customer updated successfully';
            SELECT @p_customerID AS CustomerID;
        END

        /* 5. Activate / Deactivate Customer */
        ELSE IF @ActionType = 5
        BEGIN
            IF @p_customerID IS NULL OR @p_customerID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid customer ID is required';
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
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer management is busy. Please retry';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1 FROM dbo.PARKING_USER WITH (HOLDLOCK)
                WHERE UserID = @p_uid
                  AND UserRole = 'A' AND ActiveStatus = 1
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator is required';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1 FROM dbo.PARKING_CUSTOMER WITH (UPDLOCK, HOLDLOCK)
                WHERE CustomerID = @p_customerID
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer was not found';
                RETURN;
            END;

            IF @p_isActive = 0 AND
            (
                EXISTS
                (
                    SELECT 1 FROM dbo.PARKING_CUSTOMER_VEHICLE
                    WHERE CustomerID = @p_customerID AND ActiveStatus = 1
                )
                OR EXISTS
                (
                    SELECT 1 FROM dbo.PARKING_MONTHLY_CONTRACT
                    WHERE CustomerID = @p_customerID AND ContractStatus = 'ACTIVE'
                )
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result =
                    'Deactivate the customer vehicles and resolve active monthly contracts before deactivating this customer';
                RETURN;
            END;

            SET @Now = SYSUTCDATETIME();
            UPDATE dbo.PARKING_CUSTOMER
            SET ActiveStatus = @p_isActive,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE CustomerID = @p_customerID;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer was not found';
                RETURN;
            END;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;
            SET @ResultStatusCode = 1;
            SET @Result =
                CASE WHEN @p_isActive = 1
                     THEN 'Customer activated successfully'
                     ELSE 'Customer deactivated successfully' END;
            SELECT @p_customerID AS CustomerID;
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
        SET @Result = 'An error occurred while processing customer details';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO