USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_PARKING_SPACE_PROC
    @ActionType INT,

    @p_spaceID VARCHAR(10) = NULL,
    @p_vehicleTypeID VARCHAR(10) = NULL,
    @p_spaceCode VARCHAR(30) = NULL,
    @p_spaceName VARCHAR(100) = NULL,
    @p_spaceStatus VARCHAR(20) = NULL,
    @p_blockReason VARCHAR(500) = NULL,
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

        SET @p_spaceID = NULLIF(LTRIM(RTRIM(@p_spaceID)), '');
        SET @p_vehicleTypeID = NULLIF(LTRIM(RTRIM(@p_vehicleTypeID)), '');
        SET @p_spaceCode = UPPER(NULLIF(LTRIM(RTRIM(@p_spaceCode)), ''));
        SET @p_spaceName = NULLIF(LTRIM(RTRIM(@p_spaceName)), '');
        SET @p_spaceStatus = UPPER(NULLIF(LTRIM(RTRIM(@p_spaceStatus)), ''));
        SET @p_blockReason = NULLIF(LTRIM(RTRIM(@p_blockReason)), '');

        /** 1. Get parking spaces **/
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
                S.VPS_SPACE_ID,
                S.VPS_VEHICLE_TYPE_ID,
                VT.VVT_TYPE_NAME,
                VT.VVT_WHEEL_COUNT,
                S.VPS_SPACE_CODE,
                S.VPS_SPACE_NAME,
                S.VPS_SPACE_STATUS,
                S.VPS_BLOCK_REASON
            FROM dbo.VPMS_PARKING_SPACE AS S
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = S.VPS_VEHICLE_TYPE_ID
            WHERE (@p_vehicleTypeID IS NULL
                   OR S.VPS_VEHICLE_TYPE_ID = @p_vehicleTypeID)
              AND (@p_spaceStatus IS NULL
                   OR S.VPS_SPACE_STATUS = @p_spaceStatus)
            ORDER BY S.VPS_SPACE_CODE, S.VPS_SPACE_ID;

            SET @Result = 'Parking space list retrieved successfully';
        END

        /** 2. Get parking space by ID **/
        ELSE IF @ActionType = 2
        BEGIN
            IF @p_spaceID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space ID is required';
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
                S.VPS_SPACE_ID,
                S.VPS_VEHICLE_TYPE_ID,
                VT.VVT_TYPE_NAME,
                VT.VVT_WHEEL_COUNT,
                S.VPS_SPACE_CODE,
                S.VPS_SPACE_NAME,
                S.VPS_SPACE_STATUS,
                S.VPS_BLOCK_REASON
            FROM dbo.VPMS_PARKING_SPACE AS S
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = S.VPS_VEHICLE_TYPE_ID
            WHERE S.VPS_SPACE_ID = @p_spaceID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space was not found';
                RETURN;
            END;

            SET @Result = 'Parking space retrieved successfully';
        END

        /** 3. Add parking space **/
        ELSE IF @ActionType = 3
        BEGIN
            IF @p_spaceID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space ID is required';
                RETURN;
            END;

            IF @p_spaceCode IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space code is required';
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

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_SPACE
                WHERE VPS_SPACE_ID = @p_spaceID
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space ID already exists';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_SPACE
                WHERE VPS_SPACE_CODE = @p_spaceCode
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space code already exists';
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

            INSERT INTO dbo.VPMS_PARKING_SPACE
            (
                VPS_SPACE_ID,
                VPS_VEHICLE_TYPE_ID,
                VPS_SPACE_CODE,
                VPS_SPACE_NAME,
                VPS_SPACE_STATUS,
                VPS_CREATED_BY,
                VPS_CREATED_DATE
            )
            VALUES
            (
                @p_spaceID,
                @p_vehicleTypeID,
                @p_spaceCode,
                @p_spaceName,
                'AV',
                @p_uid,
                SYSUTCDATETIME()
            );

            SET @Result = 'Parking space added successfully';
            SELECT @p_spaceID AS VPS_SPACE_ID;
        END

        /** 4. Update parking space **/
        ELSE IF @ActionType = 4
        BEGIN
            IF @p_spaceID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space ID is required';
                RETURN;
            END;

            IF @p_spaceCode IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space code is required';
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
                FROM dbo.VPMS_PARKING_SPACE
                WHERE VPS_SPACE_ID = @p_spaceID
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space was not found';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_TICKET
                WHERE VPT_SPACE_ID = @p_spaceID
                  AND VPT_EXIT_DATE_TIME IS NULL
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An open parking ticket uses this space';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_SPACE
                WHERE VPS_SPACE_ID = @p_spaceID
                  AND VPS_SPACE_STATUS NOT IN ('AV', 'B')
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Only available or blocked spaces can be edited';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_MONTHLY_RESERVATION AS R
                INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                    ON MP.VPP_MONTHLY_PAYMENT_ID = R.VPR_MONTHLY_PAYMENT_ID
                INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                    ON MC.VPM_CONTRACT_ID = MP.VPP_CONTRACT_ID
                WHERE R.VPR_SPACE_ID = @p_spaceID
                  AND R.VPR_IS_ACTIVE = 'A'
                  AND R.VPR_EFFECTIVE_TO_UTC > SYSUTCDATETIME()
                  AND MP.VPP_PAYMENT_STATUS = 'C'
                  AND MC.VPM_CONTRACT_STATUS = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A current or future paid monthly reservation uses this space';
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

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_SPACE
                WHERE VPS_SPACE_CODE = @p_spaceCode
                  AND VPS_SPACE_ID <> @p_spaceID
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space code already exists';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_SPACE
                WHERE VPS_SPACE_ID = @p_spaceID
                  AND VPS_VEHICLE_TYPE_ID <> @p_vehicleTypeID
            )
            BEGIN
                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_TICKET
                    WHERE VPT_SPACE_ID = @p_spaceID
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'A space with parking history cannot change its vehicle type';
                    RETURN;
                END;
            END;

            UPDATE dbo.VPMS_PARKING_SPACE
				SET VPS_VEHICLE_TYPE_ID = @p_vehicleTypeID,
					VPS_SPACE_CODE = @p_spaceCode,
					VPS_SPACE_NAME = @p_spaceName,
					VPS_UPDATED_BY = @p_uid,
					VPS_UPDATED_DATE = SYSUTCDATETIME()
				WHERE VPS_SPACE_ID = @p_spaceID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space was not found';
                RETURN;
            END;

            SET @Result = 'Parking space updated successfully';
        END

        /** 5. Block or unblock parking space **/
        ELSE IF @ActionType = 5
        BEGIN
            IF @p_spaceID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space ID is required';
                RETURN;
            END;

            IF @p_spaceStatus IS NULL
               OR @p_spaceStatus NOT IN ('AV', 'B')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Manual status must be AV - Available / B - Blocked';
                RETURN;
            END;

            IF @p_spaceStatus = 'B' AND @p_blockReason IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A block reason is required';
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
                FROM dbo.VPMS_PARKING_SPACE
                WHERE VPS_SPACE_ID = @p_spaceID
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space was not found';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_TICKET
                WHERE VPT_SPACE_ID = @p_spaceID
                  AND VPT_EXIT_DATE_TIME IS NULL
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An open parking ticket uses this space';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_SPACE
                WHERE VPS_SPACE_ID = @p_spaceID
                  AND VPS_SPACE_STATUS NOT IN ('AV', 'B')
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Only available or blocked spaces can be manually changed';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_MONTHLY_RESERVATION AS R
                INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                    ON MP.VPP_MONTHLY_PAYMENT_ID = R.VPR_MONTHLY_PAYMENT_ID
                INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                    ON MC.VPM_CONTRACT_ID = MP.VPP_CONTRACT_ID
                WHERE R.VPR_SPACE_ID = @p_spaceID
                  AND R.VPR_IS_ACTIVE = 'A'
                  AND R.VPR_EFFECTIVE_TO_UTC > SYSUTCDATETIME()
                  AND MP.VPP_PAYMENT_STATUS = 'C'
                  AND MC.VPM_CONTRACT_STATUS = 'A'
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A current or future paid monthly reservation uses this space';
                RETURN;
            END;

            IF @p_spaceStatus = 'AV'
            BEGIN
                IF NOT EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_SPACE AS S
                    INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                        ON VT.VVT_VEHICLE_TYPE_ID = S.VPS_VEHICLE_TYPE_ID
                    WHERE S.VPS_SPACE_ID = @p_spaceID
                      AND VT.VVT_IS_ACTIVE = 'A'
                )
                BEGIN
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Activate the vehicle type before making this space available';
                    RETURN;
                END;
            END;

            UPDATE dbo.VPMS_PARKING_SPACE
            SET VPS_SPACE_STATUS = @p_spaceStatus,
                VPS_BLOCK_REASON =
                    CASE
                        WHEN @p_spaceStatus = 'B' THEN @p_blockReason
                        ELSE NULL
                    END,
                VPS_UPDATED_BY = @p_uid,
                VPS_UPDATED_DATE = SYSUTCDATETIME()
            WHERE VPS_SPACE_ID = @p_spaceID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space was not found';
                RETURN;
            END;

            SET @Result =
                CASE
                    WHEN @p_spaceStatus = 'B'
                        THEN 'Parking space blocked successfully'
                    ELSE 'Parking space unblocked successfully'
                END;
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