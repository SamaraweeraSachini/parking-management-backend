USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_MONTHLY_PAYMENT_PROC
    @ActionType INT,

    @p_monthlyPaymentID INT = NULL,
    @p_contractID INT = NULL,
    @p_periodStartDate DATE = NULL,
    @p_periodEndDate DATE = NULL,
    @p_amount DECIMAL(12,2) = NULL,
    @p_paymentMethod VARCHAR(20) = NULL,
    @p_reservationID VARCHAR(10) = NULL,
    @p_spaceID VARCHAR(10) = NULL,
    @p_remarks VARCHAR(500) = NULL,
    @p_searchTerm VARCHAR(200) = NULL,
    @p_uid INT = NULL,

    @ResultStatusCode INT OUTPUT,
    @Result VARCHAR(MAX) OUTPUT,
    @ExceptionMessage VARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @LockResult INT;

    BEGIN TRY
        SET @ResultStatusCode = 1;
        SET @Result = 'Success';
        SET @ExceptionMessage = NULL;

        SET @p_paymentMethod = UPPER(NULLIF(LTRIM(RTRIM(@p_paymentMethod)), ''));
        SET @p_reservationID = NULLIF(LTRIM(RTRIM(@p_reservationID)), '');
        SET @p_spaceID = NULLIF(LTRIM(RTRIM(@p_spaceID)), '');
        SET @p_remarks = NULLIF(LTRIM(RTRIM(@p_remarks)), '');
        SET @p_searchTerm = NULLIF(LTRIM(RTRIM(@p_searchTerm)), '');

        /** 1. Get monthly payments **/
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
                MP.VPP_MONTHLY_PAYMENT_ID,
                MP.VPP_PAYMENT_NUMBER,
                MP.VPP_RECEIPT_NUMBER,
                MP.VPP_CONTRACT_ID,
                MC.VPM_CONTRACT_NUMBER,
                C.VPC_CUSTOMER_NAME,
                V.VPV_VEHICLE_NUMBER,
                MP.VPP_PERIOD_START_DATE,
                MP.VPP_PERIOD_END_DATE,
                MP.VPP_AMOUNT,
                MP.VPP_PAYMENT_METHOD,
                MP.VPP_PAYMENT_STATUS,
                MP.VPP_PAYMENT_DATE,
                U.VPU_FULL_NAME AS ReceivedBy
            FROM dbo.VPMS_MONTHLY_PAYMENT AS MP
            INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                ON MC.VPM_CONTRACT_ID = MP.VPP_CONTRACT_ID
            INNER JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = MC.VPM_CUSTOMER_ID
            INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                ON V.VPV_VEHICLE_ID = MC.VPM_VEHICLE_ID
            INNER JOIN dbo.VPMS_PARKING_USER AS U
                ON U.VPU_USER_ID = MP.VPP_RECEIVED_BY_USER_ID
            WHERE (@p_contractID IS NULL OR MP.VPP_CONTRACT_ID = @p_contractID)
              AND
              (
                  @p_searchTerm IS NULL
                  OR CHARINDEX(@p_searchTerm, MP.VPP_PAYMENT_NUMBER) > 0
                  OR CHARINDEX(@p_searchTerm, MP.VPP_RECEIPT_NUMBER) > 0
                  OR CHARINDEX(@p_searchTerm, MC.VPM_CONTRACT_NUMBER) > 0
                  OR CHARINDEX(@p_searchTerm, C.VPC_CUSTOMER_NAME) > 0
                  OR CHARINDEX(@p_searchTerm, V.VPV_VEHICLE_NUMBER) > 0
                  OR CHARINDEX(@p_searchTerm, C.VPC_MOBILE_NUMBER) > 0
              )
            ORDER BY MP.VPP_PAYMENT_DATE DESC, MP.VPP_MONTHLY_PAYMENT_ID DESC;

            SET @Result = 'Monthly payment list retrieved successfully';
        END

        /** 2. Get monthly payment and receipt by ID **/
        ELSE IF @ActionType = 2
        BEGIN
            IF @p_monthlyPaymentID IS NULL OR @p_monthlyPaymentID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid monthly payment ID is required';
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
                'M' AS PaymentType,
                MP.VPP_MONTHLY_PAYMENT_ID,
                MP.VPP_PAYMENT_NUMBER,
                MP.VPP_RECEIPT_NUMBER,
                MC.VPM_CONTRACT_NUMBER,
                C.VPC_CUSTOMER_NAME,
                V.VPV_VEHICLE_NUMBER,
                MP.VPP_PERIOD_START_DATE,
                MP.VPP_PERIOD_END_DATE,
                MP.VPP_AMOUNT,
                MP.VPP_PAYMENT_METHOD,
                MP.VPP_PAYMENT_STATUS,
                MP.VPP_PAYMENT_DATE,
                U.VPU_FULL_NAME AS ReceivedBy,
                MP.VPP_REMARKS,
                A.VPS_FACILITY_NAME,
                A.VPS_ADDRESS,
                A.VPS_CONTACT_NUMBER,
                A.VPS_RECEIPT_MESSAGE
            FROM dbo.VPMS_MONTHLY_PAYMENT AS MP
            INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                ON MC.VPM_CONTRACT_ID = MP.VPP_CONTRACT_ID
            INNER JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = MC.VPM_CUSTOMER_ID
            INNER JOIN dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
                ON V.VPV_VEHICLE_ID = MC.VPM_VEHICLE_ID
            INNER JOIN dbo.VPMS_PARKING_USER AS U
                ON U.VPU_USER_ID = MP.VPP_RECEIVED_BY_USER_ID
            LEFT JOIN dbo.VPMS_APP_SETTINGS AS A
                ON A.VPS_SETTINGS_ID = 1
            WHERE MP.VPP_MONTHLY_PAYMENT_ID = @p_monthlyPaymentID;

            IF @@ROWCOUNT = 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly payment was not found';
                RETURN;
            END;

            SET @Result = 'Monthly payment and receipt retrieved successfully';
        END

        /** 3. Receive monthly payment and reserve space **/
        ELSE IF @ActionType = 3
        BEGIN
            IF @p_contractID IS NULL OR @p_contractID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid contract ID is required';
                RETURN;
            END;

            IF @p_reservationID IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Reservation ID is required';
                RETURN;
            END;

            IF @p_periodStartDate IS NULL
               OR @p_periodEndDate IS NULL
               OR @p_periodEndDate < @p_periodStartDate
               OR @p_periodEndDate = CONVERT(DATE, '99991231', 112)
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid payment coverage period is required';
                RETURN;
            END;

            IF @p_amount IS NULL OR @p_amount < 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A confirmed payment amount of zero or greater is required';
                RETURN;
            END;

            IF @p_paymentMethod IS NULL
               OR @p_paymentMethod NOT IN ('CH', 'CD')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Payment method must be CH - Cash / CD - Card';
                RETURN;
            END;

            IF @@TRANCOUNT > 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Call this action without an existing transaction';
                RETURN;
            END;

            BEGIN TRANSACTION;
            SET @StartedTransaction = 1;

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
                SET @Result = 'Parking management is busy. Please retry';
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
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An active administrator or operator is required';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_MONTHLY_RESERVATION
                WHERE VPR_RESERVATION_ID = @p_reservationID
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Reservation ID already exists';
                RETURN;
            END;

            DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
            DECLARE @Today DATE = CONVERT(DATE, DATEADD(MINUTE, 330, @Now));
            DECLARE @CustomerID INT;
            DECLARE @VehicleID VARCHAR(10);
            DECLARE @VehicleTypeID VARCHAR(10);
            DECLARE @ContractStartDate DATE;
            DECLARE @ContractEndDate DATE;
            DECLARE @ContractStatus VARCHAR(20);

            SELECT
                @CustomerID = VPM_CUSTOMER_ID,
                @VehicleID = VPM_VEHICLE_ID,
                @ContractStartDate = VPM_START_DATE,
                @ContractEndDate = VPM_END_DATE,
                @ContractStatus = VPM_CONTRACT_STATUS
            FROM dbo.VPMS_PARKING_MONTHLYCONTRACT
            WHERE VPM_CONTRACT_ID = @p_contractID;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Monthly contract was not found';
                RETURN;
            END;

            IF @ContractStatus <> 'A' OR @ContractEndDate < @Today
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid active or upcoming monthly contract is required';
                RETURN;
            END;

            IF @p_periodStartDate < @ContractStartDate
               OR @p_periodEndDate > @ContractEndDate
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Payment coverage must be within the contract dates';
                RETURN;
            END;

            SELECT @VehicleTypeID = V.VPV_VEHICLE_TYPE_ID
            FROM dbo.VPMS_PARKINGCUSTOMER_VEHICLE AS V
            INNER JOIN dbo.VPMS_PARKING_CUSTOMER AS C
                ON C.VPC_CUSTOMER_ID = V.VPV_CUSTOMER_ID
            INNER JOIN dbo.VPMS_VEHICLE_TYPE AS VT
                ON VT.VVT_VEHICLE_TYPE_ID = V.VPV_VEHICLE_TYPE_ID
            WHERE V.VPV_VEHICLE_ID = @VehicleID
              AND V.VPV_CUSTOMER_ID = @CustomerID
              AND V.VPV_IS_ACTIVE = 'A'
              AND C.VPC_IS_ACTIVE = 'A'
              AND VT.VVT_IS_ACTIVE = 'A';

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An active matching customer, vehicle and vehicle type are required';
                RETURN;
            END;

            DECLARE @EffectiveFromUTC DATETIME2(0);
            DECLARE @EffectiveToUTC DATETIME2(0);

            SET @EffectiveFromUTC =
                DATEADD(MINUTE, -330, CONVERT(DATETIME2(0), @p_periodStartDate));

            SET @EffectiveToUTC =
                DATEADD
                (
                    MINUTE,
                    -330,
                    DATEADD(DAY, 1, CONVERT(DATETIME2(0), @p_periodEndDate))
                );

            IF @EffectiveToUTC <= @Now
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'The selected coverage period has already ended';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_MONTHLY_PAYMENT
                WHERE VPP_CONTRACT_ID = @p_contractID
                  AND VPP_PAYMENT_STATUS = 'C'
                  AND VPP_PERIOD_START_DATE <= @p_periodEndDate
                  AND VPP_PERIOD_END_DATE >= @p_periodStartDate
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'A completed payment already overlaps this coverage period';
                RETURN;
            END;

            /** Find a compatible space **/
            DECLARE @SelectedSpaceID VARCHAR(10);

            SELECT TOP (1)
                @SelectedSpaceID = S.VPS_SPACE_ID
            FROM dbo.VPMS_PARKING_SPACE AS S
            WHERE S.VPS_VEHICLE_TYPE_ID = @VehicleTypeID
              AND S.VPS_SPACE_STATUS IN ('AV', 'RE', 'OC')
              AND (@p_spaceID IS NULL OR S.VPS_SPACE_ID = @p_spaceID)
              AND
              (
                  S.VPS_SPACE_STATUS <> 'OC'
                  OR EXISTS
                  (
                      SELECT 1
                      FROM dbo.VPMS_PARKING_TICKET AS T
                      WHERE T.VPT_SPACE_ID = S.VPS_SPACE_ID
                        AND T.VPT_VEHICLE_ID = @VehicleID
                        AND T.VPT_MONTHLY_CONTRACT_ID = @p_contractID
                        AND T.VPT_PARKING_TYPE = 'M'
                        AND T.VPT_EXIT_DATE_TIME IS NULL
                        AND T.VPT_TICKET_STATUS <> 'CN'
                  )
              )
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.VPMS_PARKING_TICKET AS T
                  WHERE T.VPT_SPACE_ID = S.VPS_SPACE_ID
                    AND T.VPT_EXIT_DATE_TIME IS NULL
                    AND
                    (
                        T.VPT_TICKET_STATUS = 'CN'
                        OR T.VPT_VEHICLE_ID <> @VehicleID
                        OR T.VPT_PARKING_TYPE <> 'M'
                        OR T.VPT_MONTHLY_CONTRACT_ID IS NULL
                        OR T.VPT_MONTHLY_CONTRACT_ID <> @p_contractID
                    )
              )
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.VPMS_MONTHLY_RESERVATION AS R
                  INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                      ON MP.VPP_MONTHLY_PAYMENT_ID = R.VPR_MONTHLY_PAYMENT_ID
                  INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                      ON MC.VPM_CONTRACT_ID = MP.VPP_CONTRACT_ID
                  WHERE R.VPR_SPACE_ID = S.VPS_SPACE_ID
                    AND R.VPR_IS_ACTIVE = 'A'
                    AND MP.VPP_PAYMENT_STATUS = 'C'
                    AND MC.VPM_CONTRACT_STATUS = 'A'
                    AND R.VPR_EFFECTIVE_FROM_UTC < @EffectiveToUTC
                    AND R.VPR_EFFECTIVE_TO_UTC > @EffectiveFromUTC
              )
            ORDER BY
                CASE
                    WHEN EXISTS
                    (
                        SELECT 1
                        FROM dbo.VPMS_PARKING_TICKET AS T
                        WHERE T.VPT_SPACE_ID = S.VPS_SPACE_ID
                          AND T.VPT_VEHICLE_ID = @VehicleID
                          AND T.VPT_MONTHLY_CONTRACT_ID = @p_contractID
                          AND T.VPT_PARKING_TYPE = 'M'
                          AND T.VPT_EXIT_DATE_TIME IS NULL
                          AND T.VPT_TICKET_STATUS <> 'CN'
                    ) THEN 0
                    WHEN EXISTS
                    (
                        SELECT 1
                        FROM dbo.VPMS_MONTHLY_RESERVATION AS R
                        INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                            ON MP.VPP_MONTHLY_PAYMENT_ID = R.VPR_MONTHLY_PAYMENT_ID
                        WHERE R.VPR_SPACE_ID = S.VPS_SPACE_ID
                          AND MP.VPP_CONTRACT_ID = @p_contractID
                          AND MP.VPP_PAYMENT_STATUS = 'C'
                    ) THEN 1
                    ELSE 2
                END,
                S.VPS_SPACE_CODE,
                S.VPS_SPACE_ID;

            IF @SelectedSpaceID IS NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'No compatible space is available for the selected coverage period';
                RETURN;
            END;

            SET @p_spaceID = @SelectedSpaceID;

            /** Save monthly payment **/
            DECLARE @PaymentSequence BIGINT =
                NEXT VALUE FOR dbo.VPMS_PARKING_PAYMENT_SEQUENCE;

            DECLARE @PaymentNumber VARCHAR(40) =
                'PM-' + CONVERT(VARCHAR(20), @PaymentSequence);

            DECLARE @ReceiptNumber VARCHAR(40) =
                'RM-' + CONVERT(VARCHAR(20), @PaymentSequence);

            INSERT INTO dbo.VPMS_MONTHLY_PAYMENT
            (
                VPP_PAYMENT_NUMBER,
                VPP_CONTRACT_ID,
                VPP_PERIOD_START_DATE,
                VPP_PERIOD_END_DATE,
                VPP_AMOUNT,
                VPP_PAYMENT_METHOD,
                VPP_PAYMENT_STATUS,
                VPP_PAYMENT_DATE,
                VPP_RECEIVED_BY_USER_ID,
                VPP_RECEIPT_NUMBER,
                VPP_REMARKS,
                VPP_CREATED_BY,
                VPP_CREATED_DATE
            )
            VALUES
            (
                @PaymentNumber,
                @p_contractID,
                @p_periodStartDate,
                @p_periodEndDate,
                @p_amount,
                @p_paymentMethod,
                'C',
                @Now,
                @p_uid,
                @ReceiptNumber,
                @p_remarks,
                @p_uid,
                @Now
            );

            SET @p_monthlyPaymentID = CONVERT(INT, SCOPE_IDENTITY());

            /** Save space reservation **/
            INSERT INTO dbo.VPMS_MONTHLY_RESERVATION
            (
                VPR_RESERVATION_ID,
                VPR_MONTHLY_PAYMENT_ID,
                VPR_SPACE_ID,
                VPR_EFFECTIVE_FROM_UTC,
                VPR_EFFECTIVE_TO_UTC,
                VPR_IS_ACTIVE,
                VPR_CREATED_BY,
                VPR_CREATED_DATE
            )
            VALUES
            (
                @p_reservationID,
                @p_monthlyPaymentID,
                @p_spaceID,
                @EffectiveFromUTC,
                @EffectiveToUTC,
                'A',
                @p_uid,
                @Now
            );

            /** Update current space status **/
            UPDATE S
            SET VPS_SPACE_STATUS =
                    CASE
                        WHEN EXISTS
                        (
                            SELECT 1
                            FROM dbo.VPMS_PARKING_TICKET AS T
                            WHERE T.VPT_SPACE_ID = S.VPS_SPACE_ID
                              AND T.VPT_EXIT_DATE_TIME IS NULL
                        ) THEN 'OC'
                        WHEN EXISTS
                        (
                            SELECT 1
                            FROM dbo.VPMS_MONTHLY_RESERVATION AS R
                            INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                                ON MP.VPP_MONTHLY_PAYMENT_ID = R.VPR_MONTHLY_PAYMENT_ID
                            INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                                ON MC.VPM_CONTRACT_ID = MP.VPP_CONTRACT_ID
                            WHERE R.VPR_SPACE_ID = S.VPS_SPACE_ID
                              AND R.VPR_IS_ACTIVE = 'A'
                              AND MP.VPP_PAYMENT_STATUS = 'C'
                              AND MC.VPM_CONTRACT_STATUS = 'A'
                              AND MC.VPM_START_DATE <= @Today
                              AND MC.VPM_END_DATE >= @Today
                              AND R.VPR_EFFECTIVE_FROM_UTC <= @Now
                              AND R.VPR_EFFECTIVE_TO_UTC > @Now
                        ) THEN 'RE'
                        ELSE 'AV'
                    END,
                VPS_UPDATED_BY = @p_uid,
                VPS_UPDATED_DATE = @Now
            FROM dbo.VPMS_PARKING_SPACE AS S
            WHERE S.VPS_SPACE_ID = @p_spaceID;

            IF @@ROWCOUNT <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Could not update the reserved parking space';
                RETURN;
            END;

            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;

            SET @Result = 'Monthly payment and space reservation recorded successfully';

            SELECT
                @p_monthlyPaymentID AS VPP_MONTHLY_PAYMENT_ID,
                @PaymentNumber AS VPP_PAYMENT_NUMBER,
                @ReceiptNumber AS VPP_RECEIPT_NUMBER,
                @p_reservationID AS VPR_RESERVATION_ID,
                @p_spaceID AS VPR_SPACE_ID;
        END

        /** Invalid action **/
        ELSE
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = 'Invalid action type';
        END;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ResultStatusCode = -1;
        SET @Result = 'Error occurred';
        SET @ExceptionMessage = ERROR_MESSAGE();
    END CATCH;
END;
GO