USE [VehicleParkingManagementDB];
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Customer
(
    @ActionType         INT,

    @CustomerID         INT = NULL,
    @CustomerName       NVARCHAR(200) = NULL,
    @MobileNumber       VARCHAR(20) = NULL,
    @EmailAddress       VARCHAR(255) = NULL,
    @Address            NVARCHAR(500) = NULL,

    @PerformedByUserID  INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    /* ============================================================
       ACTION 1: GET ALL ACTIVE CUSTOMERS
       ============================================================ */
    IF @ActionType = 1
    BEGIN
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
        WHERE ActiveStatus = 1
        ORDER BY CustomerName;

        RETURN;
    END;


    /* ============================================================
       ACTION 2: GET CUSTOMER BY ID
       ============================================================ */
    IF @ActionType = 2
    BEGIN
        IF @CustomerID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Customer ID is required.' AS Message;
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
        WHERE CustomerID = @CustomerID;

        RETURN;
    END;


    /* ============================================================
       ACTION 3: CREATE CUSTOMER
       ============================================================ */
    IF @ActionType = 3
    BEGIN
        -- Customer name is required
        IF NULLIF(LTRIM(RTRIM(@CustomerName)), '') IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Customer name is required.' AS Message;
            RETURN;
        END;

        -- Mobile number is required
        IF NULLIF(LTRIM(RTRIM(@MobileNumber)), '') IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Mobile number is required.' AS Message;
            RETURN;
        END;

        -- Check duplicate mobile number
        IF EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_CUSTOMER
            WHERE MobileNumber = LTRIM(RTRIM(@MobileNumber))
              AND ActiveStatus = 1
        )
        BEGIN
            SELECT
                409 AS StatusCode,
                N'A customer with this mobile number already exists.' AS Message;
            RETURN;
        END;

        INSERT INTO dbo.PARKING_CUSTOMER
        (
            CustomerName,
            MobileNumber,
            EmailAddress,
            Address,
            RegisteredDate,
            ActiveStatus,
            CreatedAt,
            CreatedBy
        )
        VALUES
        (
            LTRIM(RTRIM(@CustomerName)),
            LTRIM(RTRIM(@MobileNumber)),
            NULLIF(LTRIM(RTRIM(@EmailAddress)), ''),
            NULLIF(LTRIM(RTRIM(@Address)), ''),
            CAST(SYSUTCDATETIME() AS DATE),
            1,
            SYSUTCDATETIME(),
            @PerformedByUserID
        );

        SELECT
            201 AS StatusCode,
            N'Customer created successfully.' AS Message,
            SCOPE_IDENTITY() AS CustomerID;

        RETURN;
    END;


    /* ============================================================
       ACTION 4: UPDATE CUSTOMER
       ============================================================ */
    IF @ActionType = 4
    BEGIN
        -- Required fields
        IF @CustomerID IS NULL
           OR NULLIF(LTRIM(RTRIM(@CustomerName)), '') IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Customer ID and Customer name are required.' AS Message;
            RETURN;
        END;

        -- Check customer exists and is active
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_CUSTOMER
            WHERE CustomerID = @CustomerID
              AND ActiveStatus = 1
        )
        BEGIN
            SELECT
                404 AS StatusCode,
                N'Customer not found or is inactive.' AS Message;
            RETURN;
        END;

        -- Check duplicate mobile number
        IF NULLIF(LTRIM(RTRIM(@MobileNumber)), '') IS NOT NULL
        BEGIN
            IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_CUSTOMER
                WHERE MobileNumber = LTRIM(RTRIM(@MobileNumber))
                  AND CustomerID <> @CustomerID
                  AND ActiveStatus = 1
            )
            BEGIN
                SELECT
                    409 AS StatusCode,
                    N'A customer with this mobile number already exists.' AS Message;
                RETURN;
            END;
        END;

        -- Update customer
        UPDATE dbo.PARKING_CUSTOMER
        SET
            CustomerName = LTRIM(RTRIM(@CustomerName)),
            MobileNumber = NULLIF(LTRIM(RTRIM(@MobileNumber)), ''),
            EmailAddress = NULLIF(LTRIM(RTRIM(@EmailAddress)), ''),
            Address = NULLIF(LTRIM(RTRIM(@Address)), ''),
            UpdatedAt = SYSUTCDATETIME(),
            UpdatedBy = @PerformedByUserID
        WHERE CustomerID = @CustomerID;

        SELECT
            200 AS StatusCode,
            N'Customer updated successfully.' AS Message;

        RETURN;
    END;


    /* ============================================================
       ACTION 5: DEACTIVATE CUSTOMER
       ============================================================ */
    IF @ActionType = 5
    BEGIN
        IF @CustomerID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Customer ID is required.' AS Message;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_CUSTOMER
            WHERE CustomerID = @CustomerID
              AND ActiveStatus = 1
        )
        BEGIN
            SELECT
                404 AS StatusCode,
                N'Active customer not found.' AS Message;
            RETURN;
        END;

        UPDATE dbo.PARKING_CUSTOMER
        SET
            ActiveStatus = 0,
            UpdatedAt = SYSUTCDATETIME(),
            UpdatedBy = @PerformedByUserID
        WHERE CustomerID = @CustomerID;

        SELECT
            200 AS StatusCode,
            N'Customer deactivated successfully.' AS Message;

        RETURN;
    END;


    /* ============================================================
       ACTION 6: REACTIVATE CUSTOMER
       ============================================================ */
    IF @ActionType = 6
    BEGIN
        IF @CustomerID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Customer ID is required.' AS Message;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_CUSTOMER
            WHERE CustomerID = @CustomerID
              AND ActiveStatus = 0
        )
        BEGIN
            SELECT
                404 AS StatusCode,
                N'Inactive customer not found.' AS Message;
            RETURN;
        END;

        UPDATE dbo.PARKING_CUSTOMER
        SET
            ActiveStatus = 1,
            UpdatedAt = SYSUTCDATETIME(),
            UpdatedBy = @PerformedByUserID
        WHERE CustomerID = @CustomerID;

        SELECT
            200 AS StatusCode,
            N'Customer reactivated successfully.' AS Message;

        RETURN;
    END;


    /* ============================================================
       INVALID ACTION TYPE
       ============================================================ */
    SELECT
        400 AS StatusCode,
        N'Invalid ActionType.' AS Message;

END;
GO