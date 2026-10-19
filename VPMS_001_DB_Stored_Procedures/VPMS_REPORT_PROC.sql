USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_REPORT_PROC
    @ActionType INT,

    @p_fromDate DATE = NULL,
    @p_toDate DATE = NULL,
    @p_parkingType VARCHAR(20) = 'ALL',
    @p_searchTerm VARCHAR(200) = NULL,
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

        SET @p_parkingType = ISNULL(UPPER(NULLIF(LTRIM(RTRIM(@p_parkingType)), '')), 'ALL');
        SET @p_searchTerm = NULLIF(LTRIM(RTRIM(@p_searchTerm)), '');

        IF @p_parkingType NOT IN ('ALL', 'D', 'M')
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = 'Parking type must be ALL - All / D - Daily / M - Monthly';
            RETURN;
        END;

        IF @p_fromDate IS NOT NULL
           AND @p_toDate IS NOT NULL
           AND @p_toDate < @p_fromDate
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = 'End date cannot be earlier than start date';
            RETURN;
        END;

        IF @p_fromDate = CONVERT(DATE, '00010101', 112)
           OR @p_toDate = CONVERT(DATE, '00010101', 112)
           OR @p_toDate = CONVERT(DATE, '99991231', 112)
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = 'The selected date is outside the supported range';
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

        /** 1. Collection report **/
        IF @ActionType = 1
        BEGIN
            DECLARE @FromUTC DATETIME2(0);
            DECLARE @ToUTC DATETIME2(0);

            IF @p_fromDate IS NOT NULL
            BEGIN
                SET @FromUTC = DATEADD(MINUTE, -330, CONVERT(DATETIME2(0), @p_fromDate));
            END;

            IF @p_toDate IS NOT NULL
            BEGIN
                SET @ToUTC = DATEADD
                    (
                        MINUTE,
                        -330,
                        DATEADD(DAY, 1, CONVERT(DATETIME2(0), @p_toDate))
                    );
            END;

            ;WITH Collections AS
            (
                SELECT
                    'D' AS PaymentType,
                    VPP_PAYMENT_DATE_TIME AS PaymentDateTime,
                    VPP_AMOUNT AS Amount
                FROM dbo.VPMS_PARKING_PAYMENT
                WHERE VPP_PAYMENT_STATUS = 'C'
					  AND @p_parkingType IN ('ALL', 'D')
					  AND (@FromUTC IS NULL OR VPP_PAYMENT_DATE_TIME >= @FromUTC)
					  AND (@ToUTC IS NULL OR VPP_PAYMENT_DATE_TIME < @ToUTC)

                UNION ALL

                SELECT
                    'M',
                    VPP_PAYMENT_DATE,
                    VPP_AMOUNT
                FROM dbo.VPMS_MONTHLY_PAYMENT
                WHERE VPP_PAYMENT_STATUS = 'C'
					  AND @p_parkingType IN ('ALL', 'M')
					  AND (@FromUTC IS NULL OR VPP_PAYMENT_DATE >= @FromUTC)
					  AND (@ToUTC IS NULL OR VPP_PAYMENT_DATE < @ToUTC)
            )
            SELECT
                CONVERT(DATE, DATEADD(MINUTE, 330, PaymentDateTime)) AS CollectionDate,
                SUM(CASE WHEN PaymentType = 'D' THEN Amount ELSE 0 END) AS DailyAmount,
                SUM(CASE WHEN PaymentType = 'M' THEN Amount ELSE 0 END) AS MonthlyAmount,
                SUM(Amount) AS TotalAmount,
                COUNT(CASE WHEN PaymentType = 'D' THEN 1 END) AS DailyPaymentCount,
                COUNT(CASE WHEN PaymentType = 'M' THEN 1 END) AS MonthlyPaymentCount
            FROM Collections
            GROUP BY CONVERT(DATE, DATEADD(MINUTE, 330, PaymentDateTime))
            ORDER BY CollectionDate DESC;

            SET @Result = 'Collection report retrieved successfully';
        END

        /** 2. Vehicle entry and exit report **/
        ELSE IF @ActionType = 2
        BEGIN
            DECLARE @SearchAction INT = CASE WHEN @p_searchTerm IS NULL THEN 1 ELSE 2 END;

            EXEC dbo.VPMS_PARKING_TICKET_SEARCH_PROC
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
        END

        /** 3. Monthly customer report **/
        ELSE IF @ActionType = 3
        BEGIN
            DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
            DECLARE @Today DATE = CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

            ;WITH PaymentTotals AS
            (
                SELECT
                    VPP_CONTRACT_ID,
                    COUNT(*) AS CompletedPaymentCount,
                    SUM(VPP_AMOUNT) AS TotalCompletedPayments,
                    MAX(VPP_PAYMENT_DATE) AS LastPaymentDateTime
                FROM dbo.VPMS_MONTHLY_PAYMENT
                WHERE VPP_PAYMENT_STATUS = 'C'
                GROUP BY VPP_CONTRACT_ID
            )
            SELECT
                MC.VPM_CONTRACT_ID,
                MC.VPM_CONTRACT_NUMBER,
                C.VPC_CUSTOMER_NAME,
                C.VPC_MOBILE_NUMBER,
                V.VPV_VEHICLE_NUMBER,
                VT.VVT_TYPE_NAME,
                MC.VPM_MONTHLY_FEE,
                MC.VPM_START_DATE,
                MC.VPM_END_DATE,
                MC.VPM_CONTRACT_STATUS,
                CASE
                    WHEN MC.VPM_CONTRACT_STATUS = 'CN' THEN 'CN'
                    WHEN MC.VPM_CONTRACT_STATUS = 'E'
                         OR MC.VPM_END_DATE < @Today THEN 'E'
                    WHEN MC.VPM_START_DATE > @Today THEN 'U'
                    ELSE 'A'
                END AS EffectiveContractStatus,
                CONVERT
                (
                    BIT,
                    CASE
                        WHEN MC.VPM_CONTRACT_STATUS = 'A'
                             AND MC.VPM_START_DATE <= @Today
                             AND MC.VPM_END_DATE >= @Today
                             AND C.VPC_IS_ACTIVE = 'A'
                             AND V.VPV_IS_ACTIVE = 'A'
                             AND V.VPV_CUSTOMER_ID = MC.VPM_CUSTOMER_ID
                             AND VT.VVT_IS_ACTIVE = 'A'
                             AND EXISTS
                             (
                                 SELECT 1
                                 FROM dbo.VPMS_MONTHLY_PAYMENT AS MP
                                 INNER JOIN dbo.VPMS_MONTHLY_RESERVATION AS R
                                     ON R.VPR_MONTHLY_PAYMENT_ID = MP.VPP_MONTHLY_PAYMENT_ID
                                 WHERE MP.VPP_CONTRACT_ID = MC.VPM_CONTRACT_ID
									   AND MP.VPP_PAYMENT_STATUS = 'C'
									   AND MP.VPP_PERIOD_START_DATE <= @Today
									   AND MP.VPP_PERIOD_END_DATE >= @Today
									   AND R.VPR_IS_ACTIVE = 'A'
									   AND R.VPR_EFFECTIVE_FROM_UTC <= @Now
									   AND R.VPR_EFFECTIVE_TO_UTC > @Now
                             )
                            THEN 1
                        ELSE 0
                    END
                ) AS HasPaidCoverageToday,
                ISNULL(P.CompletedPaymentCount, 0) AS CompletedPaymentCount,
                ISNULL(P.TotalCompletedPayments, 0) AS TotalCompletedPayments,
                P.LastPaymentDateTime
            FROM dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
            INNER JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = MC.VPM_CUSTOMER_ID
            INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                ON V.VPV_VEHICLE_ID = MC.VPM_VEHICLE_ID
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = V.VPV_VEHICLE_TYPE_ID
            LEFT JOIN PaymentTotals AS P
                ON P.VPP_CONTRACT_ID = MC.VPM_CONTRACT_ID
            WHERE (@p_fromDate IS NULL OR MC.VPM_END_DATE >= @p_fromDate)
              AND (@p_toDate IS NULL OR MC.VPM_START_DATE <= @p_toDate)
              AND
              (
                  @p_searchTerm IS NULL
                  OR CHARINDEX(@p_searchTerm, MC.VPM_CONTRACT_NUMBER) > 0
                  OR CHARINDEX(@p_searchTerm, C.VPC_CUSTOMER_NAME) > 0
                  OR CHARINDEX(@p_searchTerm, V.VPV_VEHICLE_NUMBER) > 0
                  OR CHARINDEX(@p_searchTerm, C.VPC_MOBILE_NUMBER) > 0
              )
            ORDER BY MC.VPM_START_DATE DESC, MC.VPM_CONTRACT_ID DESC;

            SET @Result = 'Monthly customer report retrieved successfully';
        END
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