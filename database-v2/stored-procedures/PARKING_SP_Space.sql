USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Space
(
    @ActionType         INT,

    @p_spaceID          INT = NULL,
    @p_vehicleTypeID    INT = NULL,
    @p_spaceCode        VARCHAR(30) = NULL,
    @p_spaceName        NVARCHAR(100) = NULL,
    @p_spaceStatus      VARCHAR(20) = NULL,
    @p_blockReason      NVARCHAR(500) = NULL,
    @p_isActive         BIT = NULL,
    @p_includeInactive  BIT = 0,
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

        SET @p_spaceCode =
            UPPER(NULLIF(LTRIM(RTRIM(@p_spaceCode)), ''));

        SET @p_spaceName =
            NULLIF(LTRIM(RTRIM(@p_spaceName)), N'');

        SET @p_spaceStatus =
            UPPER(NULLIF(LTRIM(RTRIM(@p_spaceStatus)), ''));

        SET @p_blockReason =
            NULLIF(LTRIM(RTRIM(@p_blockReason)), N'');

        SET @p_includeInactive = ISNULL(@p_includeInactive, 0);

        /* ============================================================
           Shared Input Validation
           ============================================================ */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType NOT BETWEEN 1 AND 6
            SET @ValidationMessage = 'Invalid action type';

        ELSE IF @ActionType IN (2, 4, 5, 6)
             AND (@p_spaceID IS NULL OR @p_spaceID <= 0)
            SET @ValidationMessage = 'A valid space ID is required';

        ELSE IF @ActionType IN (3, 4)
             AND
             (
                 @p_spaceCode IS NULL
                 OR @p_vehicleTypeID IS NULL
                 OR @p_vehicleTypeID <= 0
             )
            SET @ValidationMessage =
                'Space code and a valid vehicle type are required';

        ELSE IF @ActionType = 5
             AND
             (
                 @p_spaceStatus IS NULL
                 OR @p_spaceStatus NOT IN ('AVAILABLE', 'BLOCKED')
             )
            SET @ValidationMessage =
                'Manual space status must be AVAILABLE or BLOCKED';

        ELSE IF @ActionType = 5
             AND @p_spaceStatus = 'BLOCKED'
             AND @p_blockReason IS NULL
            SET @ValidationMessage = 'A block reason is required';

        ELSE IF @ActionType = 6 AND @p_isActive IS NULL
            SET @ValidationMessage = 'Active status is required';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ============================================================
           1. Get Parking Spaces
           2. Get Parking Space By ID
           ============================================================ */

        IF @ActionType IN (1, 2)
        BEGIN
            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_USER
                WHERE UserID = @p_uid
                  AND ActiveStatus = 1
            )
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'An authenticated active user is required';
                RETURN;
            END;

            SELECT
                S.SpaceID,
                S.SpaceCode,
                S.SpaceName,
                S.VehicleTypeID,
                VT.TypeName AS VehicleType,
                VT.WheelCount,
                S.SpaceStatus,
                S.BlockReason,
                S.ActiveStatus,
                S.CreatedAt,
                S.CreatedBy,
                S.UpdatedAt,
                S.UpdatedBy
            FROM dbo.PARKING_SPACE AS S
            INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
                ON VT.VehicleTypeID = S.VehicleTypeID
            WHERE
                (
                    @ActionType = 1
                    AND
                    (
                        @p_includeInactive = 1
                        OR S.ActiveStatus = 1
                    )
                    AND
                    (
                        @p_vehicleTypeID IS NULL
                        OR S.VehicleTypeID = @p_vehicleTypeID
                    )
                )
                OR
                (
                    @ActionType = 2
                    AND S.SpaceID = @p_spaceID
                )
            ORDER BY S.SpaceCode, S.SpaceID;

            IF @@ROWCOUNT = 0 AND @ActionType = 2
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Parking space was not found';
                RETURN;
            END;

            SET @ResultStatusCode = 1;
            SET @Result = 'Parking space details retrieved successfully';
            RETURN;
        END;

        /* ============================================================
           Shared Validation For Write Operations
           ============================================================ */

        IF @@TRANCOUNT <> 0
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result =
                'Call this procedure without an existing transaction';
            RETURN;
        END;

        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;

        DECLARE @LockResult INT;

        EXEC @LockResult = sys.sp_getapplock
            @Resource = N'ParkingV2Configuration',
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 10000;

        IF @LockResult < 0
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = 'Parking configuration is busy. Please retry';
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.PARKING_USER WITH (HOLDLOCK)
            WHERE UserID = @p_uid
              AND UserRole = 'A'
              AND ActiveStatus = 1
        )
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = 'An active administrator is required';
            RETURN;
        END;

        DECLARE
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @StoredTypeID INT,
            @StoredStatus VARCHAR(20);

        SET @ValidationMessage = NULL;

        IF @ActionType IN (4, 5, 6)
        BEGIN
            SELECT
                @StoredTypeID = VehicleTypeID,
                @StoredStatus = SpaceStatus
            FROM dbo.PARKING_SPACE WITH (UPDLOCK, HOLDLOCK)
            WHERE SpaceID = @p_spaceID;

            IF @StoredTypeID IS NULL
                SET @ValidationMessage = 'Parking space was not found';

            ELSE IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_TICKET
                WHERE SpaceID = @p_spaceID
                  AND ExitDateTime IS NULL
            )
                SET @ValidationMessage =
                    'An open parking visit uses this space';

            ELSE IF @StoredStatus = 'OCCUPIED'
                SET @ValidationMessage =
                    'Space is marked occupied. Resolve its parking status before editing it';

            ELSE IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_MONTHLY_RESERVATION AS R
                INNER JOIN dbo.PARKING_MONTHLY_PAYMENT AS MP
                    ON MP.MonthlyPaymentID = R.MonthlyPaymentID
                INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS MC
                    ON MC.ContractID = MP.ContractID
                WHERE R.SpaceID = @p_spaceID
                  AND R.EffectiveToUTC > @Now
                  AND MP.PaymentStatus = 'COMPLETED'
                  AND MC.ContractStatus = 'ACTIVE'
                  AND MC.CancelledAt IS NULL
            )
                SET @ValidationMessage =
                    'A current or future paid monthly reservation uses this space';
        END;

        IF @ValidationMessage IS NULL AND @ActionType IN (3, 4)
        BEGIN
            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_VEHICLE_TYPE WITH (HOLDLOCK)
                WHERE VehicleTypeID = @p_vehicleTypeID
                  AND ActiveStatus = 1
            )
                SET @ValidationMessage =
                    'Active vehicle type was not found';

            ELSE IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_SPACE WITH (UPDLOCK, HOLDLOCK)
                WHERE SpaceCode = @p_spaceCode
                  AND
                  (
                      @ActionType = 3
                      OR SpaceID <> @p_spaceID
                  )
            )
                SET @ValidationMessage = 'Space code already exists';

            ELSE IF @ActionType = 4
                 AND @p_vehicleTypeID <> @StoredTypeID
                 AND EXISTS
                 (
                     SELECT 1
                     FROM dbo.PARKING_TICKET
                     WHERE SpaceID = @p_spaceID
                 )
                SET @ValidationMessage =
                    'A space with parking history cannot change vehicle category. Create a new space instead';
        END;

        IF @ValidationMessage IS NULL
           AND @ActionType = 6
           AND @p_isActive = 1
           AND NOT EXISTS
           (
               SELECT 1
               FROM dbo.PARKING_VEHICLE_TYPE WITH (HOLDLOCK)
               WHERE VehicleTypeID = @StoredTypeID
                 AND ActiveStatus = 1
           )
            SET @ValidationMessage =
                'Activate the vehicle type before activating its space';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        -- Clear an expired reservation marker only after all checks pass.
        IF @ActionType IN (4, 5, 6) AND @StoredStatus = 'RESERVED'
        BEGIN
            UPDATE dbo.PARKING_SPACE
            SET
                SpaceStatus = 'AVAILABLE',
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE SpaceID = @p_spaceID;
        END;

        /* ============================================================
           3. Create Parking Space
           ============================================================ */

        IF @ActionType = 3
        BEGIN
            INSERT INTO dbo.PARKING_SPACE
            (
                VehicleTypeID,
                SpaceCode,
                SpaceName,
                CreatedAt,
                CreatedBy
            )
            VALUES
            (
                @p_vehicleTypeID,
                @p_spaceCode,
                @p_spaceName,
                @Now,
                @p_uid
            );

            SET @p_spaceID = CONVERT(INT, SCOPE_IDENTITY());
            SET @Result = 'Parking space created successfully';
        END

        /* ============================================================
           4. Update Parking Space Details
           ============================================================ */

        ELSE IF @ActionType = 4
        BEGIN
            UPDATE dbo.PARKING_SPACE
            SET
                VehicleTypeID = @p_vehicleTypeID,
                SpaceCode = @p_spaceCode,
                SpaceName = @p_spaceName,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE SpaceID = @p_spaceID;

            SET @Result = 'Parking space updated successfully';
        END

        /* ============================================================
           5. Block / Unblock Parking Space
           ============================================================ */

        ELSE IF @ActionType = 5
        BEGIN
            UPDATE dbo.PARKING_SPACE
            SET
                SpaceStatus = @p_spaceStatus,
                BlockReason =
                    CASE
                        WHEN @p_spaceStatus = 'BLOCKED'
                            THEN @p_blockReason
                        ELSE NULL
                    END,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE SpaceID = @p_spaceID;

            SET @Result =
                CASE
                    WHEN @p_spaceStatus = 'BLOCKED'
                        THEN 'Parking space blocked successfully'
                    ELSE 'Parking space unblocked successfully'
                END;
        END

        /* ============================================================
           6. Activate / Deactivate Parking Space
           ============================================================ */

        ELSE IF @ActionType = 6
        BEGIN
            UPDATE dbo.PARKING_SPACE
            SET
                ActiveStatus = @p_isActive,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE SpaceID = @p_spaceID;

            SET @Result =
                CASE
                    WHEN @p_isActive = 1
                        THEN 'Parking space activated successfully'
                    ELSE 'Parking space deactivated successfully'
                END;
        END;

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;

        SELECT @p_spaceID AS SpaceID;

    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while processing parking space details';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO