USE [VehicleParkingManagementDB];
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Vehicle_Space
(
    @ActionType         INT,

    @SpaceID             INT = NULL,
    @VehicleTypeID       INT = NULL,
    @SpaceCode           VARCHAR(30) = NULL,
    @SpaceName           NVARCHAR(100) = NULL,
    @SpaceStatus         VARCHAR(20) = NULL,
	@PerformedByUserID  INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* Remove unnecessary spaces from supplied values. */
    SET @SpaceCode = NULLIF(LTRIM(RTRIM(@SpaceCode)), N'');
    SET @SpaceName = NULLIF(LTRIM(RTRIM(@SpaceName)), N'');
	SET @SpaceStatus = NULLIF(LTRIM(RTRIM(@SpaceStatus)), N'');

     /*
        ActionType

        1 = Get all spaces
        2 = Get by ID
        3 = Get available spaces by vehicle type
        4 = Create
        5 = Update
        6 = Block
        7 = Unblock
    */

    /* ============================================================
       ACTION 1: Get all active spaces
       ============================================================ */
	   IF @ActionType = 1
	   BEGIN
		SELECT S.SpaceID,
			   S.VehicleTypeID,
			   VT.TypeName AS VehicleTypeName,
			   S.SpaceCode,
			   S.SpaceName,
			   S.SpaceStatus,
			   S.ActiveStatus,
			   S.CreatedAt,
			   S.CreatedBy,
			   S.UpdatedAt,
			   S.UpdatedBy
		FROM dbo.PARKING_SPACE S 
		INNER JOIN dbo.PARKING_VEHICLE_TYPE VT
			ON S.VehicleTypeID = VT.VehicleTypeID
		WHERE S.ActiveStatus = 1
		ORDER BY SpaceCode;

		RETURN;
	   END

	   /* ============================================================
       ACTION 2: Get active spaces by id
       ============================================================ */
	   IF @ActionType = 2
	   BEGIN
		IF @SpaceID IS NULL
			BEGIN
				SELECT
					400 AS statusCode,
					N'Space id required' AS Message;
				RETURN;
			END

		SELECT S.SpaceID,
			   S.VehicleTypeID,
			   VT.TypeName AS VehicleTypeName,
			   S.SpaceCode,
			   S.SpaceName,
			   S.SpaceStatus,
			   S.ActiveStatus,
			   S.CreatedAt,
			   S.CreatedBy,
			   S.UpdatedAt,
			   S.UpdatedBy
		FROM dbo.PARKING_SPACE S 
		INNER JOIN dbo.PARKING_VEHICLE_TYPE VT
			ON S.VehicleTypeID = VT.VehicleTypeID
		WHERE S.SpaceID = @SpaceID
			  AND S.ActiveStatus = 1;

		RETURN;
		END



	   /* ============================================================
       ACTION 3: Get available spaces by vehicle type
       ============================================================ */

	   IF @ActionType = 3
	   BEGIN
		IF @VehicleTypeID IS NULL
			BEGIN
				SELECT
					400 AS statusCode,
					N'Vehicle Type ID required' AS Message;
				RETURN;
			END

		SELECT S.SpaceID,
			   S.VehicleTypeID,
			   VT.TypeName AS VehicleTypeName,
			   S.SpaceCode,
			   S.SpaceName,
			   S.SpaceStatus,
			   S.ActiveStatus,
			   S.CreatedAt,
			   S.CreatedBy,
			   S.UpdatedAt,
			   S.UpdatedBy
		FROM dbo.PARKING_SPACE S 
		INNER JOIN dbo.PARKING_VEHICLE_TYPE VT
			ON S.VehicleTypeID = VT.VehicleTypeID
		WHERE S.VehicleTypeID = @VehicleTypeID
			  AND S.ActiveStatus = 1
			  AND S.SpaceStatus = 'AVAILABLE'
		ORDER BY S.SpaceCode;

		RETURN;
		END
		

	   /* ============================================================
       ACTION 4: Create spaces
       ============================================================ */

	   IF @ActionType = 4
		BEGIN
			IF @VehicleTypeID IS NULL
			OR @SpaceCode IS NULL
			OR @SpaceName IS NULL
			BEGIN
				SELECT 
					400 AS statusCode,
					N'Vehicle Type, Space name or Space Code required'
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
					404 AS statusCode,
					N'Active Vehicle type not found.' AS Message;
		
				RETURN
			END;
		
			IF EXISTS
			(
				SELECT 1
				FROM dbo.PARKING_SPACE
				WHERE SpaceCode = @SpaceCode
					AND ActiveStatus = 1
			)
			BEGIN
				SELECT
					409 AS statusCode,
					N'Space code already exists.' AS Message;
				RETURN
			END;
		
			INSERT INTO dbo.PARKING_SPACE 
				(
					VehicleTypeID,
					SpaceCode,
					SpaceName,
					SpaceStatus,
					ActiveStatus,
					CreatedAt,
					CreatedBy
				)
			VALUES
				(
					@VehicleTypeID,
					@SpaceCode,
					@SpaceName,
					'AVAILABLE',
					1,
					SYSUTCDATETIME(),
					@PerformedByUserID
				)
			SELECT
				201 AS statusCode,
				N'Space created successfully' AS Message,
				CONVERT(INT, SCOPE_IDENTITY()) AS SpaceID;
			RETURN;

		END;
		

	   /* ============================================================
       ACTION 5: update spaces
       ============================================================ */
	   IF @ActionType = 5
		BEGIN
			IF @SpaceID IS NULL
			   OR @VehicleTypeID IS NULL
			   OR @SpaceCode IS NULL
			   OR @SpaceName IS NULL
			BEGIN
				SELECT
					400 AS StatusCode,
					N'Space ID, Vehicle Type ID, Space Code and Space Name are required.' AS Message;
				RETURN;
			END;

			/* Check whether space exists */
			IF NOT EXISTS
			(
				SELECT 1
				FROM dbo.PARKING_SPACE
				WHERE SpaceID = @SpaceID
				  AND ActiveStatus = 1
			)
			BEGIN
				SELECT
					404 AS StatusCode,
					N'Active parking space not found.' AS Message;
				RETURN;
			END;

			/* Check vehicle type */
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
					N'Active vehicle type not found.' AS Message;
				RETURN;
			END;

			/* Check duplicate space code */
			IF EXISTS
			(
				SELECT 1
				FROM dbo.PARKING_SPACE
				WHERE SpaceCode = @SpaceCode
				  AND SpaceID <> @SpaceID
				  AND ActiveStatus = 1
			)
			BEGIN
				SELECT
					409 AS StatusCode,
					N'Space code already exists.' AS Message;
				RETURN;
			END;

			UPDATE dbo.PARKING_SPACE
			SET
				VehicleTypeID = @VehicleTypeID,
				SpaceCode = @SpaceCode,
				SpaceName = @SpaceName,
				UpdatedAt = SYSUTCDATETIME(),
				UpdatedBy = @PerformedByUserID
			WHERE SpaceID = @SpaceID
			  AND ActiveStatus = 1;

			SELECT
				200 AS StatusCode,
				N'Parking space updated successfully.' AS Message;

			RETURN;
		END;

	   /* ============================================================
       ACTION 6: Block spaces
       ============================================================ */
	   IF @ActionType = 6
	   BEGIN
		IF @SpaceID IS NULL
		BEGIN
			SELECT 400 AS statusCode,
			N'Space ID is required.' AS Message;
			RETURN;
		END;

		IF NOT EXISTS
		(
			SELECT 1
			FROM dbo.PARKING_SPACE
			WHERE SpaceID = @SpaceID
			  AND ActiveStatus = 1
		)
		BEGIN
        SELECT
            404 AS StatusCode,
            N'Active parking space not found.' AS Message;
        RETURN;
		END;

		IF EXISTS
			(
				SELECT 1
				FROM dbo.PARKING_SPACE
				WHERE SpaceID = @SpaceID
				AND SpaceStatus = 'OCCUPIED'
				
			)
			BEGIN
				SELECT 409 AS StatusCode,
					   N'Occupied space cannot be blocked.' AS Message;
				RETURN;
			END

		UPDATE dbo.PARKING_SPACE
			SET
				SpaceStatus = 'BLOCKED',
				UpdatedAt = SYSUTCDATETIME(),
				UpdatedBy = @PerformedByUserID
			WHERE SpaceID = @SpaceID
				AND ActiveStatus=1;

			SELECT 200 AS StatusCode,
				   N'Parking space blocked successfully.' AS Message;

			RETURN;

	   END;

	   /* ============================================================
       ACTION 7: Unblock spaces
       ============================================================ */

		   IF @ActionType = 7
		   BEGIN
			IF @SpaceID IS NULL
			BEGIN
				SELECT 400 AS statusCode,
				N'Space ID is required.' AS Message;
				RETURN;
			END;


			IF NOT EXISTS
			(
			SELECT 1
			FROM dbo.PARKING_SPACE
			WHERE SpaceID = @SpaceID
				  AND ActiveStatus = 1
			)
			BEGIN
				SELECT
						404 AS StatusCode,
					N'Active parking space not found.' AS Message;
				RETURN;
			END;

		UPDATE dbo.PARKING_SPACE
			SET
				SpaceStatus = 'AVAILABLE',
				UpdatedAt = SYSUTCDATETIME(),
				UpdatedBy = @PerformedByUserID
			WHERE SpaceID = @SpaceID
				AND ActiveStatus = 1;
				AND SpaceStatus = 'BLOCKED'

			SELECT 200 AS StatusCode,
				   N'Parking space is now available.' AS Message;

			RETURN;

		END;

		SELECT 400 AS StatusCode,
           N'Invalid ActionType.' AS Message;

END;
GO