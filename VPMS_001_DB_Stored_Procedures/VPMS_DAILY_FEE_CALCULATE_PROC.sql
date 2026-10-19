USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_DAILY_FEE_CALCULATE_PROC
    @ActionType INT,

    @p_ticketID INT = NULL,
    @p_atUTC DATETIME2(0) = NULL,
    @p_uid INT = NULL,

    @p_amount DECIMAL(12,2) OUTPUT,
    @p_durationSeconds BIGINT OUTPUT,
    @p_billableHours DECIMAL(10,2) OUTPUT,

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
        SET @p_amount = NULL;
        SET @p_durationSeconds = NULL;
        SET @p_billableHours = NULL;

        /** 1. Calculate daily parking fee **/
        IF @ActionType = 1
        BEGIN
            IF @p_ticketID IS NULL OR @p_ticketID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid ticket ID is required';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_USER_ROLE IN ('AD', 'OP')
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator or operator is required';
                RETURN;
            END;

            DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
            DECLARE @EntryDateTime DATETIME2(0);
            DECLARE @HourlyRate DECIMAL(12,2);
            DECLARE @DailyRate DECIMAL(12,2);
            DECLARE @ThresholdHours INT;

            SET @p_atUTC = ISNULL(@p_atUTC, @Now);

            SELECT
                @EntryDateTime = VPT_ENTRY_DATE_TIME,
                @HourlyRate = VPT_APPLIED_HOURLY_RATE,
                @DailyRate = VPT_APPLIED_DAILY_RATE,
                @ThresholdHours = VPT_APPLIED_DAILY_THRESHOLD_HOURS
            FROM dbo.VPMS_PARKING_TICKET
            WHERE VPT_TICKET_ID = @p_ticketID
              AND VPT_PARKING_TYPE = 'D'
              AND VPT_TICKET_STATUS = 'O'
              AND VPT_EXIT_DATE_TIME IS NULL;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An open unpaid daily ticket is required';
                RETURN;
            END;

            IF @p_atUTC < @EntryDateTime OR @p_atUTC > @Now
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Calculation time must be between entry time and current server time';
                RETURN;
            END;

            IF @HourlyRate IS NULL
               OR @DailyRate IS NULL
               OR @HourlyRate < 0
               OR @DailyRate < 0
               OR @ThresholdHours IS NULL
               OR @ThresholdHours NOT BETWEEN 1 AND 24
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'The ticket is missing valid saved rates or its daily threshold';
                RETURN;
            END;

            SET @p_durationSeconds =
                DATEDIFF_BIG(SECOND, @EntryDateTime, @p_atUTC);

            SET @p_billableHours =
                TRY_CONVERT(DECIMAL(10,2), @p_durationSeconds / 3600.0);

            IF @p_billableHours IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking duration exceeds the supported range';
                RETURN;
            END;

            DECLARE @FullDays BIGINT = @p_durationSeconds / 86400;
            DECLARE @RemainingSeconds BIGINT = @p_durationSeconds % 86400;
            DECLARE @RemainingAmount DECIMAL(18,6);

            SET @RemainingAmount =
                CASE
                    WHEN @RemainingSeconds >= CONVERT(BIGINT, @ThresholdHours) * 3600
                        THEN @DailyRate
                    ELSE (@RemainingSeconds / 3600.0) * @HourlyRate
                END;

            SET @p_amount =
                TRY_CONVERT
                (
                    DECIMAL(12,2),
                    ROUND(@FullDays * @DailyRate + @RemainingAmount, 2)
                );

            IF @p_amount IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking fee exceeds the supported range';
                RETURN;
            END;

            SET @Result = 'Daily parking fee calculated successfully';
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