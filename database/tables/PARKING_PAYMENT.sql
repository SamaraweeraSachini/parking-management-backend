USE [VehicleParkingManagementDB];
GO

CREATE TABLE dbo.PARKING_PAYMENT
    (
        PaymentID           INT IDENTITY(1,1) NOT NULL,
        PaymentNumber       VARCHAR(40) NOT NULL,
        TicketID            INT NOT NULL,
        Amount              DECIMAL(12,2) NOT NULL,
        PaymentMethod       VARCHAR(20) NOT NULL,
        PaymentStatus       VARCHAR(20) NOT NULL CONSTRAINT DF_PARKING_PAYMENT_Status DEFAULT ('COMPLETED'),
        PaymentDateTime     DATETIME2(0) NOT NULL CONSTRAINT DF_PARKING_PAYMENT_DateTime DEFAULT (SYSUTCDATETIME()),
        ReceivedByUserID    INT NOT NULL,
        ReceiptNumber       VARCHAR(40) NOT NULL,
        Remarks             NVARCHAR(500) NULL,

        CreatedAt           DATETIME2(0) NOT NULL CONSTRAINT DF_PARKING_PAYMENT_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy           INT NULL,
        UpdatedAt           DATETIME2(0) NULL,
        UpdatedBy           INT NULL,

        CONSTRAINT PK_PARKING_PAYMENT PRIMARY KEY (PaymentID),
        CONSTRAINT UQ_PARKING_PAYMENT_Number UNIQUE (PaymentNumber),
        CONSTRAINT UQ_PARKING_PAYMENT_Receipt UNIQUE (ReceiptNumber),
        CONSTRAINT UQ_PARKING_PAYMENT_Ticket UNIQUE (TicketID),
        CONSTRAINT FK_PARKING_PAYMENT_Ticket FOREIGN KEY (TicketID)
            REFERENCES dbo.PARKING_TICKET (TicketID),
        CONSTRAINT FK_PARKING_PAYMENT_ReceivedBy FOREIGN KEY (ReceivedByUserID)
            REFERENCES dbo.PARKING_USER (UserID),
        CONSTRAINT CK_PARKING_PAYMENT_Amount CHECK (Amount >= 0),
        CONSTRAINT CK_PARKING_PAYMENT_Method CHECK
            (PaymentMethod IN ('CASH', 'CARD')),
        CONSTRAINT CK_PARKING_PAYMENT_Status CHECK
            (PaymentStatus IN ('COMPLETED', 'CANCELLED', 'REFUNDED'))
    );