USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Payment_History
(
    @ActionType         INT,

    @p_paymentType      VARCHAR(20) = 'ALL',
    @p_paymentID        INT = NULL,
    @p_searchTerm       NVARCHAR(200) = NULL,
    @p_fromDate         DATE = NULL,
    @p_toDate           DATE = NULL,
    @p_uid              BIGINT = NULL,

    @ResultStatusCode   INT OUTPUT,
    @Result             VARCHAR(500) OUTPUT,
    @ExceptionMessage   VARCHAR(MAX) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        SET @ResultStatusCode = 0;
        SET @Result = '';
        SET @ExceptionMessage = '';

        SET @p_paymentType =
            UPPER(NULLIF(LTRIM(RTRIM(@p_paymentType)), ''));

        SET @p_searchTerm =
            NULLIF(LTRIM(RTRIM(@p_searchTerm)), N'');

        /* ====================================================
           1. Validate inputs and caller
           ==================================================== */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType NOT IN (1, 2)
            SET @ValidationMessage = 'Invalid action type.';
        ELSE IF @p_paymentType IS NULL
            OR @p_paymentType NOT IN ('ALL', 'DAILY', 'MONTHLY')
            SET @ValidationMessage =
                'Payment type must be ALL, DAILY or MONTHLY.';
        ELSE IF @ActionType = 2
            AND
            (
                @p_paymentType = 'ALL'
                OR @p_paymentID IS NULL
                OR @p_paymentID <= 0
            )
            SET @ValidationMessage =
                'Receipt lookup requires DAILY or MONTHLY and a valid payment ID.';
        ELSE IF @p_fromDate IS NOT NULL
            AND @p_toDate IS NOT NULL
            AND @p_toDate < @p_fromDate
            SET @ValidationMessage =
                'ToDate cannot be earlier than FromDate.';
        ELSE IF @p_toDate = CONVERT(DATE, '99991231', 112)
            SET @ValidationMessage =
                'The selected end date is outside the supported range.';
        ELSE IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER
            WHERE UserID = @p_uid
              AND ActiveStatus = 1
        )
            SET @ValidationMessage =
                'An authenticated active user is required.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           2. Convert Sri Lankan report dates to UTC boundaries
           ==================================================== */

        DECLARE @FromUTC DATETIME2(0) =
            CASE
                WHEN @ActionType = 1 AND @p_fromDate IS NOT NULL
                THEN DATEADD
                (
                    MINUTE,
                    -330,
                    CONVERT(DATETIME2(0), @p_fromDate)
                )
            END;

        DECLARE @ToUTC DATETIME2(0) =
            CASE
                WHEN @ActionType = 1 AND @p_toDate IS NOT NULL
                THEN DATEADD
                (
                    MINUTE,
                    -330,
                    DATEADD
                    (
                        DAY,
                        1,
                        CONVERT(DATETIME2(0), @p_toDate)
                    )
                )
            END;

        /* ====================================================
           3. Combine daily and monthly payment details
           ==================================================== */

        ;WITH Payments AS
        (
            SELECT
                CAST('DAILY' AS VARCHAR(20)) AS PaymentType,
                P.PaymentID,
                P.PaymentNumber,
                P.ReceiptNumber,
                P.Amount,
                P.PaymentMethod,
                P.PaymentStatus,
                P.PaymentDateTime,
                P.ReceivedByUserID,
                U.FullName AS ReceivedBy,
                C.CustomerID,
                COALESCE(T.CustomerName, C.CustomerName, N'')
                    AS CustomerName,
                COALESCE(T.MobileNumber, C.MobileNumber, '')
                    AS MobileNumber,
                V.VehicleID,
                V.VehicleNumber,
                VT.TypeName AS VehicleType,
                S.SpaceCode,
                T.TicketID,
                T.TicketNumber,
                T.EntryDateTime,
                T.ExitDateTime,
                CAST(NULL AS INT) AS ContractID,
                CAST(NULL AS VARCHAR(40)) AS ContractNumber,
                CAST(NULL AS DATE) AS PeriodStartDate,
                CAST(NULL AS DATE) AS PeriodEndDate,
                T.AppliedHourlyRate,
                T.AppliedDailyRate,
                T.AppliedDailyThresholdHours,
                T.FeeCalculatedAtUTC,
                P.Remarks
            FROM dbo.PARKING_PAYMENT AS P
            INNER JOIN dbo.PARKING_TICKET AS T
                ON T.TicketID = P.TicketID
            INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS V
                ON V.VehicleID = T.VehicleID
            INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
                ON VT.VehicleTypeID = V.VehicleTypeID
            INNER JOIN dbo.PARKING_SPACE AS S
                ON S.SpaceID = T.SpaceID
            INNER JOIN dbo.PARKING_USER AS U
                ON U.UserID = P.ReceivedByUserID
            LEFT JOIN dbo.PARKING_CUSTOMER AS C
                ON C.CustomerID = V.CustomerID

            UNION ALL

            SELECT
                CAST('MONTHLY' AS VARCHAR(20)),
                MP.MonthlyPaymentID,
                MP.PaymentNumber,
                MP.ReceiptNumber,
                MP.Amount,
                MP.PaymentMethod,
                MP.PaymentStatus,
                MP.PaymentDateTime,
                MP.ReceivedByUserID,
                U.FullName,
                MC.CustomerID,
                C.CustomerName,
                C.MobileNumber,
                V.VehicleID,
                V.VehicleNumber,
                VT.TypeName,
                S.SpaceCode,
                CAST(NULL AS INT),
                CAST(NULL AS VARCHAR(40)),
                CAST(NULL AS DATETIME2(0)),
                CAST(NULL AS DATETIME2(0)),
                MC.ContractID,
                MC.ContractNumber,
                MP.PeriodStartDate,
                MP.PeriodEndDate,
                CAST(NULL AS DECIMAL(12,2)),
                CAST(NULL AS DECIMAL(12,2)),
                CAST(NULL AS INT),
                CAST(NULL AS DATETIME2(0)),
                MP.Remarks
            FROM dbo.PARKING_MONTHLY_PAYMENT AS MP
            INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS MC
                ON MC.ContractID = MP.ContractID
            INNER JOIN dbo.PARKING_CUSTOMER AS C
                ON C.CustomerID = MC.CustomerID
            INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS V
                ON V.VehicleID = MC.VehicleID
            INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
                ON VT.VehicleTypeID = V.VehicleTypeID
            INNER JOIN dbo.PARKING_USER AS U
                ON U.UserID = MP.ReceivedByUserID
            LEFT JOIN dbo.PARKING_MONTHLY_RESERVATION AS R
                ON R.MonthlyPaymentID = MP.MonthlyPaymentID
            LEFT JOIN dbo.PARKING_SPACE AS S
                ON S.SpaceID = R.SpaceID
        )
        SELECT
            P.PaymentType,
            P.PaymentID,
            P.PaymentNumber,
            P.ReceiptNumber,
            P.Amount,
            P.PaymentMethod,
            P.PaymentStatus,
            P.PaymentDateTime,
            P.ReceivedByUserID,
            P.ReceivedBy,
            P.CustomerID,
            P.CustomerName,
            P.MobileNumber,
            P.VehicleID,
            P.VehicleNumber,
            P.VehicleType,
            P.SpaceCode,
            P.TicketID,
            P.TicketNumber,
            P.EntryDateTime,
            P.ExitDateTime,
            P.ContractID,
            P.ContractNumber,
            P.PeriodStartDate,
            P.PeriodEndDate,
            P.AppliedHourlyRate,
            P.AppliedDailyRate,
            P.AppliedDailyThresholdHours,
            P.FeeCalculatedAtUTC,
            P.Remarks,
            A.FacilityName,
            A.Address AS FacilityAddress,
            A.ContactNumber AS FacilityContactNumber,
            A.ReceiptMessage
        FROM Payments AS P
        LEFT JOIN dbo.PARKING_APP_SETTINGS AS A
            ON A.SettingsID = 1
        WHERE
            (@p_paymentType = 'ALL' OR P.PaymentType = @p_paymentType)
            AND
            (
                (
                    @ActionType = 2
                    AND P.PaymentID = @p_paymentID
                )
                OR
                (
                    @ActionType = 1
                    AND (@FromUTC IS NULL OR P.PaymentDateTime >= @FromUTC)
                    AND (@ToUTC IS NULL OR P.PaymentDateTime < @ToUTC)
                    AND
                    (
                        @p_searchTerm IS NULL
                        OR CHARINDEX
                        (
                            UPPER(@p_searchTerm),
                            UPPER(P.PaymentNumber)
                        ) > 0
                        OR CHARINDEX
                        (
                            UPPER(@p_searchTerm),
                            UPPER(P.ReceiptNumber)
                        ) > 0
                        OR CHARINDEX
                        (
                            UPPER(@p_searchTerm),
                            UPPER(P.CustomerName)
                        ) > 0
                        OR CHARINDEX
                        (
                            UPPER(@p_searchTerm),
                            UPPER(P.VehicleNumber)
                        ) > 0
                        OR CHARINDEX
                        (
                            @p_searchTerm,
                            P.MobileNumber
                        ) > 0
                    )
                )
            )
        ORDER BY
            P.PaymentDateTime DESC,
            P.PaymentType,
            P.PaymentID DESC;

        IF @@ROWCOUNT = 0 AND @ActionType = 2
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result =
                CASE @p_paymentType
                    WHEN 'DAILY' THEN 'Daily payment was not found.'
                    WHEN 'MONTHLY' THEN 'Monthly payment was not found.'
                END;
            RETURN;
        END;

        SET @ResultStatusCode = 1;
        SET @Result =
            CASE @ActionType
                WHEN 1 THEN 'Payment history retrieved successfully'
                WHEN 2 THEN 'Payment receipt details retrieved successfully'
            END;
    END TRY
    BEGIN CATCH
        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while retrieving payment history';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO