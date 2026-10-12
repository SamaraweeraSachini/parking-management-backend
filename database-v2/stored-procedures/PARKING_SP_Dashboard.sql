USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Dashboard
(
    @ActionType         INT,

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
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;

    BEGIN TRY
        SET @ResultStatusCode = 0;
        SET @Result = '';
        SET @ExceptionMessage = '';

        SET @p_parkingType =
            UPPER(NULLIF(LTRIM(RTRIM(@p_parkingType)), ''));

        SET @p_searchTerm =
            NULLIF(LTRIM(RTRIM(@p_searchTerm)), N'');

        /* ====================================================
           1. Validate inputs and caller
           ==================================================== */

        DECLARE
            @ValidationMessage VARCHAR(500),
            @ActorRole CHAR(1);

        IF @ActionType IS NULL OR @ActionType NOT IN (1, 2, 3)
            SET @ValidationMessage = 'Invalid action type.';
        ELSE IF @p_parkingType IS NULL
            OR @p_parkingType NOT IN ('ALL', 'DAILY', 'MONTHLY')
            SET @ValidationMessage =
                'Parking type must be ALL, DAILY or MONTHLY.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        SELECT @ActorRole = UserRole
        FROM dbo.PARKING_USER
        WHERE UserID = @p_uid
          AND ActiveStatus = 1;

        IF @ActorRole IS NULL
            SET @ValidationMessage =
                'An authenticated active user is required.';
        ELSE IF @ActionType = 1 AND @ActorRole <> 'A'
            SET @ValidationMessage =
                'Only an administrator can view the revenue summary.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ====================================================
           2. Retrieve currently parked vehicles
           ==================================================== */

        IF @ActionType = 2
        BEGIN
            DECLARE @SearchAction INT =
                CASE WHEN @p_searchTerm IS NULL THEN 1 ELSE 2 END;

            EXEC dbo.PARKING_SP_Ticket_Search
                @ActionType = @SearchAction,
                @p_searchTerm = @p_searchTerm,
                @p_parkingType = @p_parkingType,
                @p_onlyCurrent = 1,
                @p_uid = @p_uid,
                @ResultStatusCode = @ResultStatusCode OUTPUT,
                @Result = @Result OUTPUT,
                @ExceptionMessage = @ExceptionMessage OUTPUT;

            RETURN;
        END;

        /* ====================================================
           3. Obtain a consistent view for summary/space board
           ==================================================== */

        IF @@TRANCOUNT <> 0
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result =
                'Call this procedure without an existing transaction.';
            RETURN;
        END;

        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;

        DECLARE @LockResult INT;

        EXEC @LockResult = sys.sp_getapplock
            @Resource = N'ParkingV2Configuration',
            @LockMode = N'Shared',
            @LockOwner = N'Transaction',
            @LockTimeout = 10000;

        IF @LockResult < 0
            SET @ValidationMessage =
                'Dashboard is busy. Please retry.';
        ELSE IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER WITH (HOLDLOCK)
            WHERE UserID = @p_uid
              AND ActiveStatus = 1
              AND (@ActionType <> 1 OR UserRole = 'A')
        )
            SET @ValidationMessage =
                'You are not authorized to view this dashboard.';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

        DECLARE @Today DATE =
            CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

        DECLARE @TodayStartUTC DATETIME2(0) =
            DATEADD(MINUTE, -330, CONVERT(DATETIME2(0), @Today));

        DECLARE @TomorrowStartUTC DATETIME2(0) =
            DATEADD(DAY, 1, @TodayStartUTC);

        -- Temporary working rows within this procedure.
        DECLARE @SpaceBoard TABLE
        (
            SpaceID INT PRIMARY KEY,
            SpaceCode VARCHAR(30),
            SpaceName NVARCHAR(100),
            VehicleTypeID INT,
            VehicleType NVARCHAR(100),
            WheelCount INT,
            SpaceStatus VARCHAR(20),
            BlockReason NVARCHAR(500),
            TicketID INT,
            TicketNumber VARCHAR(40),
            ParkingType VARCHAR(20),
            EntryDateTime DATETIME2(0),
            VehicleNumber VARCHAR(30),
            CustomerName NVARCHAR(200),
            MobileNumber VARCHAR(20),
            ContractNumber VARCHAR(40),
            EffectiveFromUTC DATETIME2(0),
            EffectiveToUTC DATETIME2(0)
        );

        INSERT @SpaceBoard
        (
            SpaceID,
            SpaceCode,
            SpaceName,
            VehicleTypeID,
            VehicleType,
            WheelCount,
            SpaceStatus,
            BlockReason,
            TicketID,
            TicketNumber,
            ParkingType,
            EntryDateTime,
            VehicleNumber,
            CustomerName,
            MobileNumber,
            ContractNumber,
            EffectiveFromUTC,
            EffectiveToUTC
        )
        SELECT
            S.SpaceID,
            S.SpaceCode,
            S.SpaceName,
            S.VehicleTypeID,
            VT.TypeName,
            VT.WheelCount,
            CASE
                WHEN T.TicketID IS NOT NULL THEN 'OCCUPIED'
                WHEN S.SpaceStatus = 'BLOCKED' THEN 'BLOCKED'
                WHEN S.SpaceStatus = 'OCCUPIED' THEN 'OCCUPIED'
                WHEN R.ReservationID IS NOT NULL THEN 'RESERVED'
                ELSE 'AVAILABLE'
            END,
            S.BlockReason,
            T.TicketID,
            T.TicketNumber,
            T.ParkingType,
            T.EntryDateTime,
            CASE
                WHEN T.TicketID IS NOT NULL THEN V.VehicleNumber
                ELSE R.VehicleNumber
            END,
            CASE
                WHEN T.TicketID IS NOT NULL
                    THEN COALESCE(T.CustomerName, C.CustomerName)
                ELSE R.CustomerName
            END,
            CASE
                WHEN T.TicketID IS NOT NULL
                    THEN COALESCE(T.MobileNumber, C.MobileNumber)
                ELSE R.MobileNumber
            END,
            COALESCE(TC.ContractNumber, R.ContractNumber),
            R.EffectiveFromUTC,
            R.EffectiveToUTC
        FROM dbo.PARKING_SPACE AS S
        INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
            ON VT.VehicleTypeID = S.VehicleTypeID
        LEFT JOIN dbo.PARKING_TICKET AS T
            ON T.SpaceID = S.SpaceID
           AND T.ExitDateTime IS NULL
        LEFT JOIN dbo.PARKING_CUSTOMER_VEHICLE AS V
            ON V.VehicleID = T.VehicleID
        LEFT JOIN dbo.PARKING_MONTHLY_CONTRACT AS TC
            ON TC.ContractID = T.MonthlyContractID
        LEFT JOIN dbo.PARKING_CUSTOMER AS C
            ON C.CustomerID = COALESCE(TC.CustomerID, V.CustomerID)
        OUTER APPLY
        (
            SELECT TOP (1)
                MR.ReservationID,
                MR.EffectiveFromUTC,
                MR.EffectiveToUTC,
                MC.ContractNumber,
                RV.VehicleNumber,
                RC.CustomerName,
                RC.MobileNumber
            FROM dbo.PARKING_MONTHLY_RESERVATION AS MR
            INNER JOIN dbo.PARKING_MONTHLY_PAYMENT AS MP
                ON MP.MonthlyPaymentID = MR.MonthlyPaymentID
            INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS MC
                ON MC.ContractID = MP.ContractID
            INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS RV
                ON RV.VehicleID = MC.VehicleID
            INNER JOIN dbo.PARKING_CUSTOMER AS RC
                ON RC.CustomerID = MC.CustomerID
            WHERE MR.SpaceID = S.SpaceID
              AND MP.PaymentStatus = 'COMPLETED'
              AND MC.ContractStatus = 'ACTIVE'
              AND MC.CancelledAt IS NULL
              AND MC.StartDate <= @Today
              AND MC.EndDate >= @Today
              AND MP.PeriodStartDate <= @Today
              AND MP.PeriodEndDate >= @Today
              AND MR.EffectiveFromUTC <= @Now
              AND MR.EffectiveToUTC > @Now
            ORDER BY MR.ReservationID
        ) AS R
        WHERE S.ActiveStatus = 1;

        /* ====================================================
           4. Return the parking space board
           ==================================================== */

        IF @ActionType = 3
        BEGIN
            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SELECT
                SpaceID,
                SpaceCode,
                SpaceName,
                VehicleTypeID,
                VehicleType,
                WheelCount,
                SpaceStatus,
                BlockReason,
                TicketID,
                TicketNumber,
                ParkingType,
                EntryDateTime,
                VehicleNumber,
                CustomerName,
                MobileNumber,
                ContractNumber,
                EffectiveFromUTC,
                EffectiveToUTC
            FROM @SpaceBoard
            ORDER BY SpaceCode, SpaceID;

            SET @ResultStatusCode = 1;
            SET @Result = 'Parking space board retrieved successfully';
            RETURN;
        END;

        /* ====================================================
           5. Return the administrator dashboard summary
           ==================================================== */

        ;WITH SpaceTotals AS
        (
            SELECT
                COUNT(*) AS TotalSpaces,
                COUNT(CASE WHEN SpaceStatus = 'OCCUPIED' THEN 1 END)
                    AS OccupiedSpaces,
                COUNT(CASE WHEN SpaceStatus = 'AVAILABLE' THEN 1 END)
                    AS AvailableSpaces,
                COUNT(CASE WHEN SpaceStatus = 'RESERVED' THEN 1 END)
                    AS ReservedSpaces,
                COUNT(CASE WHEN SpaceStatus = 'BLOCKED' THEN 1 END)
                    AS BlockedSpaces
            FROM @SpaceBoard
        ),
        TodayVisits AS
        (
            SELECT
                COUNT(CASE WHEN ParkingType = 'DAILY' THEN 1 END)
                    AS TodayDailyVehicles,
                COUNT(CASE WHEN ParkingType = 'MONTHLY' THEN 1 END)
                    AS TodayMonthlyVehicles
            FROM dbo.PARKING_TICKET
            WHERE EntryDateTime >= @TodayStartUTC
              AND EntryDateTime < @TomorrowStartUTC
              AND TicketStatus <> 'CANCELLED'
        ),
        DailyCollections AS
        (
            SELECT COALESCE(SUM(Amount), 0) AS TodayDailyRevenue
            FROM dbo.PARKING_PAYMENT
            WHERE PaymentStatus = 'COMPLETED'
              AND PaymentDateTime >= @TodayStartUTC
              AND PaymentDateTime < @TomorrowStartUTC
        ),
        MonthlyCollections AS
        (
            SELECT COALESCE(SUM(Amount), 0) AS TodayMonthlyRevenue
            FROM dbo.PARKING_MONTHLY_PAYMENT
            WHERE PaymentStatus = 'COMPLETED'
              AND PaymentDateTime >= @TodayStartUTC
              AND PaymentDateTime < @TomorrowStartUTC
        ),
        CurrentVisits AS
        (
            SELECT
                COUNT(*) AS CurrentlyParkedVehicles,
                COUNT(CASE WHEN ParkingType = 'DAILY' THEN 1 END)
                    AS CurrentlyParkedDailyVehicles,
                COUNT(CASE WHEN ParkingType = 'MONTHLY' THEN 1 END)
                    AS CurrentlyParkedMonthlyVehicles
            FROM dbo.PARKING_TICKET
            WHERE ExitDateTime IS NULL
        )
        SELECT
            S.TotalSpaces,
            S.OccupiedSpaces,
            S.AvailableSpaces,
            S.ReservedSpaces,
            S.BlockedSpaces,
            V.TodayDailyVehicles,
            V.TodayMonthlyVehicles,
            D.TodayDailyRevenue,
            M.TodayMonthlyRevenue,
            D.TodayDailyRevenue + M.TodayMonthlyRevenue
                AS TodayTotalRevenue,
            C.CurrentlyParkedVehicles,
            C.CurrentlyParkedDailyVehicles,
            C.CurrentlyParkedMonthlyVehicles,
            @Today AS BusinessDate,
            @Now AS UpdatedAtUTC
        FROM SpaceTotals AS S
        CROSS JOIN TodayVisits AS V
        CROSS JOIN DailyCollections AS D
        CROSS JOIN MonthlyCollections AS M
        CROSS JOIN CurrentVisits AS C;

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;
        SET @Result = 'Dashboard summary retrieved successfully';
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while retrieving dashboard details';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO