USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_SETTINGS_PROC
    @ActionType INT,

    @p_facilityName VARCHAR(100) = NULL,
    @p_address VARCHAR(300) = NULL,
    @p_contactNumber VARCHAR(20) = NULL,
    @p_receiptMessage VARCHAR(300) = NULL,
    @p_dailyThresholdHours INT = NULL,
    @p_monthlyCapacityPercentage DECIMAL(5,2) = NULL,
    @p_isActive CHAR(1) = NULL,
    @p_uid INT = NULL,

    @ResultStatusCode INT OUTPUT,
    @Result VARCHAR(MAX) OUTPUT,
    @ExceptionMessage VARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;

    BEGIN TRY
        SET @ResultStatusCode = 1;
        SET @Result = 'Success';
        SET @ExceptionMessage = NULL;

        SET @p_facilityName = NULLIF(LTRIM(RTRIM(@p_facilityName)), '');
        SET @p_address = NULLIF(LTRIM(RTRIM(@p_address)), '');
        SET @p_contactNumber = NULLIF(LTRIM(RTRIM(@p_contactNumber)), '');
        SET @p_receiptMessage = NULLIF(LTRIM(RTRIM(@p_receiptMessage)), '');

        /** 1. Get application settings **/
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
                VPS_SETTINGS_ID,
                VPS_FACILITY_NAME,
                VPS_ADDRESS,
                VPS_CONTACT_NUMBER,
                VPS_RECEIPT_MESSAGE,
                VPS_DAILY_THRESHOLD_HOURS,
                VPS_MONTHLY_CAPACITY_PERCENTAGE,
                VPS_IS_ACTIVE
            FROM dbo.VPMS_APP_SETTINGS
            WHERE VPS_SETTINGS_ID = 1;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Application settings were not found';
                RETURN;
            END;

            SET @Result = 'Application settings retrieved successfully';
        END

        /** 2. Save application settings **/
        ELSE IF @ActionType = 2
        BEGIN
            IF @p_facilityName IS NULL OR @p_receiptMessage IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Facility name and receipt message are required';
                RETURN;
            END;

            IF @p_dailyThresholdHours IS NULL
               OR @p_dailyThresholdHours NOT BETWEEN 1 AND 24
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Daily threshold must be between 1 and 24 hours';
                RETURN;
            END;

            IF @p_contactNumber IS NOT NULL
            BEGIN
                IF DATALENGTH(@p_contactNumber) <> 10
                   OR @p_contactNumber COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9]%'
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Contact number must contain exactly 10 digits';
                    RETURN;
                END;
            END;

            IF @p_monthlyCapacityPercentage IS NOT NULL
               AND @p_monthlyCapacityPercentage NOT BETWEEN 0 AND 100
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly capacity percentage must be between 0 and 100';
                RETURN;
            END;

            IF @p_isActive IS NOT NULL
               AND @p_isActive NOT IN ('A', 'I')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Status must be A - Active / I - Inactive';
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
                SET @Result = 'Parking management is busy. Please retry';
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

            UPDATE dbo.VPMS_APP_SETTINGS
            SET VPS_FACILITY_NAME = @p_facilityName,
                VPS_ADDRESS = @p_address,
                VPS_CONTACT_NUMBER = @p_contactNumber,
                VPS_RECEIPT_MESSAGE = @p_receiptMessage,
                VPS_DAILY_THRESHOLD_HOURS = @p_dailyThresholdHours,
                VPS_MONTHLY_CAPACITY_PERCENTAGE = @p_monthlyCapacityPercentage,
                VPS_IS_ACTIVE = ISNULL(@p_isActive, VPS_IS_ACTIVE),
                VPS_UPDATED_BY = @p_uid,
                VPS_UPDATED_DATE = SYSUTCDATETIME()
            WHERE VPS_SETTINGS_ID = 1;

            IF @@ROWCOUNT <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Application settings were not found';
                RETURN;
            END;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SET @Result = 'Application settings saved successfully';
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