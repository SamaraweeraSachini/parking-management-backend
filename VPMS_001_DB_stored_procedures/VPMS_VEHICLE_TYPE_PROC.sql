USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_VEHICLE_TYPE_PROC
    @ActionType INT,

    @p_typeId VARCHAR(10) = NULL,
    @p_typeName VARCHAR(100) = NULL,
    @p_wheelCount INT = NULL,
    @p_description VARCHAR(500) = NULL,
    @p_isActive CHAR(1) = NULL,
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

        /** 1. Get vehicle types **/
        IF @ActionType = 1
        BEGIN
            SELECT
                VVT_VEHICLE_TYPE_ID,
                VVT_TYPE_NAME,
                VVT_WHEEL_COUNT,
                VVT_DESCRIPTION,
                VVT_IS_ACTIVE
            FROM dbo.VPMS_VEHICLE_TYPE
            WHERE ISNULL(@p_includeInactive, 0) = 1
               OR VVT_IS_ACTIVE = 'A'
            ORDER BY VVT_WHEEL_COUNT;

            SET @Result = 'Vehicle type list retrieved successfully';
        END

        /* 2. Get vehicle type by ID */
        ELSE IF @ActionType = 2
        BEGIN
            IF @p_typeId IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type ID is required';
                RETURN;
            END;

            SELECT
                VVT_VEHICLE_TYPE_ID,
                VVT_TYPE_NAME,
                VVT_WHEEL_COUNT,
                VVT_DESCRIPTION,
                VVT_IS_ACTIVE
            FROM dbo.VPMS_VEHICLE_TYPE
            WHERE VVT_VEHICLE_TYPE_ID = @p_typeId;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type was not found';
                RETURN;
            END;

            SET @Result = 'Vehicle type retrieved successfully';
        END

        /* 3. Add vehicle type */
        ELSE IF @ActionType = 3
        BEGIN
            IF @p_typeId IS NULL
               OR @p_typeName IS NULL
               OR @p_wheelCount IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type ID, name, and wheel count are required';
                RETURN;
            END;

            INSERT INTO dbo.VPMS_VEHICLE_TYPE
            (
                VVT_VEHICLE_TYPE_ID,
                VVT_TYPE_NAME,
                VVT_WHEEL_COUNT,
                VVT_DESCRIPTION,
                VVT_IS_ACTIVE,
                VVT_CREATED_BY,
				VVT_CREATED_DATE
            )
            VALUES
            (
                @p_typeId,
                @p_typeName,
                @p_wheelCount,
                @p_description,
                ISNULL(@p_isActive, 'A'),
                @p_uid,
				SYSUTCDATETIME()
            );

            SET @Result = 'Vehicle type added successfully';
            SELECT @p_typeId AS VVT_VEHICLE_TYPE_ID;
        END

        /* 4. Update vehicle type */
        ELSE IF @ActionType = 4
        BEGIN
            IF @p_typeId IS NULL
               OR @p_typeName IS NULL
               OR @p_wheelCount IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type ID, name, and wheel count are required';
                RETURN;
            END;

            UPDATE dbo.VPMS_VEHICLE_TYPE
            SET VVT_TYPE_NAME = @p_typeName,
                VVT_WHEEL_COUNT = @p_wheelCount,
                VVT_DESCRIPTION = @p_description,
                VVT_UPDATED_BY = @p_uid,
                VVT_UPDATED_DATE = SYSUTCDATETIME()
            WHERE VVT_VEHICLE_TYPE_ID = @p_typeId;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type was not found';
                RETURN;
            END;

            SET @Result = 'Vehicle type updated successfully';
        END

        /* 5. Activate or deactivate vehicle type */
        ELSE IF @ActionType = 5
        BEGIN
            IF @p_typeId IS NULL
               OR @p_isActive NOT IN ('A', 'I')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type ID and status A or I are required';
                RETURN;
            END;

            UPDATE dbo.VPMS_VEHICLE_TYPE
            SET VVT_IS_ACTIVE = @p_isActive,
                VVT_UPDATED_BY = @p_uid,
                VVT_UPDATED_DATE = SYSUTCDATETIME()
            WHERE VVT_VEHICLE_TYPE_ID = @p_typeId;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Vehicle type was not found';
                RETURN;
            END;

            SET @Result = 'Vehicle type status updated successfully';
        END

        /* Invalid action */
        ELSE
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = 'Invalid action type';
        END
    END TRY
    BEGIN CATCH
        SET @ResultStatusCode = -1;
        SET @Result = 'Error occurred';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH
END;
GO