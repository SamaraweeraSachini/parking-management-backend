USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_PARKING_CUSTOMER_PROC
    @ActionType INT,

    @p_customerID INT = NULL,
    @p_customerName VARCHAR(200) = NULL,
    @p_mobileNumber VARCHAR(20) = NULL,
    @p_emailAddress VARCHAR(254) = NULL,
    @p_address VARCHAR(500) = NULL,
    @p_isActive CHAR(1) = NULL,
    @p_searchTerm VARCHAR(200) = NULL,
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

        SET @p_customerName = NULLIF(LTRIM(RTRIM(@p_customerName)), N'');
        SET @p_mobileNumber = NULLIF(LTRIM(RTRIM(@p_mobileNumber)), '');
        SET @p_searchTerm = NULLIF(LTRIM(RTRIM(@p_searchTerm)), N'');

        /** 1. Get customers **/
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
                VPC_CUSTOMER_ID,
                VPC_CUSTOMER_NAME,
                VPC_MOBILE_NUMBER,
                VPC_EMAIL_ADDRESS,
                VPC_ADDRESS,
                VPC_REGISTERED_DATE,
                VPC_IS_ACTIVE
            FROM dbo.VPMS_PARKING_CUSTOMER
            WHERE (ISNULL(@p_includeInactive, 0) = 1 OR VPC_IS_ACTIVE = 'A')
              AND
              (
                  @p_searchTerm IS NULL
                  OR CHARINDEX(@p_searchTerm, VPC_CUSTOMER_NAME) > 0
                  OR CHARINDEX(@p_searchTerm, VPC_MOBILE_NUMBER) > 0
              )
            ORDER BY VPC_CUSTOMER_NAME, VPC_CUSTOMER_ID;

            SET @Result = 'Customer list retrieved successfully';
        END

        /** 2. Get customer by ID **/
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
                VPC_CUSTOMER_ID,
                VPC_CUSTOMER_NAME,
                VPC_MOBILE_NUMBER,
                VPC_EMAIL_ADDRESS,
                VPC_ADDRESS,
                VPC_REGISTERED_DATE,
                VPC_IS_ACTIVE
            FROM dbo.VPMS_PARKING_CUSTOMER
            WHERE VPC_CUSTOMER_ID = @p_customerID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer was not found';
                RETURN;
            END;

            SET @Result = 'Customer retrieved successfully';
        END

        /** 3. Add customer **/
        ELSE IF @ActionType = 3
        BEGIN
            IF @p_customerName IS NULL
               OR @p_mobileNumber IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer name and mobile number are required';
                RETURN;
            END;

            IF DATALENGTH(@p_mobileNumber) <> 10
               OR @p_mobileNumber COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9]%'
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Mobile number must contain exactly 10 digits';
                RETURN;
            END;

            IF @p_isActive IS NOT NULL
               AND @p_isActive NOT IN ('A', 'I')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Status must be A - Active / I - Inactive';
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

            INSERT INTO dbo.VPMS_PARKING_CUSTOMER
            (
                VPC_CUSTOMER_NAME,
                VPC_MOBILE_NUMBER,
                VPC_EMAIL_ADDRESS,
                VPC_ADDRESS,
                VPC_REGISTERED_DATE,
                VPC_IS_ACTIVE,
                VPC_CREATED_BY,
                VPC_CREATED_DATE
            )
            VALUES
            (
                @p_customerName,
                @p_mobileNumber,
                @p_emailAddress,
                @p_address,
                SYSUTCDATETIME(),
                ISNULL(@p_isActive, 'A'),
                @p_uid,
                SYSUTCDATETIME()
            );

            SET @p_customerID = CONVERT(INT, SCOPE_IDENTITY());
            SET @Result = 'Customer added successfully';

            SELECT @p_customerID AS VPC_CUSTOMER_ID;
        END

        /** 4. Update customer **/
        ELSE IF @ActionType = 4
        BEGIN
            IF @p_customerID IS NULL OR @p_customerID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid customer ID is required';
                RETURN;
            END;

            IF @p_customerName IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer name is required';
                RETURN;
            END;

            IF @p_mobileNumber IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer mobile number is required';
                RETURN;
            END;

            IF DATALENGTH(@p_mobileNumber) <> 10
               OR @p_mobileNumber COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9]%'
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Mobile number must contain exactly 10 digits';
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

            UPDATE dbo.VPMS_PARKING_CUSTOMER
            SET VPC_CUSTOMER_NAME = @p_customerName,
                VPC_MOBILE_NUMBER = @p_mobileNumber,
                VPC_EMAIL_ADDRESS = @p_emailAddress,
                VPC_ADDRESS = @p_address,
                VPC_UPDATED_BY = @p_uid,
                VPC_UPDATED_AT = SYSUTCDATETIME()
            WHERE VPC_CUSTOMER_ID = @p_customerID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer was not found';
                RETURN;
            END;

            SET @Result = 'Customer updated successfully';
        END

        /** 5. Activate or deactivate customer **/
        ELSE IF @ActionType = 5
        BEGIN
            IF @p_customerID IS NULL OR @p_customerID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid customer ID is required';
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

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_CUSTOMER
                WHERE VPC_CUSTOMER_ID = @p_customerID
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer was not found';
                RETURN;
            END;

            IF @p_isActive = 'I'
            BEGIN
                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE
                    WHERE VPV_CUSTOMER_ID = @p_customerID
                      AND VPV_IS_ACTIVE = 'A'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Deactivate the customer vehicles before deactivating this customer';
                    RETURN;
                END;

                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
                    WHERE VPM_CUSTOMER_ID = @p_customerID
                      AND VPM_CONTRACT_STATUS = 'A'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Resolve active monthly contracts before deactivating this customer';
                    RETURN;
                END;
            END;

            UPDATE dbo.VPMS_PARKING_CUSTOMER
            SET VPC_IS_ACTIVE = @p_isActive,
                VPC_UPDATED_BY = @p_uid,
                VPC_UPDATED_AT = SYSUTCDATETIME()
            WHERE VPC_CUSTOMER_ID = @p_customerID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Customer was not found';
                RETURN;
            END;

            SET @Result = 'Customer status updated successfully';
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