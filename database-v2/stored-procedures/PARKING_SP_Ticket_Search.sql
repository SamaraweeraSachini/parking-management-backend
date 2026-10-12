USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Ticket_Search
(
    @ActionType         INT,

    @p_ticketID         INT = NULL,
    @p_searchTerm       NVARCHAR(200) = NULL,
    @p_parkingType      VARCHAR(20) = 'ALL',
    @p_onlyCurrent      BIT = 1,
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

        SET @p_searchTerm =
            NULLIF(LTRIM(RTRIM(@p_searchTerm)), N'');

        SET @p_parkingType =
            UPPER(NULLIF(LTRIM(RTRIM(@p_parkingType)), ''));

        SET @p_onlyCurrent = COALESCE(@p_onlyCurrent, 1);

        /* ====================================================
           1. Validate inputs and caller
           ==================================================== */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType NOT IN (1, 2, 3)
            SET @ValidationMessage = 'Invalid action type.';
        ELSE IF @p_parkingType IS NULL
            OR @p_parkingType NOT IN ('ALL', 'DAILY', 'MONTHLY')
            SET @ValidationMessage =
                'Parking type must be ALL, DAILY or MONTHLY.';
        ELSE IF @ActionType = 2 AND @p_searchTerm IS NULL
            SET @ValidationMessage = 'A search term is required.';
        ELSE IF @ActionType = 3
            AND (@p_ticketID IS NULL OR @p_ticketID <= 0)
            SET @ValidationMessage = 'A valid ticket ID is required.';
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
                WHEN @ActionType IN (1, 2)
                     AND @p_fromDate IS NOT NULL
                THEN DATEADD
                (
                    MINUTE,
                    -330,
                    CONVERT(DATETIME2(0), @p_fromDate)
                )
            END;

        DECLARE @ToUTC DATETIME2(0) =
            CASE
                WHEN @ActionType IN (1, 2)
                     AND @p_toDate IS NOT NULL
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
           3. List, search or retrieve a ticket
           ==================================================== */

        SELECT
            T.TicketID,
            T.TicketNumber,
            T.ParkingType,
            T.TicketStatus,
            T.VehicleID,
            V.VehicleNumber,
            V.VehicleTypeID,
            VT.TypeName AS VehicleType,
            VT.WheelCount,
            C.CustomerID,
            Details.CustomerName,
            Details.MobileNumber,
            T.SpaceID,
            S.SpaceCode,
            T.MonthlyContractID AS ContractID,
            MC.ContractNumber,
            T.EntryDateTime,
            T.ExitDateTime,
            T.EntryDescription,
            T.EntryOperatorID,
            T.ExitOperatorID,
            T.HourlyRateID,
            T.DailyRateID,
            T.AppliedHourlyRate,
            T.AppliedDailyRate,
            T.AppliedDailyThresholdHours,
            T.FeeCalculatedAtUTC,
            T.BillableHours,
            T.CalculatedAmount,
            P.PaymentID,
            P.PaymentStatus,
            CASE
                WHEN P.PaymentStatus = 'COMPLETED' THEN P.Amount
            END AS PaidAmount,
            CONVERT
            (
                BIT,
                CASE
                    WHEN P.PaymentStatus = 'COMPLETED' THEN 1
                    ELSE 0
                END
            ) AS AlreadyPaid
        FROM dbo.PARKING_TICKET AS T
        INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS V
            ON V.VehicleID = T.VehicleID
        INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
            ON VT.VehicleTypeID = V.VehicleTypeID
        INNER JOIN dbo.PARKING_SPACE AS S
            ON S.SpaceID = T.SpaceID
        LEFT JOIN dbo.PARKING_MONTHLY_CONTRACT AS MC
            ON MC.ContractID = T.MonthlyContractID
        LEFT JOIN dbo.PARKING_CUSTOMER AS C
            ON C.CustomerID = COALESCE(MC.CustomerID, V.CustomerID)
        LEFT JOIN dbo.PARKING_PAYMENT AS P
            ON P.TicketID = T.TicketID
        CROSS APPLY
        (
            SELECT
                COALESCE(T.CustomerName, C.CustomerName, N'')
                    AS CustomerName,
                COALESCE(T.MobileNumber, C.MobileNumber, '')
                    AS MobileNumber
        ) AS Details
        WHERE
            (@p_parkingType = 'ALL' OR T.ParkingType = @p_parkingType)
            AND (@p_onlyCurrent = 0 OR T.ExitDateTime IS NULL)
            AND
            (
                (@ActionType = 3 AND T.TicketID = @p_ticketID)
                OR
                (
                    @ActionType IN (1, 2)
                    AND (@FromUTC IS NULL OR T.EntryDateTime >= @FromUTC)
                    AND (@ToUTC IS NULL OR T.EntryDateTime < @ToUTC)
                    AND
                    (
                        @ActionType = 1
                        OR CHARINDEX
                        (
                            UPPER(@p_searchTerm),
                            UPPER(T.TicketNumber)
                        ) > 0
                        OR CHARINDEX
                        (
                            UPPER(@p_searchTerm),
                            UPPER(V.VehicleNumber)
                        ) > 0
                        OR CHARINDEX
                        (
                            UPPER(@p_searchTerm),
                            UPPER(Details.CustomerName)
                        ) > 0
                        OR CHARINDEX
                        (
                            @p_searchTerm,
                            Details.MobileNumber
                        ) > 0
                    )
                )
            )
        ORDER BY T.EntryDateTime DESC, T.TicketID DESC;

        IF @@ROWCOUNT = 0 AND @ActionType = 3
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result =
                'No ticket matches the selected ID and filters.';
            RETURN;
        END;

        SET @ResultStatusCode = 1;
        SET @Result =
            CASE @ActionType
                WHEN 1 THEN 'Parking tickets retrieved successfully'
                WHEN 2 THEN 'Parking ticket search completed successfully'
                WHEN 3 THEN 'Parking ticket retrieved successfully'
            END;
    END TRY
    BEGIN CATCH
        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while retrieving parking tickets';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO