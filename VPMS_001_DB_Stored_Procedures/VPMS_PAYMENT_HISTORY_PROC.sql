USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_PAYMENT_HISTORY_PROC
    @ActionType INT,

    @p_paymentType VARCHAR(20) = 'ALL',
    @p_paymentID INT = NULL,
    @p_searchTerm VARCHAR(200) = NULL,
    @p_fromDate DATE = NULL,
    @p_toDate DATE = NULL,
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

        SET @p_paymentType = ISNULL(UPPER(NULLIF(LTRIM(RTRIM(@p_paymentType)), '')), 'ALL');
        SET @p_searchTerm = NULLIF(LTRIM(RTRIM(@p_searchTerm)), '');

        /** 1. Get payment history **/
        IF @ActionType = 1
        BEGIN
            IF @p_paymentType NOT IN ('ALL', 'D', 'M')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Payment type must be ALL - All / D - Daily / M - Monthly';
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
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An active user is required';
                RETURN;
            END;

            DECLARE @FromUTC DATETIME2(0);
            DECLARE @ToUTC DATETIME2(0);

            IF @p_fromDate IS NOT NULL
            BEGIN
                SET @FromUTC = DATEADD(MINUTE, -330, CONVERT(DATETIME2(0), @p_fromDate));
            END;

            IF @p_toDate IS NOT NULL
            BEGIN
                SET @ToUTC =
                    DATEADD
                    (
                        MINUTE,
                        -330,
                        DATEADD(DAY, 1, CONVERT(DATETIME2(0), @p_toDate))
                    );
            END;

            ;WITH Payments AS
            (
                SELECT
                    'D' AS PaymentType,
                    P.VPP_PAYMENT_ID AS PaymentID,
                    P.VPP_PAYMENT_NUMBER AS PaymentNumber,
                    P.VPP_RECEIPT_NUMBER AS ReceiptNumber,
                    COALESCE(T.VPT_CUSTOMER_NAME, C.VPC_CUSTOMER_NAME) AS CustomerName,
                    COALESCE(T.VPT_MOBILE_NUMBER, C.VPC_MOBILE_NUMBER) AS MobileNumber,
                    V.VPV_VEHICLE_NUMBER AS VehicleNumber,
                    P.VPP_AMOUNT AS Amount,
                    P.VPP_PAYMENT_METHOD AS PaymentMethod,
                    P.VPP_PAYMENT_STATUS AS PaymentStatus,
                    P.VPP_PAYMENT_DATE_TIME AS PaymentDateTime,
                    U.VPU_FULL_NAME AS ReceivedBy
                FROM dbo.VPMS_PARKING_PAYMENT AS P
                INNER JOIN dbo.VPMS_PARKING_TICKET AS T
                    ON T.VPT_TICKET_ID = P.VPP_TICKET_ID
                INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                    ON V.VPV_VEHICLE_ID = T.VPT_VEHICLE_ID
                INNER JOIN dbo.VPMS_PARKING_USER AS U
                    ON U.VPU_USER_ID = P.VPP_RECEIVED_BY_USER_ID
                LEFT JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                    ON C.VPC_CUSTOMER_ID = V.VPV_CUSTOMER_ID
                WHERE @p_paymentType IN ('ALL', 'D')

                UNION ALL

                SELECT
                    'M',
                    MP.VPP_MONTHLY_PAYMENT_ID,
                    MP.VPP_PAYMENT_NUMBER,
                    MP.VPP_RECEIPT_NUMBER,
                    C.VPC_CUSTOMER_NAME,
                    C.VPC_MOBILE_NUMBER,
                    V.VPV_VEHICLE_NUMBER,
                    MP.VPP_AMOUNT,
                    MP.VPP_PAYMENT_METHOD,
                    MP.VPP_PAYMENT_STATUS,
                    MP.VPP_PAYMENT_DATE,
                    U.VPU_FULL_NAME
                FROM dbo.VPMS_MONTHLY_PAYMENT AS MP
                INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                    ON MC.VPM_CONTRACT_ID = MP.VPP_CONTRACT_ID
                INNER JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                    ON C.VPC_CUSTOMER_ID = MC.VPM_CUSTOMER_ID
                INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                    ON V.VPV_VEHICLE_ID = MC.VPM_VEHICLE_ID
                INNER JOIN dbo.VPMS_PARKING_USER AS U
                    ON U.VPU_USER_ID = MP.VPP_RECEIVED_BY_USER_ID
                WHERE @p_paymentType IN ('ALL', 'M')
            )
            SELECT
                PaymentType,
                PaymentID,
                PaymentNumber,
                ReceiptNumber,
                CustomerName,
                VehicleNumber,
                Amount,
                PaymentMethod,
                PaymentStatus,
                PaymentDateTime,
                ReceivedBy
            FROM Payments
            WHERE (@FromUTC IS NULL OR PaymentDateTime >= @FromUTC)
              AND (@ToUTC IS NULL OR PaymentDateTime < @ToUTC)
              AND
              (
                  @p_searchTerm IS NULL
                  OR CHARINDEX(@p_searchTerm, PaymentNumber) > 0
                  OR CHARINDEX(@p_searchTerm, ReceiptNumber) > 0
                  OR CHARINDEX(@p_searchTerm, CustomerName) > 0
                  OR CHARINDEX(@p_searchTerm, VehicleNumber) > 0
                  OR CHARINDEX(@p_searchTerm, MobileNumber) > 0
              )
            ORDER BY PaymentDateTime DESC, PaymentType, PaymentID DESC;

            SET @Result = 'Payment history retrieved successfully';
        END

        /** 2. Get payment receipt **/
        ELSE IF @ActionType = 2
        BEGIN
            IF @p_paymentID IS NULL OR @p_paymentID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid payment ID is required';
                RETURN;
            END;

            IF @p_paymentType NOT IN ('D', 'M')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Receipt payment type must be D - Daily / M - Monthly';
                RETURN;
            END;

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

            IF @p_paymentType = 'D'
            BEGIN
                SELECT
                    'D' AS PaymentType,
                    P.VPP_PAYMENT_ID AS PaymentID,
                    P.VPP_PAYMENT_NUMBER AS PaymentNumber,
                    P.VPP_RECEIPT_NUMBER AS ReceiptNumber,
                    T.VPT_TICKET_NUMBER AS ReferenceNumber,
                    COALESCE(T.VPT_CUSTOMER_NAME, C.VPC_CUSTOMER_NAME) AS CustomerName,
                    V.VPV_VEHICLE_NUMBER AS VehicleNumber,
                    T.VPT_ENTRY_DATE_TIME AS EntryDateTime,
                    T.VPT_EXIT_DATE_TIME AS ExitDateTime,
                    CAST(NULL AS DATE) AS PeriodStartDate,
                    CAST(NULL AS DATE) AS PeriodEndDate,
                    P.VPP_AMOUNT AS Amount,
                    P.VPP_PAYMENT_METHOD AS PaymentMethod,
                    P.VPP_PAYMENT_STATUS AS PaymentStatus,
                    P.VPP_PAYMENT_DATE_TIME AS PaymentDateTime,
                    U.VPU_FULL_NAME AS ReceivedBy,
                    P.VPP_REMARKS AS Remarks,
                    A.VPS_FACILITY_NAME AS FacilityName,
                    A.VPS_ADDRESS AS FacilityAddress,
                    A.VPS_CONTACT_NUMBER AS FacilityContactNumber,
                    A.VPS_RECEIPT_MESSAGE AS ReceiptMessage
                FROM dbo.VPMS_PARKING_PAYMENT AS P
                INNER JOIN dbo.VPMS_PARKING_TICKET AS T
                    ON T.VPT_TICKET_ID = P.VPP_TICKET_ID
                INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                    ON V.VPV_VEHICLE_ID = T.VPT_VEHICLE_ID
                INNER JOIN dbo.VPMS_PARKING_USER AS U
                    ON U.VPU_USER_ID = P.VPP_RECEIVED_BY_USER_ID
                LEFT JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                    ON C.VPC_CUSTOMER_ID = V.VPV_CUSTOMER_ID
                LEFT JOIN dbo.VPMS_APP_SETTINGS AS A
                    ON A.VPS_SETTINGS_ID = 1
                WHERE P.VPP_PAYMENT_ID = @p_paymentID;

                IF @@ROWCOUNT = 0
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Daily payment was not found';
                    RETURN;
                END;
            END
            ELSE IF @p_paymentType = 'M'
            BEGIN
                SELECT
                    'M' AS PaymentType,
                    MP.VPP_MONTHLY_PAYMENT_ID AS PaymentID,
                    MP.VPP_PAYMENT_NUMBER AS PaymentNumber,
                    MP.VPP_RECEIPT_NUMBER AS ReceiptNumber,
                    MC.VPM_CONTRACT_NUMBER AS ReferenceNumber,
                    C.VPC_CUSTOMER_NAME AS CustomerName,
                    V.VPV_VEHICLE_NUMBER AS VehicleNumber,
                    CAST(NULL AS DATETIME2(0)) AS EntryDateTime,
                    CAST(NULL AS DATETIME2(0)) AS ExitDateTime,
                    MP.VPP_PERIOD_START_DATE AS PeriodStartDate,
                    MP.VPP_PERIOD_END_DATE AS PeriodEndDate,
                    MP.VPP_AMOUNT AS Amount,
                    MP.VPP_PAYMENT_METHOD AS PaymentMethod,
                    MP.VPP_PAYMENT_STATUS AS PaymentStatus,
                    MP.VPP_PAYMENT_DATE AS PaymentDateTime,
                    U.VPU_FULL_NAME AS ReceivedBy,
                    MP.VPP_REMARKS AS Remarks,
                    A.VPS_FACILITY_NAME AS FacilityName,
                    A.VPS_ADDRESS AS FacilityAddress,
                    A.VPS_CONTACT_NUMBER AS FacilityContactNumber,
                    A.VPS_RECEIPT_MESSAGE AS ReceiptMessage
                FROM dbo.VPMS_MONTHLY_PAYMENT AS MP
                INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                    ON MC.VPM_CONTRACT_ID = MP.VPP_CONTRACT_ID
                INNER JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                    ON C.VPC_CUSTOMER_ID = MC.VPM_CUSTOMER_ID
                INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                    ON V.VPV_VEHICLE_ID = MC.VPM_VEHICLE_ID
                INNER JOIN dbo.VPMS_PARKING_USER AS U
                    ON U.VPU_USER_ID = MP.VPP_RECEIVED_BY_USER_ID
                LEFT JOIN dbo.VPMS_APP_SETTINGS AS A
                    ON A.VPS_SETTINGS_ID = 1
                WHERE MP.VPP_MONTHLY_PAYMENT_ID = @p_paymentID;

                IF @@ROWCOUNT = 0
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Monthly payment was not found';
                    RETURN;
                END;
            END;

            SET @Result = 'Payment receipt retrieved successfully';
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