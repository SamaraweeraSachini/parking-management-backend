USE [VehicleParkingManagementDB];
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Vehicle_Type
(
    @ActionType         INT,

    @VehicleTypeID       INT = NULL,
    @TypeName            NVARCHAR(100) = NULL,
    @Description         NVARCHAR(500) = NULL,
	@PerformedByUserID   INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* Remove unnecessary spaces from supplied values. */
    SET @TypeName = NULLIF(LTRIM(RTRIM(@TypeName)), N'');
    SET @Description = NULLIF(LTRIM(RTRIM(@Description)), N'');

     /*
        ActionType

        1 = Get all active vehicle types
        2 = Get vehicle type by ID
        3 = Create
        4 = Update
        5 = Deactivate
        6 = Reactivate
    */

    /* ============================================================
       ACTION 1: Get all active vehicle types

       
       ============================================================ */
    IF @ActionType = 1
    BEGIN
        
        SELECT
            VehicleTypeID,
            TypeName,
			Description,
			ActiveStatus,
			CreatedAt,
            CreatedBy,
            UpdatedAt,
            UpdatedBy
        FROM dbo.PARKING_VEHICLE_TYPE
		WHERE ActiveStatus = 1
        ORDER BY VehicleTypeID

        RETURN;
    END;


	/* ============================================================
       ACTION 2: GET vehicle type BY ID
       ============================================================ */
    IF @ActionType = 2
    BEGIN
        IF @VehicleTypeID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'VehicleType ID is required.' AS Message;

            RETURN;
        END;

        SELECT
            VehicleTypeID,
            Description,
            ActiveStatus,
            CreatedAt,
            CreatedBy,
            UpdatedAt,
            UpdatedBy
        FROM dbo.PARKING_VEHICLE_TYPE
        WHERE VehicleTypeID = @VehicleTypeID;

        RETURN;
    END;


    /* ============================================================
       ACTION 3: CREATE Vehicle Type

       ============================================================ */
    IF @ActionType = 3
    BEGIN
        IF @TypeName IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Vehicle type name are required.'
                    AS Message;

            RETURN;
        END;


        IF EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_VEHICLE_TYPE
            WHERE TypeName = @TypeName
        )
        BEGIN
            SELECT
                409 AS StatusCode,
                N'Vehicle type already exists.' AS Message;

            RETURN;
        END;


            INSERT INTO dbo.PARKING_VEHICLE_TYPE
            (
                TypeName,
				Description,
                ActiveStatus,
                CreatedAt,
                CreatedBy
            )
            VALUES
            (
                @TypeName,
                @Description,
                1,
                SYSUTCDATETIME(),
                @PerformedByUserID
            );


            SELECT
                201 AS StatusCode,
                N'Vehicle Type created successfully.' AS Message,
                CONVERT(INT, SCOPE_IDENTITY()) AS VehicleTypeID;

            RETURN;

    END;
		
    

    

    /* ============================================================
       ACTION 4: UPDATE Vehicle Type
       ============================================================ */
    IF @ActionType = 4
    BEGIN
		IF @VehicleTypeID IS NULL OR @TypeName IS NULL
		BEGIN
			SELECT
				400 AS StatusCode,
				N'Vehicle Type ID or Type Name is required'
					AS Message;
			RETURN;
		END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_VEHICLE_TYPE
            WHERE VehicleTypeID = @VehicleTypeID
              AND ActiveStatus = 1
        )
        BEGIN
            SELECT
                404 AS StatusCode,
                N'Vehicle Type not Found.'
                    AS Message;

            RETURN;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_VEHICLE_TYPE
            WHERE TypeName = @TypeName
              AND VehicleTypeID <> @VehicleTypeID
        )
        BEGIN
            SELECT
                409 AS StatusCode,
                N'Vehicle type already exists.' AS Message;

            RETURN;
        END;

        

        UPDATE dbo.PARKING_VEHICLE_TYPE
        SET
            TypeName = @TypeName,
            Description = @Description,
            UpdatedAt = SYSUTCDATETIME(),
            UpdatedBy = @PerformedByUserID
        WHERE VehicleTypeID = @VehicleTypeID;

        SELECT
            200 AS StatusCode,
            N'Vehicle type updated successfully.' AS Message;

        RETURN;
    END;




    /* ============================================================
       ACTION 5: DEACTIVATE Vehicle Type
       ============================================================ */
    IF @ActionType = 5
    BEGIN
		IF @VehicleTypeID IS NULL
		BEGIN
            SELECT 400 AS StatusCode,
                   N'Vehicle Type ID is required.' AS Message;
            RETURN;
        END;
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_VEHICLE_TYPE
            WHERE VehicleTypeID = @VehicleTypeID
              AND ActiveStatus = 1
        )
		BEGIN
			SELECT 404 AS StatusCode,
				N'Vehicle Type not found.' AS Message;
			RETURN;
		END
        

        UPDATE dbo.PARKING_VEHICLE_TYPE
        SET
            ActiveStatus = 0,
            UpdatedAt = SYSUTCDATETIME(),
            UpdatedBy = @PerformedByUserID
        WHERE VehicleTypeID = @VehicleTypeID;

        SELECT
            200 AS StatusCode,
            N'Vehicle Type deactivated successfully.' AS Message;

        RETURN;
    END;

    /* ============================================================
       ACTION 6: REACTIVATE Vehicle type
       ============================================================ */
    IF @ActionType = 6
    BEGIN
		IF @VehicleTypeID IS NULL
        BEGIN
            SELECT
                400 AS StatusCode,
                N'Vehicle Type ID is required.' AS Message;

            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_VEHICLE_TYPE
            WHERE VehicleTypeID = @VehicleTypeID
              AND ActiveStatus = 0
        )
		BEGIN
			SELECT
					404 AS StatusCode,
				N'Inactive vehicle type not found.' AS Message;
			RETURN;
		END;

        


        UPDATE dbo.PARKING_VEHICLE_TYPE
        SET
            ActiveStatus = 1,
            UpdatedAt = SYSUTCDATETIME(),
            UpdatedBy = @PerformedByUserID
        WHERE VehicleTypeID = @VehicleTypeID;


        SELECT
            200 AS StatusCode,
            N'Vehicle type reactivated successfully.' AS Message;

        RETURN;

		END;

		/* ============================================================
       INVALID ACTION TYPE
       ============================================================ */
		
		SELECT 400 AS StatusCode,
           N'Invalid ActionType.' AS Message;
END;
GO