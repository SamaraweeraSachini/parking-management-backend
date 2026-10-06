USE [VehicleParkingManagementDB];
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Monthly_Contract
(
    @ActionType                  INT,

    @ContractID                  INT = NULL,
    @ContractNumber              NVARCHAR(50) = NULL,
    @CustomerID                  INT = NULL,
    @VehicleID                   INT = NULL,
    @MonthlyFee                  DECIMAL(12,2) = NULL,
    @StartDate                   DATE = NULL,
    @EndDate                     DATE = NULL,
    @ContractStatus              VARCHAR(20) = NULL,
    @CancelledReason             NVARCHAR(500) = NULL,

    @PerformedByUserID           INT = NULL,

    -- Percentage of active monthly contracts reserved for monthly parking
    @MonthlyCapacityPercentage   DECIMAL(5,2) = 30.00,

    @IncludeInactive             BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @ContractNumber = NULLIF(LTRIM(RTRIM(@ContractNumber)), N'');
    SET @CancelledReason = NULLIF(LTRIM(RTRIM(@CancelledReason)), N'');


	/*
        ActionType values:
		
			1	List monthly attendance
			2	Get one attendance record
			3	Monthly customer entry
			4	Monthly customer exit
			5	Today's monthly attendance
			6	Monthly customers currently inside
			7	Attendance history for a contract

*/
    /* ============================================================
       ACTION 1
       LIST MONTHLY CONTRACTS
       ============================================================ */
    IF @ActionType = 1
    BEGIN
        SELECT
            c.ContractID,
            c.ContractNumber,
            c.CustomerID,
            cu.CustomerName,

            c.VehicleID,
            v.VehicleNumber,
            vt.TypeName AS VehicleType,

            c.MonthlyFee,
            c.StartDate,
            c.EndDate,
            c.ContractStatus,
            c.CancelledAt,
            c.CancelledReason,

            c.CreatedAt,
            c.CreatedBy,
            c.UpdatedAt,
            c.UpdatedBy

        FROM dbo.PARKING_MONTHLY_CONTRACT AS c

        INNER JOIN dbo.PARKING_CUSTOMER AS cu
            ON cu.CustomerID = c.CustomerID

        INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS v
            ON v.VehicleID = c.VehicleID

        INNER JOIN dbo.PARKING_VEHICLE_TYPE AS vt
            ON vt.VehicleTypeID = v.VehicleTypeID

        WHERE
            @IncludeInactive = 1
            OR c.ContractStatus = 'ACTIVE'

        ORDER BY
            c.ContractID DESC;

        RETURN;
    END;


    /* ============================================================
       ACTION 2
       GET CONTRACT BY ID
       ============================================================ */
    IF @ActionType = 2
    BEGIN
        IF @ContractID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'ContractID is required.' AS Message;
            RETURN;
        END;

        SELECT
            c.ContractID,
            c.ContractNumber,
            c.CustomerID,
            cu.CustomerName,

            c.VehicleID,
            v.VehicleNumber,
            v.VehicleTypeID,
            vt.TypeName AS VehicleType,

            c.MonthlyFee,
            c.StartDate,
            c.EndDate,
            c.ContractStatus,
            c.CancelledAt,
            c.CancelledReason,

            c.CreatedAt,
            c.CreatedBy,
            c.UpdatedAt,
            c.UpdatedBy

        FROM dbo.PARKING_MONTHLY_CONTRACT AS c

        INNER JOIN dbo.PARKING_CUSTOMER AS cu
            ON cu.CustomerID = c.CustomerID

        INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS v
            ON v.VehicleID = c.VehicleID

        INNER JOIN dbo.PARKING_VEHICLE_TYPE AS vt
            ON vt.VehicleTypeID = v.VehicleTypeID

        WHERE c.ContractID = @ContractID;

        RETURN;
    END;


    /* ============================================================
       ADMIN VALIDATION
       CREATE / UPDATE / CANCEL / EXPIRE
       ============================================================ */
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.PARKING_USER
        WHERE UserID = @PerformedByUserID
          AND UserRole = 'A'
          AND ActiveStatus = 1
    )
    BEGIN
        SELECT
            403 AS StatusCode,
            N'An active administrator is required.' AS Message;
        RETURN;
    END;


    /* ============================================================
       ACTION 3 / 4
       CREATE / UPDATE VALIDATION
       ============================================================ */
    IF @ActionType IN (3,4)
    BEGIN
        IF @CustomerID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'CustomerID is required.' AS Message;
            RETURN;
        END;

        IF @VehicleID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'VehicleID is required.' AS Message;
            RETURN;
        END;

        IF @MonthlyFee IS NULL OR @MonthlyFee < 0
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Valid MonthlyFee is required.' AS Message;
            RETURN;
        END;

        IF @StartDate IS NULL OR @EndDate IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'StartDate and EndDate are required.' AS Message;
            RETURN;
        END;

        IF @EndDate < @StartDate
        BEGIN
            SELECT
                400 AS StatusCode,
                N'EndDate cannot be before StartDate.' AS Message;
            RETURN;
        END;


        /* Customer validation */
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_CUSTOMER
            WHERE CustomerID = @CustomerID
              AND ActiveStatus = 1
        )
        BEGIN
            SELECT
                404 AS StatusCode,
                N'Active customer not found.' AS Message;
            RETURN;
        END;


        /* Vehicle validation */
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_CUSTOMER_VEHICLE
            WHERE VehicleID = @VehicleID
              AND CustomerID = @CustomerID
              AND ActiveStatus = 1
        )
        BEGIN
            SELECT
                404 AS StatusCode,
                N'Active vehicle does not belong to the selected customer.' AS Message;
            RETURN;
        END;
    END;


    BEGIN TRY

        BEGIN TRANSACTION;


        /* ========================================================
           ACTION 3
           CREATE MONTHLY CONTRACT
           ======================================================== */
        IF @ActionType = 3
        BEGIN
            /* --------------------------------------------
               Check vehicle does not already have
               an active monthly contract
               -------------------------------------------- */
            IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_MONTHLY_CONTRACT WITH (UPDLOCK, HOLDLOCK)
                WHERE VehicleID = @VehicleID
                  AND ContractStatus = 'ACTIVE'
                  AND EndDate >= CAST(GETDATE() AS DATE)
            )
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    409 AS StatusCode,
                    N'This vehicle already has an active monthly contract.' AS Message;
                RETURN;
            END;


            /* --------------------------------------------
               Count physical parking spaces
               -------------------------------------------- */
            DECLARE @TotalSpaces INT;
            DECLARE @ActiveMonthlyContracts INT;

            SELECT
                @TotalSpaces = COUNT(*)
            FROM dbo.PARKING_SPACE WITH (UPDLOCK, HOLDLOCK)
            WHERE ActiveStatus = 1;


            /* --------------------------------------------
               Count currently active monthly contracts
               -------------------------------------------- */
            SELECT
                @ActiveMonthlyContracts = COUNT(*)
            FROM dbo.PARKING_MONTHLY_CONTRACT WITH (UPDLOCK, HOLDLOCK)
            WHERE ContractStatus = 'ACTIVE';


            /* --------------------------------------------
               Monthly contracts cannot exceed
               physical parking spaces
               -------------------------------------------- */
            IF @ActiveMonthlyContracts + 1 > @TotalSpaces
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    409 AS StatusCode,
                    N'Cannot create monthly contract. Active monthly contracts cannot exceed total physical parking spaces.' AS Message,
                    @TotalSpaces AS TotalParkingSpaces,
                    @ActiveMonthlyContracts AS CurrentMonthlyContracts;
                RETURN;
            END;


            /* --------------------------------------------
               Generate contract number
               -------------------------------------------- */
            IF @ContractNumber IS NULL
            BEGIN
                SET @ContractNumber =
                    N'MC-' +
                    CONVERT(NVARCHAR(8), GETDATE(), 112) +
                    N'-' +
                    RIGHT(
                        N'000000' +
                        CONVERT(NVARCHAR(20),
                            ISNULL(
                                (
                                    SELECT MAX(ContractID) + 1
                                    FROM dbo.PARKING_MONTHLY_CONTRACT
                                ),
                                1
                            )
                        ),
                        6
                    );
            END;


            /* --------------------------------------------
               Check contract number uniqueness
               -------------------------------------------- */
            IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_MONTHLY_CONTRACT
                WHERE ContractNumber = @ContractNumber
            )
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    409 AS StatusCode,
                    N'Contract number already exists.' AS Message;
                RETURN;
            END;


            /* --------------------------------------------
               Insert contract
               -------------------------------------------- */
            INSERT INTO dbo.PARKING_MONTHLY_CONTRACT
            (
                ContractNumber,
                CustomerID,
                VehicleID,
                MonthlyFee,
                StartDate,
                EndDate,
                ContractStatus,
                CreatedAt,
                CreatedBy
            )
            VALUES
            (
                @ContractNumber,
                @CustomerID,
                @VehicleID,
                @MonthlyFee,
                @StartDate,
                @EndDate,
                'ACTIVE',
                SYSUTCDATETIME(),
                @PerformedByUserID
            );


            DECLARE @NewContractID INT =
                CONVERT(INT, SCOPE_IDENTITY());


            COMMIT TRANSACTION;


            SELECT
                201 AS StatusCode,
                N'Monthly contract created successfully.' AS Message,
                @NewContractID AS ContractID,
                @ContractNumber AS ContractNumber;

            RETURN;
        END;


        /* ========================================================
           ACTION 4
           UPDATE MONTHLY CONTRACT
           ======================================================== */
        IF @ActionType = 4
        BEGIN
            IF @ContractID IS NULL
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    400 AS StatusCode,
                    N'ContractID is required.' AS Message;
                RETURN;
            END;


            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_MONTHLY_CONTRACT WITH (UPDLOCK, HOLDLOCK)
                WHERE ContractID = @ContractID
            )
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    404 AS StatusCode,
                    N'Monthly contract not found.' AS Message;
                RETURN;
            END;


            UPDATE dbo.PARKING_MONTHLY_CONTRACT
            SET
                CustomerID = @CustomerID,
                VehicleID = @VehicleID,
                MonthlyFee = @MonthlyFee,
                StartDate = @StartDate,
                EndDate = @EndDate,
                UpdatedAt = SYSUTCDATETIME(),
                UpdatedBy = @PerformedByUserID
            WHERE ContractID = @ContractID;


            COMMIT TRANSACTION;


            SELECT
                200 AS StatusCode,
                N'Monthly contract updated successfully.' AS Message;

            RETURN;
        END;


        /* ========================================================
           ACTION 5
           CANCEL MONTHLY CONTRACT
           ======================================================== */
        IF @ActionType = 5
        BEGIN
            IF @ContractID IS NULL
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    400 AS StatusCode,
                    N'ContractID is required.' AS Message;
                RETURN;
            END;


            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_MONTHLY_CONTRACT WITH (UPDLOCK, HOLDLOCK)
                WHERE ContractID = @ContractID
            )
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    404 AS StatusCode,
                    N'Monthly contract not found.' AS Message;
                RETURN;
            END;


            UPDATE dbo.PARKING_MONTHLY_CONTRACT
            SET
                ContractStatus = 'CANCELLED',
                CancelledAt = SYSUTCDATETIME(),
                CancelledReason = @CancelledReason,
                UpdatedAt = SYSUTCDATETIME(),
                UpdatedBy = @PerformedByUserID
            WHERE ContractID = @ContractID
              AND ContractStatus = 'ACTIVE';


            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    409 AS StatusCode,
                    N'Contract is not currently active.' AS Message;
                RETURN;
            END;


            COMMIT TRANSACTION;


            SELECT
                200 AS StatusCode,
                N'Monthly contract cancelled successfully.' AS Message;

            RETURN;
        END;


        /* ========================================================
           ACTION 6
           EXPIRE OLD CONTRACTS
           ======================================================== */
        IF @ActionType = 6
        BEGIN
            UPDATE dbo.PARKING_MONTHLY_CONTRACT
            SET
                ContractStatus = 'EXPIRED',
                UpdatedAt = SYSUTCDATETIME(),
                UpdatedBy = @PerformedByUserID
            WHERE ContractStatus = 'ACTIVE'
              AND EndDate < CAST(GETDATE() AS DATE);


            DECLARE @ExpiredCount INT = @@ROWCOUNT;


            COMMIT TRANSACTION;


            SELECT
                200 AS StatusCode,
                N'Expired monthly contracts updated successfully.' AS Message,
                @ExpiredCount AS ExpiredContracts;

            RETURN;
        END;


        /* ========================================================
           ACTION 7
           MONTHLY CAPACITY INFORMATION
           
           Reserved capacity =
           CEILING(active monthly contracts *
                   percentage / 100)
           ======================================================== */
        IF @ActionType = 7
        BEGIN
            IF @MonthlyCapacityPercentage < 0
               OR @MonthlyCapacityPercentage > 100
            BEGIN
                ROLLBACK TRANSACTION;

                SELECT
                    400 AS StatusCode,
                    N'Monthly capacity percentage must be between 0 and 100.' AS Message;
                RETURN;
            END;


            DECLARE @CapacityTotalSpaces INT;
            DECLARE @CapacityMonthlyContracts INT;
            DECLARE @ReservedMonthlySpaces INT;
            DECLARE @CurrentlyOccupiedMonthly INT;
            DECLARE @AvailableMonthlyCapacity INT;


            SELECT
                @CapacityTotalSpaces = COUNT(*)
            FROM dbo.PARKING_SPACE
            WHERE ActiveStatus = 1;


            SELECT
                @CapacityMonthlyContracts = COUNT(*)
            FROM dbo.PARKING_MONTHLY_CONTRACT
            WHERE ContractStatus = 'ACTIVE';


            SET @ReservedMonthlySpaces =
                CEILING(
                    @CapacityMonthlyContracts
                    * @MonthlyCapacityPercentage
                    / 100.0
                );


            SELECT
                @CurrentlyOccupiedMonthly = COUNT(*)
            FROM dbo.PARKING_TICKET
            WHERE ParkingType = 'MONTHLY'
              AND TicketStatus = 'OPEN';


            SET @AvailableMonthlyCapacity =
                @ReservedMonthlySpaces
                - @CurrentlyOccupiedMonthly;


            IF @AvailableMonthlyCapacity < 0
                SET @AvailableMonthlyCapacity = 0;


            COMMIT TRANSACTION;


            SELECT
                200 AS StatusCode,
                N'Monthly parking capacity retrieved successfully.' AS Message,

                @CapacityTotalSpaces
                    AS TotalPhysicalSpaces,

                @CapacityMonthlyContracts
                    AS ActiveMonthlyContracts,

                @MonthlyCapacityPercentage
                    AS MonthlyCapacityPercentage,

                @ReservedMonthlySpaces
                    AS ReservedMonthlySpaces,

                @CurrentlyOccupiedMonthly
                    AS CurrentlyOccupiedMonthlyVehicles,

                @AvailableMonthlyCapacity
                    AS AvailableMonthlyCapacity;

            RETURN;
        END;


        ROLLBACK TRANSACTION;

        SELECT
            400 AS StatusCode,
            N'Unsupported action.' AS Message;

    END TRY

    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;

    END CATCH
END;
GO