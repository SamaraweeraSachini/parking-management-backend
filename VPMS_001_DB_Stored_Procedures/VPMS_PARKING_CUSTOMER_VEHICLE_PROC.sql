USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_PARKING_CUSTOMER_VEHICLE_PROC
    @ActionType INT,

    @p_vehicleID VARCHAR(10) = NULL,
    @p_customerID INT = NULL,
    @p_vehicleTypeID VARCHAR(10) = NULL,
    @p_vehicleNumber VARCHAR(30) = NULL,
    @p_vehicleMake VARCHAR(100) = NULL,
    @p_vehicleModel VARCHAR(100) = NULL,
    @p_vehicleColour VARCHAR(50) = NULL,
    @p_isActive CHAR(1) = NULL,
    @p_searchTerm VARCHAR(200) = NULL,
    @p_includeInactive BIT = 0,
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

        SET @p_vehicleID = NULLIF(LTRIM(RTRIM(@p_vehicleID)), '');
        SET @p_vehicleTypeID = NULLIF(LTRIM(RTRIM(@p_vehicleTypeID)), '');
        SET @p_vehicleNumber = UPPER(NULLIF(LTRIM(RTRIM(@p_vehicleNumber)), ''));
        SET @p_vehicleMake = NULLIF(LTRIM(RTRIM(@p_vehicleMake)), '');
        SET @p_vehicleModel = NULLIF(LTRIM(RTRIM(@p_vehicleModel)), '');
        SET @p_vehicleColour = NULLIF(LTRIM(RTRIM(@p_vehicleColour)), '');
        SET @p_searchTerm = NULLIF(LTRIM(RTRIM(@p_searchTerm)), N'');

        /** 1. Get vehicles **/
        IF @ActionType = 1
        BEGIN
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
                V.VPV_VEHICLE_ID,
                V.VPV_CUSTOMER_ID,
                C.VPC_CUSTOMER_NAME,
                C.VPC_MOBILE_NUMBER,
                V.VPV_VEHICLE_TYPE_ID,
                VT.VVT_TYPE_NAME,
                VT.VVT_WHEEL_COUNT,
                V.VPV_VEHICLE_NUMBER,
                V.VPV_VEHICLE_MAKE,
                V.VPV_VEHICLE_MODEL,
                V.VPV_VEHICLE_COLOR,
                V.VPV_IS_ACTIVE
            FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = V.VPV_VEHICLE_TYPE_ID
            LEFT JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = V.VPV_CUSTOMER_ID
            WHERE (ISNULL(@p_includeInactive, 0) = 1 OR V.VPV_IS_ACTIVE = 'A')
              AND (@p_customerID IS NULL
                   OR V.VPV_CUSTOMER_ID = @p_customerID)
              AND (@p_vehicleTypeID IS NULL
                   OR V.VPV_VEHICLE_TYPE_ID = @p_vehicleTypeID)
              AND
              (
                  @p_searchTerm IS NULL
                  OR CHARINDEX(@p_searchTerm, V.VPV_VEHICLE_NUMBER) > 0
                  OR CHARINDEX(@p_searchTerm, C.VPC_CUSTOMER_NAME) > 0
                  OR CHARINDEX(@p_searchTerm, C.VPC_MOBILE_NUMBER) > 0
              )
            ORDER BY V.VPV_VEHICLE_NUMBER, V.VPV_VEHICLE_ID;

            SET @Result = 'Vehicle list retrieved successfully';
        END

        /** 2. Get vehicle by ID **/
        ELSE IF @ActionType = 2
        BEGIN
            IF @p_vehicleID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle ID is required';
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
                V.VPV_VEHICLE_ID,
                V.VPV_CUSTOMER_ID,
                C.VPC_CUSTOMER_NAME,
                C.VPC_MOBILE_NUMBER,
                V.VPV_VEHICLE_TYPE_ID,
                VT.VVT_TYPE_NAME,
                VT.VVT_WHEEL_COUNT,
                V.VPV_VEHICLE_NUMBER,
                V.VPV_VEHICLE_MAKE,
                V.VPV_VEHICLE_MODEL,
                V.VPV_VEHICLE_COLOR,
                V.VPV_IS_ACTIVE
            FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = V.VPV_VEHICLE_TYPE_ID
            LEFT JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = V.VPV_CUSTOMER_ID
            WHERE V.VPV_VEHICLE_ID = @p_vehicleID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle was not found';
                RETURN;
            END;

            SET @Result = 'Vehicle retrieved successfully';
        END

        /** 3. Add vehicle **/
        ELSE IF @ActionType = 3
        BEGIN
            IF @p_vehicleID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle ID is required';
                RETURN;
            END;

            IF @p_vehicleNumber IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle number is required';
                RETURN;
            END;

            IF @p_vehicleTypeID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type ID is required';
                RETURN;
            END;

            IF @p_isActive IS NOT NULL
               AND @p_isActive NOT IN ('A', 'I')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Status is required : A - Active / I - Inactive';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_USER
                WHERE VPU_USER_ID = @p_uid
                  AND VPU_USER_ROLE IN ('AD', 'OP')
                  AND VPU_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator or operator is required';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE
                WHERE VPV_VEHICLE_ID = @p_vehicleID
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle ID already exists';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE
                WHERE VPV_VEHICLE_NUMBER = @p_vehicleNumber
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle number already exists';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_VEHICLE_TYPE
                WHERE VVT_VEHICLE_TYPE_ID = @p_vehicleTypeID
                  AND VVT_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Active vehicle type was not found';
                RETURN;
            END;

            IF @p_customerID IS NOT NULL
            BEGIN
                IF NOT EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_CUSTOMER
                    WHERE VPC_CUSTOMER_ID = @p_customerID
                      AND VPC_IS_ACTIVE = 'A'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Active customer was not found';
                    RETURN;
                END;
            END;

            INSERT INTO dbo.VPMS_PARKINGCUSTOMER_VEHICLE
            (
                VPV_VEHICLE_ID,
                VPV_CUSTOMER_ID,
                VPV_VEHICLE_TYPE_ID,
                VPV_VEHICLE_NUMBER,
                VPV_VEHICLE_MAKE,
                VPV_VEHICLE_MODEL,
                VPV_VEHICLE_COLOR,
                VPV_IS_ACTIVE,
                VPV_CREATED_BY,
                VPV_CREATED_DATE
            )
            VALUES
            (
                @p_vehicleID,
                @p_customerID,
                @p_vehicleTypeID,
                @p_vehicleNumber,
                @p_vehicleMake,
                @p_vehicleModel,
                @p_vehicleColour,
                ISNULL(@p_isActive, 'A'),
                @p_uid,
                SYSUTCDATETIME()
            );

            SET @Result = 'Vehicle added successfully';
            SELECT @p_vehicleID AS VPV_VEHICLE_ID;
        END

        /** 4. Update vehicle **/
        ELSE IF @ActionType = 4
        BEGIN
            IF @p_vehicleID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle ID is required';
                RETURN;
            END;

            IF @p_vehicleNumber IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle number is required';
                RETURN;
            END;

            IF @p_vehicleTypeID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type ID is required';
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

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE
                WHERE VPV_VEHICLE_ID = @p_vehicleID
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle was not found';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE
                WHERE VPV_VEHICLE_ID = @p_vehicleID
                  AND
                  (
                      VPV_VEHICLE_TYPE_ID <> @p_vehicleTypeID
                      OR VPV_VEHICLE_NUMBER <> @p_vehicleNumber
                      OR ISNULL(VPV_CUSTOMER_ID, 0) <> ISNULL(@p_customerID, 0)
                  )
            )
            BEGIN
                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_TICKET
                    WHERE VPT_VEHICLE_ID = @p_vehicleID
                      AND VPT_EXIT_DATE_TIME IS NULL
                      AND VPT_TICKET_STATUS <> 'CN'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Cannot change vehicle number, type or customer while the vehicle is parked';
                    RETURN;
                END;

                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
                    WHERE VPM_VEHICLE_ID = @p_vehicleID
                      AND VPM_CONTRACT_STATUS = 'A'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Resolve the active monthly contract before changing vehicle number, type or customer';
                    RETURN;
                END;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE
                WHERE VPV_VEHICLE_ID = @p_vehicleID
                  AND
                  (
                      VPV_VEHICLE_TYPE_ID <> @p_vehicleTypeID
                      OR VPV_VEHICLE_NUMBER <> @p_vehicleNumber
                  )
            )
            BEGIN
                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_TICKET
                    WHERE VPT_VEHICLE_ID = @p_vehicleID
                )
                OR EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
                    WHERE VPM_VEHICLE_ID = @p_vehicleID
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'A vehicle with active parking or contract history cannot change its number or type';
                    RETURN;
                END;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE
                WHERE VPV_VEHICLE_NUMBER = @p_vehicleNumber
                  AND VPV_VEHICLE_ID <> @p_vehicleID
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle number already exists';
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_VEHICLE_TYPE
                WHERE VVT_VEHICLE_TYPE_ID = @p_vehicleTypeID
                  AND VVT_IS_ACTIVE = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Active vehicle type was not found';
                RETURN;
            END;

            IF @p_customerID IS NOT NULL
            BEGIN
                IF NOT EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_CUSTOMER
                    WHERE VPC_CUSTOMER_ID = @p_customerID
                      AND VPC_IS_ACTIVE = 'A'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Active customer was not found';
                    RETURN;
                END;
            END;

            UPDATE dbo.VPMS_PARKINGCUSTOMER_VEHICLE
            SET VPV_CUSTOMER_ID = @p_customerID,
                VPV_VEHICLE_TYPE_ID = @p_vehicleTypeID,
                VPV_VEHICLE_NUMBER = @p_vehicleNumber,
                VPV_VEHICLE_MAKE = @p_vehicleMake,
                VPV_VEHICLE_MODEL = @p_vehicleModel,
                VPV_VEHICLE_COLOR = @p_vehicleColour,
                VPV_UPDATED_BY = @p_uid,
                VPV_UPDATED_DATE = SYSUTCDATETIME()
            WHERE VPV_VEHICLE_ID = @p_vehicleID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle was not found';
                RETURN;
            END;

            SET @Result = 'Vehicle updated successfully';
        END

        /** 5. Activate or deactivate vehicle **/
        ELSE IF @ActionType = 5
        BEGIN
            IF @p_vehicleID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle ID is required';
                RETURN;
            END;

            IF @p_isActive IS NULL
               OR @p_isActive NOT IN ('A', 'I')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Status A or I is required';
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

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE
                WHERE VPV_VEHICLE_ID = @p_vehicleID
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle was not found';
                RETURN;
            END;

            IF @p_isActive = 'I'
            BEGIN
                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_TICKET
                    WHERE VPT_VEHICLE_ID = @p_vehicleID
                      AND VPT_EXIT_DATE_TIME IS NULL
                      AND VPT_TICKET_STATUS <> 'CN'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Cannot deactivate a vehicle while it is parked';
                    RETURN;
                END;

                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
                    WHERE VPM_VEHICLE_ID = @p_vehicleID
                      AND VPM_CONTRACT_STATUS = 'A'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Resolve the active monthly contract before deactivating this vehicle';
                    RETURN;
                END;
            END;

            IF @p_isActive = 'A'
            BEGIN
                IF NOT EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                    INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                        ON VT.VVT_VEHICLE_TYPE_ID = V.VPV_VEHICLE_TYPE_ID
                    WHERE V.VPV_VEHICLE_ID = @p_vehicleID
                      AND VT.VVT_IS_ACTIVE = 'A'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Activate the vehicle type before activating this vehicle';
                    RETURN;
                END;

                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                    INNER JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                        ON C.VPC_CUSTOMER_ID = V.VPV_CUSTOMER_ID
                    WHERE V.VPV_VEHICLE_ID = @p_vehicleID
                      AND C.VPC_IS_ACTIVE = 'I'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Activate the customer before activating this vehicle';
                    RETURN;
                END;
            END;

            UPDATE dbo.VPMS_PARKINGCUSTOMER_VEHICLE
            SET VPV_IS_ACTIVE = @p_isActive,
                VPV_UPDATED_BY = @p_uid,
                VPV_UPDATED_DATE = SYSUTCDATETIME()
            WHERE VPV_VEHICLE_ID = @p_vehicleID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle was not found';
                RETURN;
            END;

            SET @Result = 'Vehicle status updated successfully';
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