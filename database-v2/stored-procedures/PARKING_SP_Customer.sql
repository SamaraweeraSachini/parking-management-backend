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

        SET @p_customerName =
            NULLIF(LTRIM(RTRIM(@p_customerName)), N'');

        SET @p_mobileNumber =
            NULLIF(LTRIM(RTRIM(@p_mobileNumber)), '');

        SET @p_emailAddress =
            NULLIF(LTRIM(RTRIM(@p_emailAddress)), N'');

        SET @p_address =
            NULLIF(LTRIM(RTRIM(@p_address)), N'');

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
             AND (@p_customerID IS NULL OR @p_customerID <= 0)
            SET @ValidationMessage = 'A valid customer ID is required';

        ELSE IF @ActionType IN (3, 4)
             AND
             (
                 @p_customerName IS NULL
                 OR @p_mobileNumber IS NULL
                 OR LEN(@p_mobileNumber) NOT BETWEEN 7 AND 20
             )
            SET @ValidationMessage =
                'Customer name and a mobile number of 7-20 characters are required';

        ELSE IF @ActionType = 5 AND @p_isActive IS NULL
            SET @ValidationMessage = 'Active status is required';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ============================================================
           1. Get / Search Customers
           2. Get Customer By ID
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
                CustomerID,
                CustomerName,
                MobileNumber,
                EmailAddress,
                Address,
                RegisteredDate,
                ActiveStatus,
                CreatedAt,
                CreatedBy,
                UpdatedAt,
                UpdatedBy
            FROM dbo.PARKING_CUSTOMER
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
                        @p_searchTerm IS NULL
                        OR CHARINDEX
                           (
                               UPPER(@p_searchTerm),
                               UPPER(CustomerName)
                           ) > 0
                        OR CHARINDEX
                           (
                               @p_searchTerm,
                               MobileNumber
                           ) > 0
                    )
                )
                OR
                (
                    @ActionType = 2
                    AND CustomerID = @p_customerID
                )
            ORDER BY CustomerName, CustomerID;

            IF @@ROWCOUNT = 0 AND @ActionType = 2
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer was not found';
                RETURN;
            END;

            SET @ResultStatusCode = 1;
            SET @Result = 'Customer details retrieved successfully';
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
            SET @Result = 'Customer management is busy. Please retry';
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

        SET @ValidationMessage = NULL;

        IF @ActionType IN (4, 5)
           AND NOT EXISTS
           (
               SELECT 1
               FROM dbo.PARKING_CUSTOMER WITH (UPDLOCK, HOLDLOCK)
               WHERE CustomerID = @p_customerID
           )
            SET @ValidationMessage = 'Customer was not found';

        IF @ValidationMessage IS NULL
           AND @ActionType = 5
           AND @p_isActive = 0
        BEGIN
            IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_CUSTOMER_VEHICLE
                WHERE CustomerID = @p_customerID
                  AND ActiveStatus = 1
            )
            OR EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_MONTHLY_CONTRACT
                WHERE CustomerID = @p_customerID
                  AND ContractStatus = 'ACTIVE'
            )
                SET @ValidationMessage =
                    'Deactivate the customer vehicles and resolve active monthly contracts before deactivating this customer';
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
           3. Create Customer
           ============================================================ */

        IF @ActionType = 3
        BEGIN
            INSERT INTO dbo.PARKING_CUSTOMER
            (
                CustomerName,
                MobileNumber,
                EmailAddress,
                Address,
                RegisteredDate,
                CreatedAt,
                CreatedBy
            )
            VALUES
            (
                @p_customerName,
                @p_mobileNumber,
                @p_emailAddress,
                @p_address,
                @Now,
                @Now,
                @p_uid
            );

            SET @p_customerID = CONVERT(INT, SCOPE_IDENTITY());
            SET @Result = 'Customer created successfully';
        END

        /* ============================================================
           4. Update Customer
           ============================================================ */

        ELSE IF @ActionType = 4
        BEGIN
            UPDATE dbo.PARKING_CUSTOMER
            SET
                CustomerName = @p_customerName,
                MobileNumber = @p_mobileNumber,
                EmailAddress = @p_emailAddress,
                Address = @p_address,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE CustomerID = @p_customerID;

            SET @Result = 'Customer updated successfully';
        END

        /* ============================================================
           5. Activate / Deactivate Customer
           ============================================================ */

        ELSE IF @ActionType = 5
        BEGIN
            UPDATE dbo.PARKING_CUSTOMER
            SET
                ActiveStatus = @p_isActive,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE CustomerID = @p_customerID;

            SET @Result =
                CASE
                    WHEN @p_isActive = 1
                        THEN 'Customer activated successfully'
                    ELSE 'Customer deactivated successfully'
                END;
        END;

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;

        SELECT @p_customerID AS CustomerID;

    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while processing customer details';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO