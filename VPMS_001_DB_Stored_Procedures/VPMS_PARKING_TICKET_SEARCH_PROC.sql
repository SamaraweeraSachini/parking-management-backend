USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_PARKING_TICKET_SEARCH_PROC
    @ActionType INT,

    @p_ticketID INT = NULL,
    @p_searchTerm VARCHAR(200) = NULL,
    @p_parkingType VARCHAR(20) = 'ALL',
    @p_onlyCurrent BIT = 1,
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

        SET @p_searchTerm = NULLIF(LTRIM(RTRIM(@p_searchTerm)), '');
        SET @p_parkingType = ISNULL(UPPER(NULLIF(LTRIM(RTRIM(@p_parkingType)), '')), 'ALL');
        SET @p_onlyCurrent = ISNULL(@p_onlyCurrent, 1);

        DECLARE @FromUTC DATETIME2(0);
        DECLARE @ToUTC DATETIME2(0);

        /** Validate optional date filters **/
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

        /** Convert Sri Lankan date filters to UTC **/
        IF @p_fromDate IS NOT NULL
        BEGIN
            SET @FromUTC =
                DATEADD(MINUTE, -330, CONVERT(DATETIME2(0), @p_fromDate));
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

        /** 1. Get parking tickets or currently parked vehicles **/
        IF @ActionType = 1
        BEGIN
            IF @p_parkingType NOT IN ('ALL', 'D', 'M')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking type must be ALL-ALL / D - Daily / M - Monthly';
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

            SELECT
                T.VPT_TICKET_ID,
                T.VPT_TICKET_NUMBER,
                T.VPT_PARKING_TYPE,
                T.VPT_TICKET_STATUS,
                V.VPV_VEHICLE_NUMBER,
                VT.VVT_TYPE_NAME,
                VT.VVT_WHEEL_COUNT,
                COALESCE(T.VPT_CUSTOMER_NAME, C.VPC_CUSTOMER_NAME) AS CustomerName,
                COALESCE(T.VPT_MOBILE_NUMBER, C.VPC_MOBILE_NUMBER) AS MobileNumber,
                S.VPS_SPACE_CODE,
                T.VPT_ENTRY_DATE_TIME,
                T.VPT_EXIT_DATE_TIME,
                T.VPT_CALCULATED_AMOUNT
            FROM dbo.VPMS_PARKING_TICKET AS T
            INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                ON V.VPV_VEHICLE_ID = T.VPT_VEHICLE_ID
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = V.VPV_VEHICLE_TYPE_ID
            INNER JOIN dbo.VPMS_PARKING_SPACE AS S
                ON S.VPS_SPACE_ID = T.VPT_SPACE_ID
            LEFT JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                ON MC.VPM_CONTRACT_ID = T.VPT_MONTHLY_CONTRACT_ID
            LEFT JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = COALESCE(MC.VPM_CUSTOMER_ID, V.VPV_CUSTOMER_ID)
            WHERE (@p_parkingType = 'ALL' OR T.VPT_PARKING_TYPE = @p_parkingType)
              AND
              (
                  @p_onlyCurrent = 0
                  OR
                  (
                      T.VPT_EXIT_DATE_TIME IS NULL
                      AND T.VPT_TICKET_STATUS IN ('O', 'PP')
                  )
              )
              AND (@FromUTC IS NULL OR T.VPT_ENTRY_DATE_TIME >= @FromUTC)
              AND (@ToUTC IS NULL OR T.VPT_ENTRY_DATE_TIME < @ToUTC)
            ORDER BY T.VPT_ENTRY_DATE_TIME DESC, T.VPT_TICKET_ID DESC;

            SET @Result = 'Parking ticket list retrieved successfully';
        END

        /** 2. Search parking tickets **/
        ELSE IF @ActionType = 2
        BEGIN
            IF @p_searchTerm IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A search term is required';
                RETURN;
            END;

            IF @p_parkingType NOT IN ('A', 'D', 'M')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking type must be A - All / D - Daily / M - Monthly';
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

            SELECT
                T.VPT_TICKET_ID,
                T.VPT_TICKET_NUMBER,
                T.VPT_PARKING_TYPE,
                T.VPT_TICKET_STATUS,
                V.VPV_VEHICLE_NUMBER,
                VT.VVT_TYPE_NAME,
                VT.VVT_WHEEL_COUNT,
                COALESCE(T.VPT_CUSTOMER_NAME, C.VPC_CUSTOMER_NAME) AS CustomerName,
                COALESCE(T.VPT_MOBILE_NUMBER, C.VPC_MOBILE_NUMBER) AS MobileNumber,
                S.VPS_SPACE_CODE,
                T.VPT_ENTRY_DATE_TIME,
                T.VPT_EXIT_DATE_TIME,
                T.VPT_CALCULATED_AMOUNT
            FROM dbo.VPMS_PARKING_TICKET AS T
            INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                ON V.VPV_VEHICLE_ID = T.VPT_VEHICLE_ID
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = V.VPV_VEHICLE_TYPE_ID
            INNER JOIN dbo.VPMS_PARKING_SPACE AS S
                ON S.VPS_SPACE_ID = T.VPT_SPACE_ID
            LEFT JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                ON MC.VPM_CONTRACT_ID = T.VPT_MONTHLY_CONTRACT_ID
            LEFT JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = COALESCE(MC.VPM_CUSTOMER_ID, V.VPV_CUSTOMER_ID)
            WHERE (@p_parkingType = 'A' OR T.VPT_PARKING_TYPE = @p_parkingType)
              AND
              (
                  @p_onlyCurrent = 0
                  OR
                  (
                      T.VPT_EXIT_DATE_TIME IS NULL
                      AND T.VPT_TICKET_STATUS IN ('O', 'PP')
                  )
              )
              AND (@FromUTC IS NULL OR T.VPT_ENTRY_DATE_TIME >= @FromUTC)
              AND (@ToUTC IS NULL OR T.VPT_ENTRY_DATE_TIME < @ToUTC)
              AND
              (
                  CHARINDEX(@p_searchTerm, T.VPT_TICKET_NUMBER) > 0
                  OR CHARINDEX(@p_searchTerm, V.VPV_VEHICLE_NUMBER) > 0
                  OR CHARINDEX(@p_searchTerm, COALESCE(T.VPT_CUSTOMER_NAME, C.VPC_CUSTOMER_NAME)) > 0
                  OR CHARINDEX(@p_searchTerm, COALESCE(T.VPT_MOBILE_NUMBER, C.VPC_MOBILE_NUMBER)) > 0
              )
            ORDER BY T.VPT_ENTRY_DATE_TIME DESC, T.VPT_TICKET_ID DESC;

            SET @Result = 'Parking ticket search completed successfully';
        END

        /** 3. Get parking ticket by ID **/
        ELSE IF @ActionType = 3
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
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An active user is required';
                RETURN;
            END;

            SELECT
                T.VPT_TICKET_ID,
                T.VPT_TICKET_NUMBER,
                T.VPT_PARKING_TYPE,
                T.VPT_TICKET_STATUS,
                T.VPT_VEHICLE_ID,
                V.VPV_VEHICLE_NUMBER,
                V.VPV_VEHICLE_TYPE_ID,
                VT.VVT_TYPE_NAME,
                COALESCE(T.VPT_CUSTOMER_NAME, C.VPC_CUSTOMER_NAME) AS CustomerName,
                COALESCE(T.VPT_MOBILE_NUMBER, C.VPC_MOBILE_NUMBER) AS MobileNumber,
                T.VPT_SPACE_ID,
                S.VPS_SPACE_CODE,
                T.VPT_MONTHLY_CONTRACT_ID,
                MC.VPM_CONTRACT_NUMBER,
                T.VPT_ENTRY_DATE_TIME,
                T.VPT_EXIT_DATE_TIME,
                T.VPT_ENTRY_DESCRIPTION,
                T.VPT_BILLABLE_HOURS,
                T.VPT_CALCULATED_AMOUNT,
                T.VPT_FEE_CALCULATED_DATE,
                P.VPP_PAYMENT_ID,
                P.VPP_PAYMENT_STATUS,
                CASE
                    WHEN P.VPP_PAYMENT_STATUS = 'C' THEN P.VPP_AMOUNT
                END AS DailyPaidAmount
            FROM dbo.VPMS_PARKING_TICKET AS T
            INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                ON V.VPV_VEHICLE_ID = T.VPT_VEHICLE_ID
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = V.VPV_VEHICLE_TYPE_ID
            INNER JOIN dbo.VPMS_PARKING_SPACE AS S
                ON S.VPS_SPACE_ID = T.VPT_SPACE_ID
            LEFT JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                ON MC.VPM_CONTRACT_ID = T.VPT_MONTHLY_CONTRACT_ID
            LEFT JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = COALESCE(MC.VPM_CUSTOMER_ID, V.VPV_CUSTOMER_ID)
            LEFT JOIN dbo.VPMS_PARKING_PAYMENT AS P
                ON P.VPP_TICKET_ID = T.VPT_TICKET_ID
            WHERE T.VPT_TICKET_ID = @p_ticketID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking ticket was not found';
                RETURN;
            END;

            SET @Result = 'Parking ticket retrieved successfully';
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