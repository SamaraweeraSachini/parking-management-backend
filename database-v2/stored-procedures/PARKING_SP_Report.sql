USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Report
(
    @ActionType         INT,

    @p_fromDate         DATE = NULL,
    @p_toDate           DATE = NULL,
    @p_parkingType      VARCHAR(20) = 'ALL',
    @p_searchTerm       NVARCHAR(200) = NULL,
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

        SET @p_parkingType =
            UPPER(NULLIF(LTRIM(RTRIM(@p_parkingType)), ''));

        SET @p_searchTerm =
            NULLIF(LTRIM(RTRIM(@p_searchTerm)), N'');

        /* ====================================================
           1. Validate inputs and administrator access
           ==================================================== */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType NOT IN (1, 2, 3)
            SET @ValidationMessage = 'Invalid action type.';
        ELSE IF @p_parkingType IS NULL
            OR @p_parkingType NOT IN ('ALL', 'DAILY', 'MONTHLY')
            SET @ValidationMessage =
                'Parking type must be ALL, DAILY or MONTHLY.';
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
              AND UserRole = 'A'
              AND ActiveStatus = 1
        )
            SET @ValidationMessage =
                'An active administrator is required.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           2. Vehicle visit report
           Reuse ticket search and include completed visits.
           ==================================================== */

        IF @ActionType = 2
        BEGIN
            DECLARE @SearchAction INT =
                CASE WHEN @p_searchTerm IS NULL THEN 1 ELSE 2 END;

            EXEC dbo.PARKING_SP_Ticket_Search
                @ActionType = @SearchAction,
                @p_searchTerm = @p_searchTerm,
                @p_parkingType = @p_parkingType,
                @p_onlyCurrent = 0,
                @p_fromDate = @p_fromDate,
                @p_toDate = @p_toDate,
                @p_uid = @p_uid,
                @ResultStatusCode = @ResultStatusCode OUTPUT,
                @Result = @Result OUTPUT,
                @ExceptionMessage = @ExceptionMessage OUTPUT;

            RETURN;
        END;

        /* ====================================================
           3. Collections report
           Group completed payments by Sri Lankan date.
           ==================================================== */

        IF @ActionType = 1
        BEGIN
            DECLARE @FromUTC DATETIME2(0) =
                CASE
                    WHEN @p_fromDate IS NOT NULL
                    THEN DATEADD
                    (
                        MINUTE,
                        -330,
                        CONVERT(DATETIME2(0), @p_fromDate)
                    )
                END;

            DECLARE @ToUTC DATETIME2(0) =
                CASE
                    WHEN @p_toDate IS NOT NULL
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

            ;WITH Collections AS
            (
                SELECT
                    CAST('DAILY' AS VARCHAR(20)) AS PaymentType,
                    PaymentDateTime,
                    Amount
                FROM dbo.PARKING_PAYMENT
                WHERE PaymentStatus = 'COMPLETED'
                  AND @p_parkingType IN ('ALL', 'DAILY')
                  AND
                  (
                      @FromUTC IS NULL
                      OR PaymentDateTime >= @FromUTC
                  )
                  AND
                  (
                      @ToUTC IS NULL
                      OR PaymentDateTime < @ToUTC
                  )

                UNION ALL

                SELECT
                    CAST('MONTHLY' AS VARCHAR(20)),
                    PaymentDateTime,
                    Amount
                FROM dbo.PARKING_MONTHLY_PAYMENT
                WHERE PaymentStatus = 'COMPLETED'
                  AND @p_parkingType IN ('ALL', 'MONTHLY')
                  AND
                  (
                      @FromUTC IS NULL
                      OR PaymentDateTime >= @FromUTC
                  )
                  AND
                  (
                      @ToUTC IS NULL
                      OR PaymentDateTime < @ToUTC
                  )
            )
            SELECT
                CONVERT
                (
                    DATE,
                    DATEADD(MINUTE, 330, PaymentDateTime)
                ) AS CollectionDate,
                SUM
                (
                    CASE WHEN PaymentType = 'DAILY'
                         THEN Amount ELSE 0 END
                ) AS DailyAmount,
                SUM
                (
                    CASE WHEN PaymentType = 'MONTHLY'
                         THEN Amount ELSE 0 END
                ) AS MonthlyAmount,
                SUM(Amount) AS TotalAmount,
                COUNT
                (
                    CASE WHEN PaymentType = 'DAILY' THEN 1 END
                ) AS DailyPaymentCount,
                COUNT
                (
                    CASE WHEN PaymentType = 'MONTHLY' THEN 1 END
                ) AS MonthlyPaymentCount,
                COUNT(*) AS TotalPaymentCount
            FROM Collections
            GROUP BY CONVERT
            (
                DATE,
                DATEADD(MINUTE, 330, PaymentDateTime)
            )
            ORDER BY CollectionDate DESC;

            SET @ResultStatusCode = 1;
            SET @Result = 'Collections report retrieved successfully';
            RETURN;
        END;

        /* ====================================================
           4. Monthly customer and contract report
           Dates select contracts overlapping the report range.
           Payment totals cover the whole contract history.
           ==================================================== */

        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

        DECLARE @Today DATE =
            CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

        SELECT
            MC.ContractID,
            MC.ContractNumber,
            MC.CustomerID,
            C.CustomerName,
            C.MobileNumber,
            MC.VehicleID,
            V.VehicleNumber,
            VT.TypeName AS VehicleType,
            MC.MonthlyFee,
            MC.StartDate,
            MC.EndDate,
            MC.ContractStatus,
            CASE
                WHEN MC.ContractStatus = 'CANCELLED'
                    THEN 'CANCELLED'
                WHEN MC.ContractStatus = 'EXPIRED'
                     OR MC.EndDate < @Today
                    THEN 'EXPIRED'
                WHEN MC.StartDate > @Today
                    THEN 'UPCOMING'
                ELSE 'ACTIVE'
            END AS EffectiveContractStatus,
            CASE
                WHEN MC.ContractStatus = 'ACTIVE'
                     AND MC.CancelledAt IS NULL
                     AND MC.StartDate <= @Today
                     AND MC.EndDate >= @Today
                     AND C.ActiveStatus = 1
                     AND V.ActiveStatus = 1
                     AND V.CustomerID = MC.CustomerID
                     AND VT.ActiveStatus = 1
                     AND EXISTS
                     (
                         SELECT 1
                         FROM dbo.PARKING_MONTHLY_PAYMENT AS MP
                         INNER JOIN dbo.PARKING_MONTHLY_RESERVATION AS R
                             ON R.MonthlyPaymentID = MP.MonthlyPaymentID
                         WHERE MP.ContractID = MC.ContractID
                           AND MP.PaymentStatus = 'COMPLETED'
                           AND MP.PeriodStartDate <= @Today
                           AND MP.PeriodEndDate >= @Today
                           AND R.EffectiveFromUTC <= @Now
                           AND R.EffectiveToUTC > @Now
                     )
                    THEN 'PAID_COVERAGE'
                ELSE 'NO_CURRENT_COVERAGE'
            END AS CoverageToday,
            P.CompletedPaymentCount,
            P.TotalCompletedPayments,
            P.LastPaymentDateTime,
            MC.CancelledAt,
            MC.CancelledReason,
            @Today AS CoverageCheckDate
        FROM dbo.PARKING_MONTHLY_CONTRACT AS MC
        INNER JOIN dbo.PARKING_CUSTOMER AS C
            ON C.CustomerID = MC.CustomerID
        INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS V
            ON V.VehicleID = MC.VehicleID
        INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
            ON VT.VehicleTypeID = V.VehicleTypeID
        OUTER APPLY
        (
            SELECT
                COUNT(*) AS CompletedPaymentCount,
                COALESCE(SUM(Amount), 0) AS TotalCompletedPayments,
                MAX(PaymentDateTime) AS LastPaymentDateTime
            FROM dbo.PARKING_MONTHLY_PAYMENT
            WHERE ContractID = MC.ContractID
              AND PaymentStatus = 'COMPLETED'
        ) AS P
        WHERE
            (@p_fromDate IS NULL OR MC.EndDate >= @p_fromDate)
            AND (@p_toDate IS NULL OR MC.StartDate <= @p_toDate)
            AND
            (
                @p_searchTerm IS NULL
                OR CHARINDEX
                (
                    UPPER(@p_searchTerm),
                    UPPER(MC.ContractNumber)
                ) > 0
                OR CHARINDEX
                (
                    UPPER(@p_searchTerm),
                    UPPER(C.CustomerName)
                ) > 0
                OR CHARINDEX
                (
                    UPPER(@p_searchTerm),
                    UPPER(V.VehicleNumber)
                ) > 0
                OR CHARINDEX
                (
                    @p_searchTerm,
                    C.MobileNumber
                ) > 0
            )
        ORDER BY MC.StartDate DESC, MC.ContractID DESC;

        SET @ResultStatusCode = 1;
        SET @Result =
            'Monthly customer report retrieved successfully';
    END TRY
    BEGIN CATCH
        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while retrieving parking reports';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO