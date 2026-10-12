USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_User_Bootstrap_Admin
(
    @ActionType         INT,

    @p_firstName        NVARCHAR(100) = NULL,
    @p_lastName         NVARCHAR(100) = NULL,
    @p_username         NVARCHAR(100) = NULL,
    @p_passwordHash     NVARCHAR(500) = NULL,
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

        /* ============================================================
           1. Create First Administrator
           ============================================================ */

        IF @ActionType = 1
        BEGIN
            SET @p_firstName =
                NULLIF(LTRIM(RTRIM(@p_firstName)), N'');

            SET @p_lastName =
                NULLIF(LTRIM(RTRIM(@p_lastName)), N'');

            SET @p_username =
                NULLIF(LTRIM(RTRIM(@p_username)), N'');

            IF @p_firstName IS NULL
               OR @p_lastName IS NULL
               OR @p_username IS NULL
               OR NULLIF(LTRIM(RTRIM(@p_passwordHash)), N'') IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result =
                    'First name, last name, username and backend-generated password hash are required';
                RETURN;
            END;

            IF @@TRANCOUNT <> 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result =
                    'Call this procedure without an existing transaction';
                RETURN;
            END;

            BEGIN TRANSACTION;
            SET @StartedTransaction = 1;

            -- Use the same lock as normal user management.
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
                SET @Result =
                    'User administration is busy. Please retry';
                RETURN;
            END;

            DECLARE @UserCount INT;

            SELECT @UserCount = COUNT(*)
            FROM dbo.PARKING_USER WITH (UPDLOCK, HOLDLOCK);

            IF @UserCount > 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;

                SET @ResultStatusCode = -1;
                SET @Result =
                    'Bootstrap is unavailable because user accounts already exist';
                RETURN;
            END;

            INSERT INTO dbo.PARKING_USER
            (
                FirstName,
                LastName,
                Username,
                PasswordHash,
                UserRole,
                CreatedBy
            )
            VALUES
            (
                @p_firstName,
                @p_lastName,
                @p_username,
                @p_passwordHash,
                'A',
                NULL
            );

            DECLARE @NewUserID INT =
                CONVERT(INT, SCOPE_IDENTITY());

            -- No earlier application user exists to create this account.
            UPDATE dbo.PARKING_USER
            SET CreatedBy = @NewUserID
            WHERE UserID = @NewUserID;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = 1;
            SET @Result =
                'First administrator created successfully';

            SELECT @NewUserID AS UserID;
        END

        /* ============================================================
           Invalid Action
           ============================================================ */

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
        SET @Result =
            'An error occurred while creating the first administrator';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO