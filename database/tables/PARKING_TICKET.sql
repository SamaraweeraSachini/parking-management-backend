USE [VehicleParkingManagementDB];
GO

CREATE TABLE dbo.PARKING_TICKET
    (
        TicketID            INT IDENTITY(1,1) NOT NULL,
        TicketNumber        VARCHAR(40) NOT NULL,
        VehicleID           INT NOT NULL,
        SpaceID             INT NOT NULL,
        HourlyRateID        INT NULL,
        DailyRateID         INT NULL,
        MonthlyContractID   INT NULL,
        ParkingType         VARCHAR(20) NOT NULL,
        EntryDateTime       DATETIME2(0) NOT NULL CONSTRAINT DF_PARKING_TICKET_EntryDateTime DEFAULT (SYSUTCDATETIME()),
        ExitDateTime        DATETIME2(0) NULL,
        AppliedHourlyRate   DECIMAL(12,2) NULL,
        AppliedDailyRate    DECIMAL(12,2) NULL,
        BillableHours       DECIMAL(10,2) NULL,
        CalculatedAmount    DECIMAL(12,2) NULL,
        TicketStatus        VARCHAR(30) NOT NULL CONSTRAINT DF_PARKING_TICKET_Status DEFAULT ('OPEN'),
        EntryOperatorID     INT NOT NULL,
        ExitOperatorID      INT NULL,

        CreatedAt           DATETIME2(0) NOT NULL CONSTRAINT DF_PARKING_TICKET_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy           INT NULL,
        UpdatedAt           DATETIME2(0) NULL,
        UpdatedBy           INT NULL,

        CONSTRAINT PK_PARKING_TICKET PRIMARY KEY (TicketID),
        CONSTRAINT UQ_PARKING_TICKET_Number UNIQUE (TicketNumber),
        CONSTRAINT FK_PARKING_TICKET_Vehicle FOREIGN KEY (VehicleID)
            REFERENCES dbo.PARKING_CUSTOMER_VEHICLE (VehicleID),
        CONSTRAINT FK_PARKING_TICKET_Space FOREIGN KEY (SpaceID)
            REFERENCES dbo.PARKING_SPACE (SpaceID),
        CONSTRAINT FK_PARKING_TICKET_HourlyRate FOREIGN KEY (HourlyRateID)
            REFERENCES dbo.PARKING_RATE (RateID),
        CONSTRAINT FK_PARKING_TICKET_DailyRate FOREIGN KEY (DailyRateID)
            REFERENCES dbo.PARKING_RATE (RateID),
        CONSTRAINT FK_PARKING_TICKET_MonthlyContract FOREIGN KEY (MonthlyContractID)
            REFERENCES dbo.PARKING_MONTHLY_CONTRACT (ContractID),
        CONSTRAINT FK_PARKING_TICKET_EntryOperator FOREIGN KEY (EntryOperatorID)
            REFERENCES dbo.PARKING_USER (UserID),
        CONSTRAINT FK_PARKING_TICKET_ExitOperator FOREIGN KEY (ExitOperatorID)
            REFERENCES dbo.PARKING_USER (UserID),
        CONSTRAINT CK_PARKING_TICKET_Type CHECK (ParkingType IN ('DAILY', 'MONTHLY')),
        CONSTRAINT CK_PARKING_TICKET_Status CHECK
            (TicketStatus IN ('OPEN', 'PAYMENT_PENDING', 'CLOSED', 'CANCELLED')),
        CONSTRAINT CK_PARKING_TICKET_ExitTime CHECK
            (ExitDateTime IS NULL OR ExitDateTime >= EntryDateTime),
        CONSTRAINT CK_PARKING_TICKET_ExitOperator CHECK
        (
            (ExitDateTime IS NULL AND ExitOperatorID IS NULL)
            OR
            (ExitDateTime IS NOT NULL AND ExitOperatorID IS NOT NULL)
        ),
        CONSTRAINT CK_PARKING_TICKET_BillableHours CHECK
            (BillableHours IS NULL OR BillableHours >= 0),
        CONSTRAINT CK_PARKING_TICKET_Amount CHECK
            (CalculatedAmount IS NULL OR CalculatedAmount >= 0),
        CONSTRAINT CK_PARKING_TICKET_RateAmounts CHECK
            ((AppliedHourlyRate IS NULL OR AppliedHourlyRate >= 0)
             AND (AppliedDailyRate IS NULL OR AppliedDailyRate >= 0)),
        CONSTRAINT CK_PARKING_TICKET_DailyOrMonthly CHECK
        (
            (ParkingType = 'DAILY'
             AND MonthlyContractID IS NULL
             AND HourlyRateID IS NOT NULL AND DailyRateID IS NOT NULL
             AND AppliedHourlyRate IS NOT NULL AND AppliedDailyRate IS NOT NULL)
            OR
            (ParkingType = 'MONTHLY'
             AND MonthlyContractID IS NOT NULL
             AND HourlyRateID IS NULL AND DailyRateID IS NULL
             AND AppliedHourlyRate IS NULL AND AppliedDailyRate IS NULL)
        )
    );
GO
