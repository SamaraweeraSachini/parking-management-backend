USE [VehicleParkingManagementDB];
GO

CREATE PROCEDURE dbo.PARKING_SP_User
(
    @ActionType         INT,

    @UserID             INT = NULL,
    @FirstName          NVARCHAR(100) = NULL,
    @LastName           NVARCHAR(100) = NULL,
    @Username           NVARCHAR(100) = NULL,
    @PasswordHash       NVARCHAR(500) = NULL,
    @UserRole           CHAR(1) = NULL,
    @PerformedByUserID  INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* Remove unnecessary spaces from supplied values. */
    SET @FirstName = NULLIF(LTRIM(RTRIM(@FirstName)), N'');
    SET @LastName = NULLIF(LTRIM(RTRIM(@LastName)), N'');
    SET @Username = NULLIF(LTRIM(RTRIM(@Username)), N'');
    SET @PasswordHash = NULLIF(LTRIM(RTRIM(@PasswordHash)), N'');

    /*
        ActionType values:

        1 = Find active user by username for login
        2 = Create user
        3 = List all users
        4 = Get user by ID
        5 = Update user
        6 = Deactivate user
        7 = Reactivate user
        8 = Update password hash
    */

    /* ============================================================
       ACTION 1: FIND USER FOR LOGIN

       PasswordHash is returned only for backend verification.
       SQL Server does not compare the entered password.
       ============================================================ */
    IF @ActionType = 1
    BEGIN
        IF @Username IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Username is required.' AS Message;

            RETURN;
        END;

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
        WHERE Username = @Username
          AND ActiveStatus = 1;

        RETURN;
    END;

    /* ============================================================
       ACTION 2: CREATE USER

       The first user must be an administrator.
       After that, only an active administrator can create users.
       ============================================================ */
    IF @ActionType = 2
    BEGIN
        IF @FirstName IS NULL
           OR @LastName IS NULL
           OR @Username IS NULL
           OR @PasswordHash IS NULL
           OR @UserRole IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'First name, last name, username, password hash and role are required.'
                    AS Message;

            RETURN;
        END;

        IF @UserRole NOT IN ('A', 'O')
        BEGIN
            SELECT
                400 AS StatusCode,
                N'User role must be A for Admin or O for Operator.'
                    AS Message;

            RETURN;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER
            WHERE Username = @Username
        )
        BEGIN
            SELECT
                409 AS StatusCode,
                N'Username already exists.' AS Message;

            RETURN;
        END;

        DECLARE @ExistingUserCount INT;

        SELECT @ExistingUserCount = COUNT(*)
        FROM dbo.PARKING_USER;

        /* Bootstrap rule for the very first account. */
        IF @ExistingUserCount = 0
        BEGIN
            IF @UserRole <> 'A'
            BEGIN
                SELECT
                    400 AS StatusCode,
                    N'The first system user must be an administrator.'
                        AS Message;

                RETURN;
            END;
        END;
        ELSE
        BEGIN
            /* Once users exist, only an Admin can create another user. */
            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_USER
                WHERE UserID = @PerformedByUserID
                  AND UserRole = 'A'
                  AND ActiveStatus = 1
            )
            BEGIN
                SELECT
                    403 AS StatusCode,
                    N'Only an active administrator can create users.'
                        AS Message;

                RETURN;
            END;
        END;

        BEGIN TRY
            BEGIN TRANSACTION;

            INSERT INTO dbo.PARKING_USER
            (
                FirstName,
                LastName,
                Username,
                PasswordHash,
                UserRole,
                ActiveStatus,
                CreatedAt,
                CreatedBy
            )
            VALUES
            (
                @FirstName,
                @LastName,
                @Username,
                @PasswordHash,
                @UserRole,
                1,
                SYSUTCDATETIME(),
                @PerformedByUserID
            );

            DECLARE @NewUserID INT = CONVERT(INT, SCOPE_IDENTITY());

            /*
                For the first administrator, CreatedBy is set to their
                own ID because no previous user exists.
            */
            IF @ExistingUserCount = 0
            BEGIN
                UPDATE dbo.PARKING_USER
                SET CreatedBy = @NewUserID
                WHERE UserID = @NewUserID;
            END;

            COMMIT TRANSACTION;

            SELECT
                201 AS StatusCode,
                N'User created successfully.' AS Message,
                @NewUserID AS UserID;

            RETURN;

        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;

            THROW;
        END CATCH;
    END;

    /* ============================================================
       ACTION 3: LIST USERS
       ============================================================ */
    IF @ActionType = 3
    BEGIN
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
        ORDER BY UserID;

        RETURN;
    END;

    /* ============================================================
       ACTION 4: GET USER BY ID
       ============================================================ */
    IF @ActionType = 4
    BEGIN
        IF @UserID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'User ID is required.' AS Message;

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
        WHERE UserID = @UserID;

        RETURN;
    END;

    /* ============================================================
       ACTION 5: UPDATE USER
       ============================================================ */
    IF @ActionType = 5
    BEGIN
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER
            WHERE UserID = @PerformedByUserID
              AND UserRole = 'A'
              AND ActiveStatus = 1
        )
        BEGIN
            SELECT
                403 AS StatusCode,
                N'Only an active administrator can update users.'
                    AS Message;

            RETURN;
        END;

        IF @UserID IS NULL
           OR @FirstName IS NULL
           OR @LastName IS NULL
           OR @Username IS NULL
           OR @UserRole IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'User ID, name, username and role are required.'
                    AS Message;

            RETURN;
        END;

        IF @UserRole NOT IN ('A', 'O')
        BEGIN
            SELECT
                400 AS StatusCode,
                N'User role must be A for Admin or O for Operator.'
                    AS Message;

            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER
            WHERE UserID = @UserID
        )
        BEGIN
            SELECT
                404 AS StatusCode,
                N'User was not found.' AS Message;

            RETURN;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER
            WHERE Username = @Username
              AND UserID <> @UserID
        )
        BEGIN
            SELECT
                409 AS StatusCode,
                N'Username already exists.' AS Message;

            RETURN;
        END;

        /*
            Do not allow the final active administrator to be changed
            into an operator.
        */
        IF @UserRole = 'O'
           AND EXISTS
           (
               SELECT 1
               FROM dbo.PARKING_USER
               WHERE UserID = @UserID
                 AND UserRole = 'A'
                 AND ActiveStatus = 1
           )
           AND
           (
               SELECT COUNT(*)
               FROM dbo.PARKING_USER
               WHERE UserRole = 'A'
                 AND ActiveStatus = 1
           ) = 1
        BEGIN
            SELECT
                409 AS StatusCode,
                N'The final active administrator cannot be changed into an operator.'
                    AS Message;

            RETURN;
        END;

        UPDATE dbo.PARKING_USER
        SET
            FirstName = @FirstName,
            LastName = @LastName,
            Username = @Username,
            UserRole = @UserRole,
            UpdatedAt = SYSUTCDATETIME(),
            UpdatedBy = @PerformedByUserID
        WHERE UserID = @UserID;

        SELECT
            200 AS StatusCode,
            N'User updated successfully.' AS Message;

        RETURN;
    END;

    /* ============================================================
       ACTION 6: DEACTIVATE USER
       ============================================================ */
    IF @ActionType = 6
    BEGIN
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER
            WHERE UserID = @PerformedByUserID
              AND UserRole = 'A'
              AND ActiveStatus = 1
        )
        BEGIN
            SELECT
                403 AS StatusCode,
                N'Only an active administrator can deactivate users.'
                    AS Message;

            RETURN;
        END;

        IF @UserID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'User ID is required.' AS Message;

            RETURN;
        END;

        IF @UserID = @PerformedByUserID
        BEGIN
            SELECT
                409 AS StatusCode,
                N'You cannot deactivate your own account.'
                    AS Message;

            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER
            WHERE UserID = @UserID
        )
        BEGIN
            SELECT
                404 AS StatusCode,
                N'User was not found.' AS Message;

            RETURN;
        END;

        UPDATE dbo.PARKING_USER
        SET
            ActiveStatus = 0,
            UpdatedAt = SYSUTCDATETIME(),
            UpdatedBy = @PerformedByUserID
        WHERE UserID = @UserID;

        SELECT
            200 AS StatusCode,
            N'User deactivated successfully.' AS Message;

        RETURN;
    END;

    /* ============================================================
       ACTION 7: REACTIVATE USER
       ============================================================ */
    IF @ActionType = 7
    BEGIN
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER
            WHERE UserID = @PerformedByUserID
              AND UserRole = 'A'
              AND ActiveStatus = 1
        )
        BEGIN
            SELECT
                403 AS StatusCode,
                N'Only an active administrator can reactivate users.'
                    AS Message;

            RETURN;
        END;

        IF @UserID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'User ID is required.' AS Message;

            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER
            WHERE UserID = @UserID
        )
        BEGIN
            SELECT
                404 AS StatusCode,
                N'User was not found.' AS Message;

            RETURN;
        END;

        UPDATE dbo.PARKING_USER
        SET
            ActiveStatus = 1,
            UpdatedAt = SYSUTCDATETIME(),
            UpdatedBy = @PerformedByUserID
        WHERE UserID = @UserID;

        SELECT
            200 AS StatusCode,
            N'User reactivated successfully.' AS Message;

        RETURN;
    END;

    /* ============================================================
       ACTION 8: UPDATE PASSWORD HASH

       The new hash must already have been generated by the backend.
       ============================================================ */
    IF @ActionType = 8
    BEGIN
        IF @UserID IS NULL OR @PasswordHash IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'User ID and password hash are required.'
                    AS Message;

            RETURN;
        END;

        /*
            A user can change their own password.
            An active administrator can reset another user's password.
        */
        IF @PerformedByUserID <> @UserID
           AND NOT EXISTS
           (
               SELECT 1
               FROM dbo.PARKING_USER
               WHERE UserID = @PerformedByUserID
                 AND UserRole = 'A'
                 AND ActiveStatus = 1
           )
        BEGIN
            SELECT
                403 AS StatusCode,
                N'You are not authorized to change this password.'
                    AS Message;

            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER
            WHERE UserID = @UserID
        )
        BEGIN
            SELECT
                404 AS StatusCode,
                N'User was not found.' AS Message;

            RETURN;
        END;

        UPDATE dbo.PARKING_USER
        SET
            PasswordHash = @PasswordHash,
            UpdatedAt = SYSUTCDATETIME(),
            UpdatedBy = @PerformedByUserID
        WHERE UserID = @UserID;

        SELECT
            200 AS StatusCode,
            N'Password updated successfully.' AS Message;

        RETURN;
    END;

    /* Invalid ActionType */
    SELECT
        400 AS StatusCode,
        N'Invalid ActionType.' AS Message;
END;
GO