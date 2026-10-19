USE [VPMS_001_DB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.VPMS_PARKING_EXIT_PAYMENT_PROC
    @ActionType INT,

    @p_ticketID INT = NULL,
    @p_paymentMethod VARCHAR(20) = NULL,
    @p_expectedAmount DECIMAL(12,2) = NULL,
    @p_calculationTimeUTC DATETIME2(0) = NULL,
    @p_exitNow BIT = 1,
    @p_remarks VARCHAR(500) = NULL,
    @p_uid INT = NULL,

    @ResultStatusCode INT OUTPUT,
    @Result VARCHAR(MAX) OUTPUT,
    @ExceptionMessage VARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @CloseTicket BIT = 0;
    DECLARE @LockResult INT;

    BEGIN TRY
        SET @ResultStatusCode = 1;
        SET @Result = 'Success';
        SET @ExceptionMessage = NULL;

        SET @p_paymentMethod = UPPER(NULLIF(LTRIM(RTRIM(@p_paymentMethod)), ''));
        SET @p_remarks = NULLIF(LTRIM(RTRIM(@p_remarks)), '');

        /** Ticket and space details **/
        DECLARE @Now DATETIME2(0);
        DECLARE @Today DATE;
        DECLARE @SpaceID VARCHAR(10);
        DECLARE @SpaceStatus VARCHAR(20);
        DECLARE @TicketNumber VARCHAR(40);
        DECLARE @ParkingType VARCHAR(20);

        /** Fee calculation results **/
        DECLARE @Amount DECIMAL(12,2);
        DECLARE @DurationSeconds BIGINT;
        DECLARE @BillableHours DECIMAL(10,2);

        /** Generated payment details **/
        DECLARE @PaymentID INT;
        DECLARE @PaymentNumber VARCHAR(40);
        DECLARE @ReceiptNumber VARCHAR(40);

        /** 1. Preview daily parking fee **/
        IF @ActionType = 1
        BEGIN
            SET @Now = SYSUTCDATETIME();

            EXEC dbo.VPMS_DAILY_FEE_CALCULATE_PROC
                @ActionType = 1,
                @p_ticketID = @p_ticketID,
                @p_atUTC = @Now,
                @p_uid = @p_uid,
                @p_amount = @Amount OUTPUT,
                @p_durationSeconds = @DurationSeconds OUTPUT,
                @p_billableHours = @BillableHours OUTPUT,
                @ResultStatusCode = @ResultStatusCode OUTPUT,
                @Result = @Result OUTPUT,
                @ExceptionMessage = @ExceptionMessage OUTPUT;

            IF ISNULL(@ResultStatusCode, 0) <> 1
                RETURN;

            SELECT
                @p_ticketID AS VPT_TICKET_ID,
                @BillableHours AS VPT_BILLABLE_HOURS,
                @Amount AS VPT_CALCULATED_AMOUNT,
                @Now AS VPT_FEE_CALCULATED_DATE;

            RETURN;
        END

        /** 2. Receive daily payment and optionally complete exit **/
        ELSE IF @ActionType = 2
        BEGIN
            IF @p_ticketID IS NULL OR @p_ticketID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid ticket ID is required';
                RETURN;
            END;

            IF @p_expectedAmount IS NULL OR @p_expectedAmount < 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A confirmed preview amount of zero or greater is required';
                RETURN;
            END;

            IF @p_calculationTimeUTC IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'The confirmed preview calculation time is required';
                RETURN;
            END;

            IF @p_paymentMethod IS NULL
               OR @p_paymentMethod NOT IN ('CH', 'CD')
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'Payment method must be CH - Cash / CD - Card';
                RETURN;
            END;

            IF @p_exitNow IS NULL
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'The exit choice is required';
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

            SET @Now = SYSUTCDATETIME();
            SET @Today = CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

            IF @p_calculationTimeUTC > @Now
               OR @p_calculationTimeUTC < DATEADD(MINUTE, -2, @Now)
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Fee preview expired. Refresh and confirm again';
                RETURN;
            END;

            SELECT
                @SpaceID = VPT_SPACE_ID,
                @TicketNumber = VPT_TICKET_NUMBER,
                @ParkingType = VPT_PARKING_TYPE
            FROM dbo.VPMS_PARKING_TICKET
            WHERE VPT_TICKET_ID = @p_ticketID
              AND VPT_PARKING_TYPE = 'D'
              AND VPT_TICKET_STATUS = 'O'
              AND VPT_EXIT_DATE_TIME IS NULL;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'An open unpaid daily ticket is required';
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_PARKING_PAYMENT
                WHERE VPP_TICKET_ID = @p_ticketID
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'A payment record already exists for this ticket';
                RETURN;
            END;

            /** Verify the confirmed fee using saved ticket rates **/
            EXEC dbo.VPMS_DAILY_FEE_CALCULATE_PROC
                @ActionType = 1,
                @p_ticketID = @p_ticketID,
                @p_atUTC = @p_calculationTimeUTC,
                @p_uid = @p_uid,
                @p_amount = @Amount OUTPUT,
                @p_durationSeconds = @DurationSeconds OUTPUT,
                @p_billableHours = @BillableHours OUTPUT,
                @ResultStatusCode = @ResultStatusCode OUTPUT,
                @Result = @Result OUTPUT,
                @ExceptionMessage = @ExceptionMessage OUTPUT;

            IF ISNULL(@ResultStatusCode, 0) <> 1
            BEGIN
                IF XACT_STATE() <> 0
                    ROLLBACK TRANSACTION;

                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                RETURN;
            END;

            IF @Amount IS NULL OR @Amount <> @p_expectedAmount
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Fee changed. Refresh the preview and confirm again';
                RETURN;
            END;

            /** Save daily payment **/
            DECLARE @PaymentSequence BIGINT =
                NEXT VALUE FOR dbo.VPMS_PARKING_PAYMENT_SEQUENCE;

            SET @PaymentNumber = 'PD-' + CONVERT(VARCHAR(20), @PaymentSequence);
            SET @ReceiptNumber = 'RD-' + CONVERT(VARCHAR(20), @PaymentSequence);

            INSERT INTO dbo.VPMS_PARKING_PAYMENT
            (
                VPP_PAYMENT_NUMBER,
                VPP_TICKET_ID,
                VPP_AMOUNT,
                VPP_PAYMENT_METHOD,
                VPP_PAYMENT_STATUS,
                VPP_PAYMENT_DATE_TIME,
                VPP_RECEIVED_BY_USER_ID,
                VPP_RECEIPT_NUMBER,
                VPP_REMARKS,
                VPP_CREATED_BY,
                VPP_CREATED_DATE
            )
            VALUES
            (
                @PaymentNumber,
                @p_ticketID,
                @Amount,
                @p_paymentMethod,
                'C',
                @Now,
                @p_uid,
                @ReceiptNumber,
                @p_remarks,
                @p_uid,
                @Now
            );

            SET @PaymentID = CONVERT(INT, SCOPE_IDENTITY());

            /** Save confirmed billing details **/
            UPDATE dbo.VPMS_PARKING_TICKET
            SET VPT_BILLABLE_HOURS = @BillableHours,
                VPT_CALCULATED_AMOUNT = @Amount,
                VPT_FEE_CALCULATED_DATE = @p_calculationTimeUTC,
                VPT_TICKET_STATUS = 'PP',
                VPT_UPDATED_BY = @p_uid,
                VPT_UPDATED_DATE = @Now
            WHERE VPT_TICKET_ID = @p_ticketID
              AND VPT_PARKING_TYPE = 'D'
              AND VPT_TICKET_STATUS = 'O'
              AND VPT_EXIT_DATE_TIME IS NULL;

            IF @@ROWCOUNT <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Could not update the paid ticket';
                RETURN;
            END;

            SET @CloseTicket = @p_exitNow;
            SET @SpaceStatus = 'OC';

            SET @Result =
                CASE
                    WHEN @p_exitNow = 1
                        THEN 'Payment recorded and vehicle exited successfully'
                    ELSE 'Payment recorded. Vehicle exit remains pending'
                END;
        END

        /** 3. Complete paid daily exit or monthly exit **/
        ELSE IF @ActionType = 3
        BEGIN
            IF @p_ticketID IS NULL OR @p_ticketID <= 0
            BEGIN
                SET @ResultStatusCode = -1;
                SET @Result = 'A valid ticket ID is required';
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

            SET @Now = SYSUTCDATETIME();
            SET @Today = CONVERT(DATE, DATEADD(MINUTE, 330, @Now));

            SELECT
                @SpaceID = VPT_SPACE_ID,
                @TicketNumber = VPT_TICKET_NUMBER,
                @ParkingType = VPT_PARKING_TYPE
            FROM dbo.VPMS_PARKING_TICKET
            WHERE VPT_TICKET_ID = @p_ticketID
              AND VPT_ENTRY_DATE_TIME <= @Now
              AND VPT_EXIT_DATE_TIME IS NULL
              AND
              (
                  (VPT_PARKING_TYPE = 'D' AND VPT_TICKET_STATUS = 'PP')
                  OR (VPT_PARKING_TYPE = 'M' AND VPT_TICKET_STATUS = 'O')
              );

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'A paid daily ticket or open monthly ticket with a valid entry time is required';
                RETURN;
            END;

            IF @ParkingType = 'D'
            BEGIN
                SELECT
                    @Amount = P.VPP_AMOUNT,
                    @PaymentID = P.VPP_PAYMENT_ID,
                    @PaymentNumber = P.VPP_PAYMENT_NUMBER,
                    @ReceiptNumber = P.VPP_RECEIPT_NUMBER
                FROM dbo.VPMS_PARKING_PAYMENT AS P
                INNER JOIN dbo.VPMS_PARKING_TICKET AS T
                    ON T.VPT_TICKET_ID = P.VPP_TICKET_ID
                WHERE P.VPP_TICKET_ID = @p_ticketID
                  AND P.VPP_PAYMENT_STATUS = 'C'
                  AND P.VPP_AMOUNT = T.VPT_CALCULATED_AMOUNT;

                IF @@ROWCOUNT = 0
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @StartedTransaction = 0;
                    SET @ResultStatusCode = -1;
                    SET @Result = 'A matching completed payment is required before exit';
                    RETURN;
                END;

                SET @Result = 'Daily vehicle exited successfully';
            END
            ELSE IF @ParkingType = 'M'
            BEGIN
                IF NOT EXISTS
                (
                    SELECT 1
                    FROM dbo.VPMS_PARKING_TICKET AS T
                    INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                        ON MC.VPM_CONTRACT_ID = T.VPT_MONTHLY_CONTRACT_ID
                       AND MC.VPM_VEHICLE_ID = T.VPT_VEHICLE_ID
                    INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                        ON MP.VPP_CONTRACT_ID = MC.VPM_CONTRACT_ID
                    INNER JOIN dbo.VPMS_MONTHLY_RESERVATION AS R
                        ON R.VPR_MONTHLY_PAYMENT_ID = MP.VPP_MONTHLY_PAYMENT_ID
                       AND R.VPR_SPACE_ID = T.VPT_SPACE_ID
                    WHERE T.VPT_TICKET_ID = @p_ticketID
                      AND MC.VPM_START_DATE <= CONVERT(DATE, DATEADD(MINUTE, 330, T.VPT_ENTRY_DATE_TIME))
                      AND MC.VPM_END_DATE >= CONVERT(DATE, DATEADD(MINUTE, 330, T.VPT_ENTRY_DATE_TIME))
                      AND MP.VPP_PAYMENT_STATUS = 'C'
                      AND R.VPR_EFFECTIVE_FROM_UTC <= T.VPT_ENTRY_DATE_TIME
                      AND R.VPR_EFFECTIVE_TO_UTC > T.VPT_ENTRY_DATE_TIME
                )
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @StartedTransaction = 0;
                    SET @ResultStatusCode = -1;
                    SET @Result = 'Completed monthly payment coverage for this entry was not found';
                    RETURN;
                END;

                SET @Amount = 0;
                SET @Result = 'Monthly vehicle exited successfully';
            END;

            SET @CloseTicket = 1;
        END

        /** Invalid action **/
        ELSE
        BEGIN
            SET @ResultStatusCode = -1;
            SET @Result = 'Invalid action type';
            RETURN;
        END;

        /** Close the ticket and release its space **/
        IF @CloseTicket = 1
        BEGIN
            SET @SpaceStatus = 'AV';

            IF EXISTS
            (
                SELECT 1
                FROM dbo.VPMS_MONTHLY_RESERVATION AS R
                INNER JOIN dbo.VPMS_MONTHLY_PAYMENT AS MP
                    ON MP.VPP_MONTHLY_PAYMENT_ID = R.VPR_MONTHLY_PAYMENT_ID
                INNER JOIN dbo.VPMS_PARKING_MONTHLYCONTRACT AS MC
                    ON MC.VPM_CONTRACT_ID = MP.VPP_CONTRACT_ID
                WHERE R.VPR_SPACE_ID = @SpaceID
                  AND R.VPR_IS_ACTIVE = 'A'
                  AND MP.VPP_PAYMENT_STATUS = 'C'
                  AND MC.VPM_CONTRACT_STATUS = 'A'
                  AND MC.VPM_START_DATE <= @Today
                  AND MC.VPM_END_DATE >= @Today
                  AND R.VPR_EFFECTIVE_FROM_UTC <= @Now
                  AND R.VPR_EFFECTIVE_TO_UTC > @Now
            )
                SET @SpaceStatus = 'RE';

            UPDATE dbo.VPMS_PARKING_TICKET
            SET VPT_EXIT_DATE_TIME = @Now,
                VPT_EXIT_OPERATOR_ID = @p_uid,
                VPT_TICKET_STATUS = 'CL',
                VPT_CALCULATED_AMOUNT =
                    CASE
                        WHEN @ParkingType = 'M' THEN 0
                        ELSE VPT_CALCULATED_AMOUNT
                    END,
                VPT_UPDATED_BY = @p_uid,
                VPT_UPDATED_DATE = @Now
            WHERE VPT_TICKET_ID = @p_ticketID
              AND VPT_EXIT_DATE_TIME IS NULL
              AND
              (
                  (VPT_PARKING_TYPE = 'D' AND VPT_TICKET_STATUS = 'PP')
                  OR (VPT_PARKING_TYPE = 'M' AND VPT_TICKET_STATUS = 'O')
              );

            IF @@ROWCOUNT <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Could not close the parking ticket';
                RETURN;
            END;

            UPDATE dbo.VPMS_PARKING_SPACE
            SET VPS_SPACE_STATUS = @SpaceStatus,
                VPS_UPDATED_BY = @p_uid,
                VPS_UPDATED_DATE = @Now
            WHERE VPS_SPACE_ID = @SpaceID
              AND VPS_SPACE_STATUS = 'OC';

            IF @@ROWCOUNT <> 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @StartedTransaction = 0;
                SET @ResultStatusCode = -1;
                SET @Result = 'Could not release the occupied space';
                RETURN;
            END;
        END;

        IF @StartedTransaction = 1
        BEGIN
            COMMIT TRANSACTION;
            SET @StartedTransaction = 0;
        END;

        SELECT
            @p_ticketID AS VPT_TICKET_ID,
            @TicketNumber AS VPT_TICKET_NUMBER,
            @PaymentID AS VPP_PAYMENT_ID,
            @PaymentNumber AS VPP_PAYMENT_NUMBER,
            @ReceiptNumber AS VPP_RECEIPT_NUMBER,
            @Amount AS VPT_CALCULATED_AMOUNT,
            @SpaceID AS VPT_SPACE_ID,
            @SpaceStatus AS VPS_SPACE_STATUS,
            CASE WHEN @CloseTicket = 1 THEN @Now END AS VPT_EXIT_DATE_TIME;
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