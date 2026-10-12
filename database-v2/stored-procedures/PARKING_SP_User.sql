USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_User
(
    @ActionType         INT,

    @p_userID           INT = NULL,
    @p_firstName        NVARCHAR(100) = NULL,
    @p_lastName         NVARCHAR(100) = NULL,
    @p_username         NVARCHAR(100) = NULL,
    @p_passwordHash     NVARCHAR(500) = NULL,
    @p_userRole         CHAR(1) = NULL,
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

        SET @p_firstName =
            NULLIF(LTRIM(RTRIM(@p_firstName)), N'');

        SET @p_lastName =
            NULLIF(LTRIM(RTRIM(@p_lastName)), N'');

        SET @p_username =
            NULLIF(LTRIM(RTRIM(@p_username)), N'');

        SET @p_userRole = UPPER(@p_userRole);
        SET @p_includeInactive = ISNULL(@p_includeInactive, 0);

        DECLARE @ValidationMessage VARCHAR(500);

        /* ============================================================
           Shared input validation
           ============================================================ */

        IF @ActionType IS NULL OR @ActionType NOT BETWEEN 1 AND 7
            SET @ValidationMessage = 'Invalid action type';

        ELSE IF @ActionType = 1 AND @p_username IS NULL
            SET @ValidationMessage = 'Username is required';

        ELSE IF @ActionType IN (3, 5, 6, 7)
             AND (@p_userID IS NULL OR @p_userID <= 0)
            SET @ValidationMessage = 'A valid user ID is required';

        ELSE IF @ActionType IN (4, 5)
             AND
             (
                 @p_firstName IS NULL
                 OR @p_lastName IS NULL
                 OR @p_username IS NULL
                 OR @p_userRole IS NULL
                 OR @p_userRole NOT IN ('A', 'O')
             )
            SET @ValidationMessage =
                'First name, last name, username and a valid A/O role are required';

        ELSE IF @ActionType IN (4, 7)
             AND NULLIF(LTRIM(RTRIM(@p_passwordHash)), N'') IS NULL
            SET @ValidationMessage =
                'A backend-generated password hash is required';

        ELSE IF @ActionType = 6 AND @p_isActive IS NULL
            SET @ValidationMessage = 'Active status is required';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ============================================================
           1. Find Active User For Login
           Password verification is performed by the backend.
           ============================================================ */

        IF @ActionType = 1
        BEGIN
            SELECT
                UserID,
                FirstName,
                LastName,
                FullName,
                Username,
                PasswordHash,
                UserRole,
                ActiveStatus
            FROM dbo.PARKING_USER
            WHERE Username = @p_username
              AND ActiveStatus = 1;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Active user was not found';
                RETURN;
            END;

            SET @ResultStatusCode = 1;
            SET @Result = 'Login account retrieved successfully';
            RETURN;
        END;

        /* ============================================================
           2. List Users
           3. Get User By ID
           ============================================================ */

        DECLARE @ActorRole CHAR(1);

        IF @ActionType IN (2, 3)
        BEGIN
            SELECT @ActorRole = UserRole
            FROM dbo.PARKING_USER
            WHERE UserID = @p_uid
              AND ActiveStatus = 1;

            IF @ActorRole IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An authenticated active user is required';
                RETURN;
            END;

            IF @ActionType = 2 AND @ActorRole <> 'A'
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Only an administrator can list users';
                RETURN;
            END;

            IF @ActionType = 3
               AND @ActorRole <> 'A'
               AND @p_uid <> @p_userID
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'You may only view your own account';
                RETURN;
            END;

            SELECT
                UserID,
                FirstName,
                LastName,
                FullName,
                Username,
                UserRole,
                ActiveStatus,
                CreatedAt,
                CreatedBy,
                UpdatedAt,
                UpdatedBy
            FROM dbo.PARKING_USER
            WHERE
                (
                    @ActionType = 2
                    AND
                    (
                        @p_includeInactive = 1
                        OR ActiveStatus = 1
                    )
                )
                OR
                (
                    @ActionType = 3
                    AND UserID = @p_userID
                )
            ORDER BY FullName, UserID;

            IF @@ROWCOUNT = 0 AND @ActionType = 3
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'User was not found';
                RETURN;
            END;

            SET @ResultStatusCode = 1;
            SET @Result = 'User details retrieved successfully';
            RETURN;
        END;

        /* ============================================================
           Shared validation for account writes
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
            @Resource = N'ParkingV2UserAdministration',
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 10000;

        IF @LockResult < 0
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = 'User administration is busy. Please retry';
            RETURN;
        END;

        DECLARE
            @ActiveAdminCount INT,
            @CurrentRole CHAR(1),
            @CurrentActive BIT;

        SELECT
            @ActiveAdminCount = COUNT
            (
                CASE
                    WHEN UserRole = 'A' AND ActiveStatus = 1
                    THEN 1
                END
            )
        FROM dbo.PARKING_USER WITH (UPDLOCK, HOLDLOCK);

        SET @ActorRole = NULL;

        SELECT @ActorRole = UserRole
        FROM dbo.PARKING_USER
        WHERE UserID = @p_uid
          AND ActiveStatus = 1;

        IF @ActionType IN (5, 6, 7)
        BEGIN
            SELECT
                @CurrentRole = UserRole,
                @CurrentActive = ActiveStatus
            FROM dbo.PARKING_USER
            WHERE UserID = @p_userID;
        END;

        SET @ValidationMessage = NULL;

        IF @ActorRole IS NULL
            SET @ValidationMessage =
                'An authenticated active user is required';

        ELSE IF @ActorRole <> 'A'
             AND NOT
             (
                 @ActionType = 7
                 AND @p_uid = @p_userID
             )
            SET @ValidationMessage =
                'Only an administrator can perform this operation';

        ELSE IF @ActionType IN (5, 6, 7)
             AND @CurrentRole IS NULL
            SET @ValidationMessage = 'User was not found';

        ELSE IF @ActionType IN (4, 5)
             AND EXISTS
             (
                 SELECT 1
                 FROM dbo.PARKING_USER
                 WHERE Username = @p_username
                   AND
                   (
                       @ActionType = 4
                       OR UserID <> @p_userID
                   )
             )
            SET @ValidationMessage = 'Username already exists';

        ELSE IF @CurrentRole = 'A'
             AND @CurrentActive = 1
             AND @ActiveAdminCount = 1
             AND
             (
                 (@ActionType = 5 AND @p_userRole = 'O')
                 OR
                 (@ActionType = 6 AND @p_isActive = 0)
             )
            SET @ValidationMessage =
                'The final active administrator cannot be demoted or deactivated';

        ELSE IF @ActionType = 6
             AND @p_isActive = 0
             AND @p_userID = @p_uid
            SET @ValidationMessage =
                'You cannot deactivate your own account';

        ELSE IF @ActionType = 6
             AND @CurrentActive = @p_isActive
            SET @ValidationMessage =
                'The account already has the requested active status';

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
           4. Create User
           ============================================================ */

        IF @ActionType = 4
        BEGIN
            INSERT INTO dbo.PARKING_USER
            (
                FirstName,
                LastName,
                Username,
                PasswordHash,
                UserRole,
                CreatedAt,
                CreatedBy
            )
            VALUES
            (
                @p_firstName,
                @p_lastName,
                @p_username,
                @p_passwordHash,
                @p_userRole,
                @Now,
                @p_uid
            );

            SET @p_userID = CONVERT(INT, SCOPE_IDENTITY());
            SET @Result = 'User created successfully';
        END

        /* ============================================================
           5. Update User Details
           ============================================================ */

        ELSE IF @ActionType = 5
        BEGIN
            UPDATE dbo.PARKING_USER
            SET
                FirstName = @p_firstName,
                LastName = @p_lastName,
                Username = @p_username,
                UserRole = @p_userRole,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE UserID = @p_userID;

            SET @Result = 'User updated successfully';
        END

        /* ============================================================
           6. Activate / Deactivate User
           ============================================================ */

        ELSE IF @ActionType = 6
        BEGIN
            UPDATE dbo.PARKING_USER
            SET
                ActiveStatus = @p_isActive,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE UserID = @p_userID;

            SET @Result =
                CASE
                    WHEN @p_isActive = 1
                        THEN 'User activated successfully'
                    ELSE 'User deactivated successfully'
                END;
        END

        /* ============================================================
           7. Update Password Hash
           ============================================================ */

        ELSE IF @ActionType = 7
        BEGIN
            UPDATE dbo.PARKING_USER
            SET
                PasswordHash = @p_passwordHash,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE UserID = @p_userID;

            UPDATE dbo.PARKING_PASSWORD_RESET
            SET UsedAt = @Now
            WHERE UserID = @p_userID
              AND UsedAt IS NULL;

            SET @Result = 'Password updated successfully';
        END;

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;

        -- Return the affected ID as data, including newly created users.
        SELECT @p_userID AS UserID;

    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result = 'An error occurred while processing user details';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO