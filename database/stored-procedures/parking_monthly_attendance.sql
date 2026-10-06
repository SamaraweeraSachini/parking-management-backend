USE [VehicleParkingManagementDB];
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Monthly_Attendance
(
    @ActionType              INT,

    @TicketID                INT = NULL,
    @VehicleID               INT = NULL,
    @ContractID              INT = NULL,
    @SpaceID                 INT = NULL,

    @PerformedByUserID       INT = NULL,

    @MonthlyCapacityPercentage DECIMAL(5,2) = 30.00,

    @FromDate                DATE = NULL,
    @ToDate                  DATE = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;


    /* ============================================================
       VALID ACTION
       ============================================================ */
    IF @ActionType NOT BETWEEN 1 AND 7
    BEGIN
        SELECT
            400 AS StatusCode,
            N'Invalid ActionType.' AS Message;
        RETURN;
    END;


    /* ============================================================
       ACTION 1
       LIST MONTHLY ATTENDANCE
       ============================================================ */
    IF @ActionType = 1
    BEGIN
        SELECT
            t.TicketID,
            t.TicketNumber,

            t.VehicleID,
            v.VehicleNumber,
            vt.TypeName AS VehicleType,

            t.MonthlyContractID,
            mc.ContractNumber,
            c.CustomerName,

            t.SpaceID,
            s.SpaceCode,
            s.SpaceName,

            t.EntryDateTime,
            t.ExitDateTime,
            t.TicketStatus,

            t.EntryOperatorID,
            t.ExitOperatorID

        FROM dbo.PARKING_TICKET AS t

        INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS v
            ON v.VehicleID = t.VehicleID

        INNER JOIN dbo.PARKING_VEHICLE_TYPE AS vt
            ON vt.VehicleTypeID = v.VehicleTypeID

        INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS mc
            ON mc.ContractID = t.MonthlyContractID

        INNER JOIN dbo.PARKING_CUSTOMER AS c
            ON c.CustomerID = mc.CustomerID

        INNER JOIN dbo.PARKING_SPACE AS s
            ON s.SpaceID = t.SpaceID

        WHERE
            t.ParkingType = 'MONTHLY'
            AND
            (
                @FromDate IS NULL
                OR CAST(t.EntryDateTime AS DATE) >= @FromDate
            )
            AND
            (
                @ToDate IS NULL
                OR CAST(t.EntryDateTime AS DATE) <= @ToDate
            )

        ORDER BY
            t.EntryDateTime DESC;

        RETURN;
    END;


    /* ============================================================
       ACTION 2
       GET ATTENDANCE BY TICKET ID
       ============================================================ */
    IF @ActionType = 2
    BEGIN
        IF @TicketID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'TicketID is required.' AS Message;
            RETURN;
        END;


        SELECT
            t.TicketID,
            t.TicketNumber,

            t.VehicleID,
            v.VehicleNumber,
            vt.TypeName AS VehicleType,

            t.MonthlyContractID,
            mc.ContractNumber,

            c.CustomerID,
            c.CustomerName,

            t.SpaceID,
            s.SpaceCode,
            s.SpaceName,

            t.EntryDateTime,
            t.ExitDateTime,
            t.TicketStatus,

            t.EntryOperatorID,
            t.ExitOperatorID

        FROM dbo.PARKING_TICKET AS t

        INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS v
            ON v.VehicleID = t.VehicleID

        INNER JOIN dbo.PARKING_VEHICLE_TYPE AS vt
            ON vt.VehicleTypeID = v.VehicleTypeID

        INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS mc
            ON mc.ContractID = t.MonthlyContractID

        INNER JOIN dbo.PARKING_CUSTOMER AS c
            ON c.CustomerID = mc.CustomerID

        INNER JOIN dbo.PARKING_SPACE AS s
            ON s.SpaceID = t.SpaceID

        WHERE t.TicketID = @TicketID
          AND t.ParkingType = 'MONTHLY';

        RETURN;
    END;


    /* ============================================================
       ACTION 3
       MONTHLY CUSTOMER ENTRY
       ============================================================ */
    IF @ActionType = 3
    BEGIN

        IF @VehicleID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'VehicleID is required.' AS Message;
            RETURN;
        END;


        IF @MonthlyCapacityPercentage < 0
           OR @MonthlyCapacityPercentage > 100
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Monthly capacity percentage must be between 0 and 100.' AS Message;
            RETURN;
        END;


        BEGIN TRY

            BEGIN TRANSACTION;


            /* ----------------------------------------------------
               Find active monthly contract for this vehicle
               ---------------------------------------------------- */
            DECLARE @ActiveContractID INT;
            DECLARE @VehicleTypeID INT;


            SELECT
                @ActiveContractID = mc.ContractID,
                @VehicleTypeID = v.VehicleTypeID

            FROM dbo.PARKING_MONTHLY_CONTRACT AS mc WITH (UPDLOCK, HOLDLOCK)

            INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS v
                ON v.VehicleID = mc.VehicleID

            WHERE mc.VehicleID = @VehicleID
              AND mc.ContractStatus = 'ACTIVE'
              AND mc.StartDate <= CAST(GETDATE() AS DATE)
              AND mc.EndDate >= CAST(GETDATE() AS DATE)
              AND v.ActiveStatus = 1;


            IF @ActiveContractID IS NULL
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    404 AS StatusCode,
                    N'No active monthly contract was found for this vehicle.' AS Message;
                RETURN;
            END;


            /* ----------------------------------------------------
               Check whether vehicle is already inside
               ---------------------------------------------------- */
            IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_TICKET WITH (UPDLOCK, HOLDLOCK)
                WHERE VehicleID = @VehicleID
                  AND TicketStatus = 'OPEN'
            )
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    409 AS StatusCode,
                    N'This vehicle already has an open parking attendance record.' AS Message;
                RETURN;
            END;


            /* ----------------------------------------------------
               Get monthly capacity
               ---------------------------------------------------- */
            DECLARE @ActiveMonthlyContracts INT;
            DECLARE @ReservedMonthlySpaces INT;
            DECLARE @CurrentMonthlyVehicles INT;


            SELECT
                @ActiveMonthlyContracts = COUNT(*)
            FROM dbo.PARKING_MONTHLY_CONTRACT WITH (UPDLOCK, HOLDLOCK)
            WHERE ContractStatus = 'ACTIVE';


            SET @ReservedMonthlySpaces =
                CEILING(
                    @ActiveMonthlyContracts
                    * @MonthlyCapacityPercentage
                    / 100.0
                );


            SELECT
                @CurrentMonthlyVehicles = COUNT(*)
            FROM dbo.PARKING_TICKET WITH (UPDLOCK, HOLDLOCK)
            WHERE ParkingType = 'MONTHLY'
              AND TicketStatus = 'OPEN';


            /* ----------------------------------------------------
               Check monthly reserved capacity
               ---------------------------------------------------- */
            IF @CurrentMonthlyVehicles >= @ReservedMonthlySpaces
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    409 AS StatusCode,
                    N'Monthly reserved parking capacity is currently full.' AS Message,

                    @ReservedMonthlySpaces
                        AS ReservedMonthlySpaces,

                    @CurrentMonthlyVehicles
                        AS CurrentlyOccupiedMonthlySpaces;

                RETURN;
            END;


            /* ----------------------------------------------------
               Find compatible available physical space
               ---------------------------------------------------- */
            DECLARE @AvailableSpaceID INT;


            SELECT TOP 1
                @AvailableSpaceID = SpaceID

            FROM dbo.PARKING_SPACE WITH (UPDLOCK, READPAST)

            WHERE VehicleTypeID = @VehicleTypeID
              AND SpaceStatus = 'AVAILABLE'
              AND ActiveStatus = 1

            ORDER BY SpaceID;


            IF @AvailableSpaceID IS NULL
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    409 AS StatusCode,
                    N'No available parking space is currently available for this vehicle type.' AS Message;
                RETURN;
            END;


            /* ----------------------------------------------------
               Generate ticket number
               ---------------------------------------------------- */
            DECLARE @TicketNumber NVARCHAR(50);


            SET @TicketNumber =
                N'M-' +
                CONVERT(NVARCHAR(8), GETDATE(), 112) +
                N'-' +
                RIGHT(
                    N'000000' +
                    CONVERT(
                        NVARCHAR(20),
                        ISNULL(
                            (
                                SELECT MAX(TicketID) + 1
                                FROM dbo.PARKING_TICKET
                            ),
                            1
                        )
                    ),
                    6
                );


            /* ----------------------------------------------------
               Insert monthly attendance ticket
               ---------------------------------------------------- */
            INSERT INTO dbo.PARKING_TICKET
            (
                TicketNumber,
                VehicleID,
                SpaceID,
                RateID,
                MonthlyContractID,
                ParkingType,
                EntryDateTime,
                ExitDateTime,
                AppliedRate,
                BillableHours,
                CalculatedAmount,
                TicketStatus,
                EntryOperatorID
            )
            VALUES
            (
                @TicketNumber,
                @VehicleID,
                @AvailableSpaceID,
                NULL,
                @ActiveContractID,
                'MONTHLY',
                SYSUTCDATETIME(),
                NULL,
                NULL,
                NULL,
                NULL,
                'OPEN',
                @PerformedByUserID
            );


            DECLARE @NewTicketID INT =
                CONVERT(INT, SCOPE_IDENTITY());


            /* ----------------------------------------------------
               Mark space occupied
               ---------------------------------------------------- */
            UPDATE dbo.PARKING_SPACE
            SET
                SpaceStatus = 'OCCUPIED',
                UpdatedAt = SYSUTCDATETIME(),
                UpdatedBy = @PerformedByUserID
            WHERE SpaceID = @AvailableSpaceID;


            COMMIT TRANSACTION;


            SELECT
                201 AS StatusCode,
                N'Monthly customer entry recorded successfully.' AS Message,

                @NewTicketID AS TicketID,
                @TicketNumber AS TicketNumber,
                @ActiveContractID AS ContractID,
                @AvailableSpaceID AS SpaceID;

            RETURN;

        END TRY

        BEGIN CATCH

            IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;

            THROW;

        END CATCH
    END;


    /* ============================================================
       ACTION 4
       MONTHLY CUSTOMER EXIT
       ============================================================ */
    IF @ActionType = 4
    BEGIN

        IF @VehicleID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'VehicleID is required.' AS Message;
            RETURN;
        END;


        BEGIN TRY

            BEGIN TRANSACTION;


            DECLARE @OpenTicketID INT;
            DECLARE @ExitSpaceID INT;


            SELECT
                @OpenTicketID = TicketID,
                @ExitSpaceID = SpaceID

            FROM dbo.PARKING_TICKET WITH (UPDLOCK, HOLDLOCK)

            WHERE VehicleID = @VehicleID
              AND ParkingType = 'MONTHLY'
              AND TicketStatus = 'OPEN';


            IF @OpenTicketID IS NULL
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    404 AS StatusCode,
                    N'No open monthly attendance record was found for this vehicle.' AS Message;
                RETURN;
            END;


            /* ----------------------------------------------------
               Close monthly attendance
               ---------------------------------------------------- */
            UPDATE dbo.PARKING_TICKET
            SET
                ExitDateTime = SYSUTCDATETIME(),
                TicketStatus = 'CLOSED',
                ExitOperatorID = @PerformedByUserID,
                UpdatedAt = SYSUTCDATETIME(),
                UpdatedBy = @PerformedByUserID
            WHERE TicketID = @OpenTicketID;


            /* ----------------------------------------------------
               Release parking space
               ---------------------------------------------------- */
            UPDATE dbo.PARKING_SPACE
            SET
                SpaceStatus = 'AVAILABLE',
                UpdatedAt = SYSUTCDATETIME(),
                UpdatedBy = @PerformedByUserID
            WHERE SpaceID = @ExitSpaceID;


            COMMIT TRANSACTION;


            SELECT
                200 AS StatusCode,
                N'Monthly customer exit recorded successfully.' AS Message,

                @OpenTicketID AS TicketID,
                @ExitSpaceID AS SpaceID;

            RETURN;

        END TRY

        BEGIN CATCH

            IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;

            THROW;

        END CATCH
    END;


    /* ============================================================
       ACTION 5
       TODAY'S MONTHLY ATTENDANCE
       ============================================================ */
    IF @ActionType = 5
    BEGIN

        SELECT
            t.TicketID,
            t.TicketNumber,

            c.CustomerName,
            v.VehicleNumber,
            vt.TypeName AS VehicleType,

            mc.ContractNumber,

            s.SpaceCode,
            s.SpaceName,

            t.EntryDateTime,
            t.ExitDateTime,
            t.TicketStatus

        FROM dbo.PARKING_TICKET AS t

        INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS mc
            ON mc.ContractID = t.MonthlyContractID

        INNER JOIN dbo.PARKING_CUSTOMER AS c
            ON c.CustomerID = mc.CustomerID

        INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS v
            ON v.VehicleID = t.VehicleID

        INNER JOIN dbo.PARKING_VEHICLE_TYPE AS vt
            ON vt.VehicleTypeID = v.VehicleTypeID

        INNER JOIN dbo.PARKING_SPACE AS s
            ON s.SpaceID = t.SpaceID

        WHERE t.ParkingType = 'MONTHLY'
          AND CAST(t.EntryDateTime AS DATE) = CAST(GETDATE() AS DATE)

        ORDER BY
            t.EntryDateTime DESC;

        RETURN;
    END;


    /* ============================================================
       ACTION 6
       CURRENT MONTHLY CUSTOMERS INSIDE
       ============================================================ */
    IF @ActionType = 6
    BEGIN

        SELECT
            t.TicketID,
            t.TicketNumber,

            c.CustomerID,
            c.CustomerName,

            v.VehicleID,
            v.VehicleNumber,

            vt.TypeName AS VehicleType,

            mc.ContractID,
            mc.ContractNumber,

            s.SpaceID,
            s.SpaceCode,
            s.SpaceName,

            t.EntryDateTime

        FROM dbo.PARKING_TICKET AS t

        INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS mc
            ON mc.ContractID = t.MonthlyContractID

        INNER JOIN dbo.PARKING_CUSTOMER AS c
            ON c.CustomerID = mc.CustomerID

        INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS v
            ON v.VehicleID = t.VehicleID

        INNER JOIN dbo.PARKING_VEHICLE_TYPE AS vt
            ON vt.VehicleTypeID = v.VehicleTypeID

        INNER JOIN dbo.PARKING_SPACE AS s
            ON s.SpaceID = t.SpaceID

        WHERE t.ParkingType = 'MONTHLY'
          AND t.TicketStatus = 'OPEN'

        ORDER BY
            t.EntryDateTime;

        RETURN;
    END;


    /* ============================================================
       ACTION 7
       ATTENDANCE HISTORY FOR A CONTRACT
       ============================================================ */
    IF @ActionType = 7
    BEGIN

        IF @ContractID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'ContractID is required.' AS Message;
            RETURN;
        END;


        SELECT
            t.TicketID,
            t.TicketNumber,

            t.VehicleID,
            v.VehicleNumber,

            t.SpaceID,
            s.SpaceCode,
            s.SpaceName,

            t.EntryDateTime,
            t.ExitDateTime,
            t.TicketStatus

        FROM dbo.PARKING_TICKET AS t

        INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS v
            ON v.VehicleID = t.VehicleID

        INNER JOIN dbo.PARKING_SPACE AS s
            ON s.SpaceID = t.SpaceID

        WHERE t.MonthlyContractID = @ContractID
          AND t.ParkingType = 'MONTHLY'
          AND
          (
              @FromDate IS NULL
              OR CAST(t.EntryDateTime AS DATE) >= @FromDate
          )
          AND
          (
              @ToDate IS NULL
              OR CAST(t.EntryDateTime AS DATE) <= @ToDate
          )

        ORDER BY
            t.EntryDateTime DESC;

        RETURN;
    END;

END;
GO