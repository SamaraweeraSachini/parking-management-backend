USE [VehicleParkingManagementDB];
GO

CREATE TABLE dbo.PARKING_MONTHLY_CONTRACT
    (
        ContractID          INT IDENTITY(1,1) NOT NULL,
        ContractNumber      VARCHAR(40) NOT NULL,
        CustomerID          INT NOT NULL,
        VehicleID           INT NOT NULL,
        MonthlyFee          DECIMAL(12,2) NOT NULL,
        StartDate           DATE NOT NULL,
        EndDate             DATE NOT NULL,
        ContractStatus      VARCHAR(20) NOT NULL CONSTRAINT DF_PARKING_MONTHLY_CONTRACT_Status DEFAULT ('ACTIVE'),
        CancelledAt         DATETIME2(0) NULL,
        CancellationReason NVARCHAR(500) NULL,

        CreatedAt           DATETIME2(0) NOT NULL CONSTRAINT DF_PARKING_MONTHLY_CONTRACT_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy           INT NULL,
        UpdatedAt           DATETIME2(0) NULL,
        UpdatedBy           INT NULL,

        CONSTRAINT PK_PARKING_MONTHLY_CONTRACT PRIMARY KEY (ContractID),
        CONSTRAINT UQ_PARKING_MONTHLY_CONTRACT_Number UNIQUE (ContractNumber),
        CONSTRAINT FK_PARKING_MONTHLY_CONTRACT_Customer FOREIGN KEY (CustomerID)
            REFERENCES dbo.PARKING_CUSTOMER (CustomerID),
        CONSTRAINT FK_PARKING_MONTHLY_CONTRACT_Vehicle FOREIGN KEY (VehicleID)
            REFERENCES dbo.PARKING_CUSTOMER_VEHICLE (VehicleID),
        CONSTRAINT CK_PARKING_MONTHLY_CONTRACT_Fee CHECK (MonthlyFee >= 0),
        CONSTRAINT CK_PARKING_MONTHLY_CONTRACT_Dates CHECK (EndDate >= StartDate),
        CONSTRAINT CK_PARKING_MONTHLY_CONTRACT_Status CHECK
            (ContractStatus IN ('ACTIVE', 'EXPIRED', 'CANCELLED')),
        CONSTRAINT CK_PARKING_MONTHLY_CONTRACT_Cancellation CHECK
        (
            (ContractStatus <> 'CANCELLED' AND CancelledAt IS NULL)
            OR
            (ContractStatus = 'CANCELLED' AND CancelledAt IS NOT NULL)
        )
    );