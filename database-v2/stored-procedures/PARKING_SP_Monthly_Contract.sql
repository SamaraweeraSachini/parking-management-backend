USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.PARKING_SP_Monthly_Contract
(
    @ActionType         INT,

    @p_contractID       INT = NULL,
    @p_customerID       INT = NULL,
    @p_vehicleID        INT = NULL,
    @p_monthlyFee       DECIMAL(12,2) = NULL,
    @p_startDate        DATE = NULL,
    @p_endDate          DATE = NULL,
    @p_cancelledReason  NVARCHAR(500) = NULL,
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

        SET @p_cancelledReason =
            NULLIF(LTRIM(RTRIM(@p_cancelledReason)), N'');

        SET @p_searchTerm =
            NULLIF(LTRIM(RTRIM(@p_searchTerm)), N'');

        /* ============================================================
           Shared Input Validation
           ============================================================ */

        DECLARE @ValidationMessage VARCHAR(500);

        IF @ActionType IS NULL OR @ActionType NOT BETWEEN 1 AND 6
            SET @ValidationMessage = 'Invalid action type';

        ELSE IF @ActionType IN (2, 4, 5, 6)
             AND (@p_contractID IS NULL OR @p_contractID <= 0)
            SET @ValidationMessage = 'A valid contract ID is required';

        ELSE IF @ActionType = 3
             AND
             (
                 @p_customerID IS NULL OR @p_customerID <= 0
                 OR @p_vehicleID IS NULL OR @p_vehicleID <= 0
             )
            SET @ValidationMessage =
                'Valid customer and vehicle IDs are required';

        ELSE IF @ActionType IN (3, 4)
             AND
             (
                 @p_startDate IS NULL
                 OR @p_endDate IS NULL
                 OR @p_endDate < @p_startDate
             )
            SET @ValidationMessage =
                'Valid contract start and end dates are required';

        ELSE IF @ActionType IN (3, 4) AND @p_monthlyFee < 0
            SET @ValidationMessage = 'Monthly fee cannot be negative';

        ELSE IF @ActionType = 4 AND @p_monthlyFee IS NULL
            SET @ValidationMessage =
                'Monthly fee is required when updating a contract';

        ELSE IF @ActionType = 5 AND @p_cancelledReason IS NULL
            SET @ValidationMessage = 'A cancellation reason is required';

        IF @ValidationMessage IS NOT NULL
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

        DECLARE @Today DATE =
            CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

        /* ============================================================
           1. Get / Search Monthly Contracts
           2. Get Monthly Contract By ID
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
                MC.ContractID,
                MC.ContractNumber,
                MC.CustomerID,
                C.CustomerName,
                C.MobileNumber,
                MC.VehicleID,
                V.VehicleNumber,
                V.VehicleTypeID,
                VT.TypeName AS VehicleType,
                MC.MonthlyFee,
                MC.StartDate,
                MC.EndDate,
                MC.ContractStatus,

                CASE
                    WHEN MC.ContractStatus = 'CANCELLED'
                        THEN 'CANCELLED'
                    WHEN MC.ContractStatus = 'EXPIRED'
                         OR MC.EndDate < @Today
                        THEN 'EXPIRED'
                    WHEN MC.StartDate > @Today
                        THEN 'UPCOMING'
                    ELSE 'ACTIVE'
                END AS EffectiveContractStatus,

                MC.CancelledAt,
                MC.CancelledReason,
                MC.CreatedAt,
                MC.CreatedBy,
                MC.UpdatedAt,
                MC.UpdatedBy
            FROM dbo.PARKING_MONTHLY_CONTRACT AS MC
            INNER JOIN dbo.PARKING_CUSTOMER AS C
                ON C.CustomerID = MC.CustomerID
            INNER JOIN dbo.PARKING_CUSTOMER_VEHICLE AS V
                ON V.VehicleID = MC.VehicleID
            INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
                ON VT.VehicleTypeID = V.VehicleTypeID
            WHERE
                (
                    @ActionType = 1
                    AND
                    (
                        @p_customerID IS NULL
                        OR MC.CustomerID = @p_customerID
                    )
                    AND
                    (
                        @p_vehicleID IS NULL
                        OR MC.VehicleID = @p_vehicleID
                    )
                    AND
                    (
                        @p_searchTerm IS NULL
                        OR CHARINDEX
                           (
                               UPPER(@p_searchTerm),
                               UPPER(MC.ContractNumber)
                           ) > 0
                        OR CHARINDEX
                           (
                               UPPER(@p_searchTerm),
                               UPPER(C.CustomerName)
                           ) > 0
                        OR CHARINDEX
                           (
                               UPPER(@p_searchTerm),
                               UPPER(V.VehicleNumber)
                           ) > 0
                        OR CHARINDEX
                           (
                               @p_searchTerm,
                               C.MobileNumber
                           ) > 0
                    )
                )
                OR
                (
                    @ActionType = 2
                    AND MC.ContractID = @p_contractID
                )
            ORDER BY MC.StartDate DESC, MC.ContractID DESC;

            IF @@ROWCOUNT = 0 AND @ActionType = 2
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly contract was not found';
                RETURN;
            END;

            SET @ResultStatusCode = 1;
            SET @Result = 'Monthly contract details retrieved successfully';
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
            SET @Result =
                'Monthly contract management is busy. Please retry';
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

        SET @Now = SYSUTCDATETIME();
        SET @Today = CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

        DECLARE
            @StoredStatus VARCHAR(20),
            @StoredEndDate DATE,
            @VehicleTypeID INT,
            @ContractNumber VARCHAR(40);

        SET @ValidationMessage = NULL;

        IF @ActionType IN (4, 5, 6)
        BEGIN
            SELECT
                @StoredStatus = ContractStatus,
                @StoredEndDate = EndDate,
                @ContractNumber = ContractNumber
            FROM dbo.PARKING_MONTHLY_CONTRACT
                WITH (UPDLOCK, HOLDLOCK)
            WHERE ContractID = @p_contractID;

            IF @StoredStatus IS NULL
                SET @ValidationMessage = 'Monthly contract was not found';
        END;

        /* ============================================================
           Validate New Contract
           ============================================================ */

        IF @ActionType = 3
        BEGIN
            IF @p_endDate < @Today
                SET @ValidationMessage =
                    'A new contract cannot already have ended';

            IF @ValidationMessage IS NULL
            BEGIN
                SELECT @VehicleTypeID = V.VehicleTypeID
                FROM dbo.PARKING_CUSTOMER_VEHICLE AS V
                    WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.PARKING_CUSTOMER AS C
                    WITH (HOLDLOCK)
                    ON C.CustomerID = V.CustomerID
                INNER JOIN dbo.PARKING_VEHICLE_TYPE AS VT
                    WITH (HOLDLOCK)
                    ON VT.VehicleTypeID = V.VehicleTypeID
                WHERE V.VehicleID = @p_vehicleID
                  AND V.CustomerID = @p_customerID
                  AND V.ActiveStatus = 1
                  AND C.ActiveStatus = 1
                  AND VT.ActiveStatus = 1;

                IF @VehicleTypeID IS NULL
                    SET @ValidationMessage =
                        'An active vehicle belonging to the active customer and an active vehicle type are required';

                ELSE IF EXISTS
                (
                    SELECT 1
                    FROM dbo.PARKING_MONTHLY_CONTRACT
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE VehicleID = @p_vehicleID
                      AND ContractStatus = 'ACTIVE'
                      AND EndDate >= @Today
                )
                    SET @ValidationMessage =
                        'This vehicle already has an active or upcoming monthly agreement';
            END;

            IF @ValidationMessage IS NULL
               AND @p_monthlyFee IS NULL
            BEGIN
                DECLARE @RateCount INT;

                SELECT
                    @RateCount = COUNT(*),
                    @p_monthlyFee = MAX(RateAmount)
                FROM dbo.PARKING_RATE WITH (HOLDLOCK)
                WHERE VehicleTypeID = @VehicleTypeID
                  AND RateUnit = 'MONTHLY'
                  AND ActiveStatus = 1
                  AND EffectiveFrom <= @Now
                  AND
                  (
                      EffectiveTo IS NULL
                      OR EffectiveTo > @Now
                  );

                IF @RateCount <> 1
                    SET @ValidationMessage =
                        'Provide an agreed monthly fee or configure one effective monthly rate';
            END;
        END;

        /* ============================================================
           Validate Contract Update
           ============================================================ */

        IF @ValidationMessage IS NULL AND @ActionType = 4
        BEGIN
            IF @StoredStatus <> 'ACTIVE'
               OR @StoredEndDate < @Today
                SET @ValidationMessage =
                    'Only an active or upcoming agreement can be edited';

            ELSE IF @p_endDate < @Today
                SET @ValidationMessage =
                    'The updated contract cannot already have ended';

            ELSE IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_MONTHLY_PAYMENT
                WHERE ContractID = @p_contractID
            )
            OR EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_TICKET
                WHERE MonthlyContractID = @p_contractID
            )
                SET @ValidationMessage =
                    'A contract with payment or attendance history cannot be edited';
        END;

        /* ============================================================
           Validate Contract Cancellation
           ============================================================ */

        IF @ValidationMessage IS NULL AND @ActionType = 5
        BEGIN
            IF @StoredStatus <> 'ACTIVE'
                SET @ValidationMessage =
                    'Only an administratively active contract can be cancelled';

            ELSE IF EXISTS
            (
                SELECT 1
                FROM dbo.PARKING_TICKET
                WHERE MonthlyContractID = @p_contractID
                  AND ExitDateTime IS NULL
            )
                SET @ValidationMessage =
                    'Complete the vehicle exit before cancelling its contract';
        END;

        /* ============================================================
           Validate Contract Expiry
           ============================================================ */

        IF @ValidationMessage IS NULL AND @ActionType = 6
        BEGIN
            IF @StoredStatus = 'CANCELLED'
                SET @ValidationMessage =
                    'A cancelled contract cannot be expired';

            ELSE IF @StoredEndDate >= @Today
                SET @ValidationMessage =
                    'The contract period has not ended';
        END;

        IF @ValidationMessage IS NOT NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @StartedTransaction = 0;

            SET @ResultStatusCode = -1;
            SET @Result = @ValidationMessage;
            RETURN;
        END;

        /* ============================================================
           3. Create Monthly Contract
           ============================================================ */

        IF @ActionType = 3
        BEGIN
            -- Free the active-contract slot occupied by ended agreements.
            UPDATE dbo.PARKING_MONTHLY_CONTRACT
            SET
                ContractStatus = 'EXPIRED',
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE VehicleID = @p_vehicleID
              AND ContractStatus = 'ACTIVE'
              AND EndDate < @Today;

            DECLARE @ContractSequence BIGINT =
                NEXT VALUE FOR dbo.PARKING_CONTRACT_SEQUENCE;

            SET @ContractNumber =
                'MC-' + CONVERT(VARCHAR(20), @ContractSequence);

            INSERT INTO dbo.PARKING_MONTHLY_CONTRACT
            (
                ContractNumber,
                CustomerID,
                VehicleID,
                MonthlyFee,
                StartDate,
                EndDate,
                CreatedAt,
                CreatedBy
            )
            VALUES
            (
                @ContractNumber,
                @p_customerID,
                @p_vehicleID,
                @p_monthlyFee,
                @p_startDate,
                @p_endDate,
                @Now,
                @p_uid
            );

            SET @p_contractID = CONVERT(INT, SCOPE_IDENTITY());
            SET @Result =
                'Monthly contract created successfully. Payment is still required';
        END

        /* ============================================================
           4. Update Unused Monthly Contract
           ============================================================ */

        ELSE IF @ActionType = 4
        BEGIN
            UPDATE dbo.PARKING_MONTHLY_CONTRACT
            SET
                MonthlyFee = @p_monthlyFee,
                StartDate = @p_startDate,
                EndDate = @p_endDate,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE ContractID = @p_contractID;

            SET @Result = 'Monthly contract updated successfully';
        END

        /* ============================================================
           5. Cancel Monthly Contract
           ============================================================ */

        ELSE IF @ActionType = 5
        BEGIN
            UPDATE dbo.PARKING_MONTHLY_CONTRACT
            SET
                ContractStatus = 'CANCELLED',
                CancelledAt = @Now,
                CancelledReason = @p_cancelledReason,
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE ContractID = @p_contractID;

            SET @Result =
                'Monthly contract cancelled successfully. Payment history is retained';
        END

        /* ============================================================
           6. Expire Ended Monthly Contract
           ============================================================ */

        ELSE IF @ActionType = 6
        BEGIN
            UPDATE dbo.PARKING_MONTHLY_CONTRACT
            SET
                ContractStatus = 'EXPIRED',
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            WHERE ContractID = @p_contractID;

            SET @Result = 'Monthly contract marked expired successfully';
        END;

        /* ============================================================
           Release Unoccupied Reservation Markers
           After Contract Cancellation Or Expiry
           ============================================================ */

        IF @ActionType IN (5, 6)
        BEGIN
            UPDATE S
            SET
                SpaceStatus = 'AVAILABLE',
                UpdatedAt = @Now,
                UpdatedBy = @p_uid
            FROM dbo.PARKING_SPACE AS S
            WHERE S.SpaceStatus = 'RESERVED'
              AND EXISTS
              (
                  SELECT 1
                  FROM dbo.PARKING_MONTHLY_RESERVATION AS R
                  INNER JOIN dbo.PARKING_MONTHLY_PAYMENT AS MP
                      ON MP.MonthlyPaymentID = R.MonthlyPaymentID
                  WHERE R.SpaceID = S.SpaceID
                    AND MP.ContractID = @p_contractID
              )
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.PARKING_TICKET AS T
                  WHERE T.SpaceID = S.SpaceID
                    AND T.ExitDateTime IS NULL
              )
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.PARKING_MONTHLY_RESERVATION AS R
                  INNER JOIN dbo.PARKING_MONTHLY_PAYMENT AS MP
                      ON MP.MonthlyPaymentID = R.MonthlyPaymentID
                  INNER JOIN dbo.PARKING_MONTHLY_CONTRACT AS MC
                      ON MC.ContractID = MP.ContractID
                  WHERE R.SpaceID = S.SpaceID
                    AND MP.PaymentStatus = 'COMPLETED'
                    AND MC.ContractStatus = 'ACTIVE'
                    AND MC.CancelledAt IS NULL
                    AND MC.StartDate <= @Today
                    AND MC.EndDate >= @Today
                    AND R.EffectiveFromUTC <= @Now
                    AND R.EffectiveToUTC > @Now
              );
        END;

        COMMIT TRANSACTION;
        SET @StartedTransaction = 0;

        SET @ResultStatusCode = 1;

        SELECT
            @p_contractID AS ContractID,
            @ContractNumber AS ContractNumber;

    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result =
            'An error occurred while processing monthly contracts';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO