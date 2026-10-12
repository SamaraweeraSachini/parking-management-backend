USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Settings
(
    @ActionType                  INT,

    @p_facilityName              NVARCHAR(100) = NULL,
    @p_address                   NVARCHAR(300) = NULL,
    @p_contactNumber             NVARCHAR(30) = NULL,
    @p_receiptMessage            NVARCHAR(300) = NULL,
    @p_dailyThresholdHours       INT = NULL,
    @p_monthlyCapacityPercentage DECIMAL(5,2) = NULL,
    @p_uid                       BIGINT = NULL,

    @ResultStatusCode            INT OUTPUT,
    @Result                      VARCHAR(500) OUTPUT,
    @ExceptionMessage            VARCHAR(MAX) OUTPUT
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

        SET @p_facilityName =
            NULLIF(LTRIM(RTRIM(@p_facilityName)), N'');

        SET @p_address =
            NULLIF(LTRIM(RTRIM(@p_address)), N'');

        SET @p_contactNumber =
            NULLIF(LTRIM(RTRIM(@p_contactNumber)), N'');

        SET @p_receiptMessage =
            NULLIF(LTRIM(RTRIM(@p_receiptMessage)), N'');

        IF @ActionType IS NULL OR @ActionType NOT IN (1, 2)
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = 'Invalid action type.';
            RETURN;
        END;

        /* ====================================================
           1. Read application settings
           ==================================================== */

        IF @ActionType = 1
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
                SET @Result =
                    'An authenticated active user is required.';
                RETURN;
            END;

            SELECT
                SettingsID,
                FacilityName,
                Address,
                ContactNumber,
                ReceiptMessage,
                DailyThresholdHours,
                MonthlyCapacityPercentage,
                UpdatedAt,
                UpdatedBy
            FROM dbo.PARKING_APP_SETTINGS
            WHERE SettingsID = 1;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Application settings were not found.';
                RETURN;
            END;

            SET @ResultStatusCode = 1;
            SET @Result =
                'Application settings retrieved successfully';
            RETURN;
        END;

        /* ====================================================
           2. Validate the complete settings save
           ==================================================== */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @p_facilityName IS NULL OR @p_receiptMessage IS NULL
            SET @ValidationMessage =
                'Facility name and receipt message are required.';
        ELSE IF @p_dailyThresholdHours IS NULL
            OR @p_dailyThresholdHours NOT BETWEEN 1 AND 24
            SET @ValidationMessage =
                'Daily threshold must be between 1 and 24 hours.';
        ELSE IF @p_contactNumber IS NOT NULL
            AND LEN(@p_contactNumber) NOT BETWEEN 7 AND 30
            SET @ValidationMessage =
                'Contact number must contain 7-30 characters.';
        ELSE IF @p_monthlyCapacityPercentage IS NOT NULL
            AND @p_monthlyCapacityPercentage NOT BETWEEN 0 AND 100
            SET @ValidationMessage =
                'Monthly capacity percentage must be between 0 and 100, or NULL.';
        ELSE IF @@TRANCOUNT <> 0
            SET @ValidationMessage =
                'Call this procedure without an existing transaction.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           3. Lock configuration and verify administrator access
           ==================================================== */

        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;

        DECLARE @LockResult INT;

        EXEC @LockResult = sys.sp_getapplock
            @Resource = N'ParkingV2Configuration',
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 10000;

        IF @LockResult < 0
            SET @ValidationMessage =
                'Parking configuration is busy. Please retry.';
        ELSE IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER WITH (HOLDLOCK)
            WHERE UserID = @p_uid
              AND UserRole = 'A'
              AND ActiveStatus = 1
        )
            SET @ValidationMessage =
                'An active administrator is required.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           4. Save application settings
           ==================================================== */

        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

        UPDATE dbo.PARKING_APP_SETTINGS
        SET
            FacilityName = @p_facilityName,
            Address = @p_address,
            ContactNumber = @p_contactNumber,
            ReceiptMessage = @p_receiptMessage,
            DailyThresholdHours = @p_dailyThresholdHours,
            MonthlyCapacityPercentage = @p_monthlyCapacityPercentage,
            UpdatedAt = @Now,
            UpdatedBy = @p_uid
        WHERE SettingsID = 1;

        IF @@ROWCOUNT <> 1
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = 'Application settings were not found.';
            RETURN;
        END;

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;
        SET @Result = 'Application settings saved successfully';

        SELECT
            1 AS SettingsID,
            @Now AS UpdatedAtUTC;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while processing application settings';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO