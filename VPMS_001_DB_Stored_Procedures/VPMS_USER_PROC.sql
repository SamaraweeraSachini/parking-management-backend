USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_USER_PROC
    @ActionType INT,

    @p_userID INT = NULL,
    @p_firstName VARCHAR(100) = NULL,
    @p_lastName VARCHAR(100) = NULL,
    @p_username VARCHAR(100) = NULL,
    @p_passwordHash VARCHAR(500) = NULL,
    @p_userRole VARCHAR(2) = NULL,
    @p_isActive CHAR(1) = NULL,
    @p_includeInactive BIT = 0,
    @p_uid INT = NULL,

    @ResultStatusCode INT OUTPUT,
    @Result VARCHAR(MAX) OUTPUT,
    @ExceptionMessage VARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @LockResult INT;

    BEGIN TRY
        SET @ResultStatusCode = 1;
        SET @Result = 'Success';
        SET @ExceptionMessage = NULL;

        SET @p_firstName = NULLIF(LTRIM(RTRIM(@p_firstName)), '');
        SET @p_lastName = NULLIF(LTRIM(RTRIM(@p_lastName)), '');
        SET @p_username = NULLIF(LTRIM(RTRIM(@p_username)), '');
        SET @p_userRole = UPPER(NULLIF(LTRIM(RTRIM(@p_userRole)), ''));

        /** 1. Find active login account **/
        IF @ActionType = 1
        BEGIN
            IF @p_username IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Username is required';
                RETURN;
            END;

            SELECT
                VPU_USER_ID,
                VPU_FIRST_NAME,
                VPU_LAST_NAME,
                VPU_FULL_NAME,
                VPU_USER_NAME,
                VPU_PASSWORD_HASH,
                VPU_USER_ROLE,
                VPU_IS_ACTIVE
            FROM dbo.VPMS_PARKING_USER
            WHERE VPU_USER_NAME = @p_username
              AND VPU_IS_ACTIVE = 'A';

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Active user was not found';
                RETURN;
            END;

            SET @Result = 'Login account retrieved successfully';
        END

        /** 2. Get users **/
        ELSE IF @ActionType = 2
        BEGIN
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
                VPU_USER_ID,
                VPU_FIRST_NAME,
                VPU_LAST_NAME,
                VPU_FULL_NAME,
                VPU_USER_NAME,
                VPU_USER_ROLE,
                VPU_IS_ACTIVE
            FROM dbo.VPMS_PARKING_USER
            WHERE ISNULL(@p_includeInactive, 0) = 1
               OR VPU_IS_ACTIVE = 'A'
            ORDER BY VPU_FULL_NAME, VPU_USER_ID;

            SET @Result = 'User list retrieved successfully';
        END

        /** 3. Get user by ID **/
        ELSE IF @ActionType = 3
        BEGIN
            IF @p_userID IS NULL OR @p_userID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid user ID is required';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_IS_ACTIVE = 'A'
                  AND (VPU_USER_ROLE = 'AD' OR VPU_USER_ID = @p_userID)
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator or the account owner is required';
                RETURN;
            END;

            SELECT
                VPU_USER_ID,
                VPU_FIRST_NAME,
                VPU_LAST_NAME,
                VPU_FULL_NAME,
                VPU_USER_NAME,
                VPU_USER_ROLE,
                VPU_IS_ACTIVE
            FROM dbo.VPMS_PARKING_USER
            WHERE VPU_USER_ID = @p_userID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'User was not found';
                RETURN;
            END;

            SET @Result = 'User retrieved successfully';
        END

        /** 4. Add user **/
        ELSE IF @ActionType = 4
        BEGIN
            IF @p_firstName IS NULL
               OR @p_lastName IS NULL
               OR @p_username IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'First name, last name and username are required';
                RETURN;
            END;

            IF @p_userRole IS NULL OR @p_userRole NOT IN ('AD', 'OP')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Role must be AD - Administrator / OP - Operator';
                RETURN;
            END;

            IF NULLIF(LTRIM(RTRIM(@p_passwordHash)), '') IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A backend-generated password hash is required';
                RETURN;
            END;

            IF @@TRANCOUNT > 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Call this action without an existing transaction';
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
                SET @Result = 'User management is busy. Please retry';
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
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator is required';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_NAME = @p_username
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Username already exists';
                RETURN;
            END;

            INSERT INTO dbo.VPMS_PARKING_USER
            (
                VPU_FIRST_NAME,
                VPU_LAST_NAME,
                VPU_USER_NAME,
                VPU_PASSWORD_HASH,
                VPU_USER_ROLE,
                VPU_IS_ACTIVE,
                VPU_CREATED_BY,
                VPU_CREATED_DATE
            )
            VALUES
            (
                @p_firstName,
                @p_lastName,
                @p_username,
                @p_passwordHash,
                @p_userRole,
                'A',
                @p_uid,
                SYSUTCDATETIME()
            );

            SET @p_userID = CONVERT(INT, SCOPE_IDENTITY());

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SET @Result = 'User added successfully';
            SELECT @p_userID AS VPU_USER_ID;
        END

        /** 5. Update user details **/
        ELSE IF @ActionType = 5
        BEGIN
            IF @p_userID IS NULL OR @p_userID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid user ID is required';
                RETURN;
            END;

            IF @p_firstName IS NULL
               OR @p_lastName IS NULL
               OR @p_username IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'First name, last name and username are required';
                RETURN;
            END;

            IF @p_userRole IS NULL OR @p_userRole NOT IN ('AD', 'OP')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Role must be AD - Administrator / OP - Operator';
                RETURN;
            END;

            IF @@TRANCOUNT > 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Call this action without an existing transaction';
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
                SET @Result = 'User management is busy. Please retry';
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
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator is required';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_userID
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'User was not found';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_NAME = @p_username
                  AND VPU_USER_ID <> @p_userID
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Username already exists';
                RETURN;
            END;

            IF @p_userRole <> 'AD'
               AND EXISTS
               (
                   SELECT 1
                   FROM dbo.VPMS_PARKING_USER
                   WHERE VPU_USER_ID = @p_userID
                     AND VPU_USER_ROLE = 'AD'
                     AND VPU_IS_ACTIVE = 'A'
               )
               AND NOT EXISTS
               (
                   SELECT 1
                   FROM dbo.VPMS_PARKING_USER
                   WHERE VPU_USER_ID <> @p_userID
                     AND VPU_USER_ROLE = 'AD'
                     AND VPU_IS_ACTIVE = 'A'
               )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'The final active administrator cannot be demoted';
                RETURN;
            END;

            UPDATE dbo.VPMS_PARKING_USER
            SET VPU_FIRST_NAME = @p_firstName,
                VPU_LAST_NAME = @p_lastName,
                VPU_USER_NAME = @p_username,
                VPU_USER_ROLE = @p_userRole,
                VPU_UPDATED_BY = @p_uid,
                VPU_UPDATED_DATE = SYSUTCDATETIME()
            WHERE VPU_USER_ID = @p_userID;

            IF @@ROWCOUNT <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Could not update the user';
                RETURN;
            END;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SET @Result = 'User updated successfully';
        END

        /** 6. Activate or deactivate user **/
        ELSE IF @ActionType = 6
        BEGIN
            IF @p_userID IS NULL OR @p_userID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid user ID is required';
                RETURN;
            END;

            IF @p_isActive IS NULL OR @p_isActive NOT IN ('A', 'I')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Status is required : A - Active / I - Inactive';
                RETURN;
            END;

            IF @@TRANCOUNT > 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Call this action without an existing transaction';
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
                SET @Result = 'User management is busy. Please retry';
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
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator is required';
                RETURN;
            END;

            IF @p_isActive = 'I' AND @p_userID = @p_uid
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'You cannot deactivate your own account';
                RETURN;
            END;

            IF @p_isActive = 'I'
               AND EXISTS
               (
                   SELECT 1
                   FROM dbo.VPMS_PARKING_USER
                   WHERE VPU_USER_ID = @p_userID
                     AND VPU_USER_ROLE = 'AD'
                     AND VPU_IS_ACTIVE = 'A'
               )
               AND NOT EXISTS
               (
                   SELECT 1
                   FROM dbo.VPMS_PARKING_USER
                   WHERE VPU_USER_ID <> @p_userID
                     AND VPU_USER_ROLE = 'AD'
                     AND VPU_IS_ACTIVE = 'A'
               )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'The final active administrator cannot be deactivated';
                RETURN;
            END;

            UPDATE dbo.VPMS_PARKING_USER
            SET VPU_IS_ACTIVE = @p_isActive,
                VPU_UPDATED_BY = @p_uid,
                VPU_UPDATED_DATE = SYSUTCDATETIME()
            WHERE VPU_USER_ID = @p_userID;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'User was not found';
                RETURN;
            END;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SET @Result = 'User status updated successfully';
        END

        /** 7. Update password hash **/
        ELSE IF @ActionType = 7
        BEGIN
            IF @p_userID IS NULL OR @p_userID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid user ID is required';
                RETURN;
            END;

            IF NULLIF(LTRIM(RTRIM(@p_passwordHash)), '') IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A backend-generated password hash is required';
                RETURN;
            END;

            IF @@TRANCOUNT > 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Call this action without an existing transaction';
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
                SET @Result = 'User management is busy. Please retry';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_IS_ACTIVE = 'A'
                  AND (VPU_USER_ROLE = 'AD' OR VPU_USER_ID = @p_userID)
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator or the account owner is required';
                RETURN;
            END;

            UPDATE dbo.VPMS_PARKING_USER
				SET VPU_PASSWORD_HASH = @p_passwordHash,
					VPU_UPDATED_BY = @p_uid,
					VPU_UPDATED_DATE = SYSUTCDATETIME()
				WHERE VPU_USER_ID = @p_userID;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'User was not found';
                RETURN;
            END;

            /** Invalidate outstanding reset tokens **/
            UPDATE dbo.VPMS_RESET_PASSWORD
				SET VRP_IS_ACTIVE = 'I',
					VRP_UPDATED_BY = @p_uid,
					VRP_UPDATED_DATE = SYSUTCDATETIME()
				WHERE VRP_USER_ID = @p_userID
				  AND VRP_IS_ACTIVE = 'A';

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SET @Result = 'Password updated successfully';
        END
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
        SET @Result = 'Error occurred';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO