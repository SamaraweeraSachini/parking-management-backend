USE [VehicleParkingManagementDB_V2];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO

CREATE TABLE dbo.PARKING_MONTHLY_CONTRACT
(
    ContractID INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_PARKING_MONTHLY_CONTRACT PRIMARY KEY,

    ContractNumber VARCHAR(40) NOT NULL
        CONSTRAINT UQ_PARKING_MONTHLY_CONTRACT_Number UNIQUE,

    CustomerID INT NOT NULL,
    VehicleID INT NOT NULL,
    MonthlyFee DECIMAL(12,2) NOT NULL,

    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL,

    ContractStatus VARCHAR(20) NOT NULL
        CONSTRAINT DF_PARKING_MONTHLY_CONTRACT_Status
        DEFAULT ('ACTIVE'),

    CancelledAt DATETIME2(0) NULL,
    CancelledReason NVARCHAR(500) NULL,

    CreatedAt DATETIME2(0) NOT NULL
        CONSTRAINT DF_PARKING_MONTHLY_CONTRACT_CreatedAt
        DEFAULT (SYSUTCDATETIME()),

    CreatedBy INT NULL,
    UpdatedAt DATETIME2(0) NULL,
    UpdatedBy INT NULL,

    CONSTRAINT CK_PARKING_MONTHLY_CONTRACT_Fee
        CHECK (MonthlyFee >= 0),

    CONSTRAINT CK_PARKING_MONTHLY_CONTRACT_Dates
        CHECK (EndDate >= StartDate),

    CONSTRAINT CK_PARKING_MONTHLY_CONTRACT_Status
        CHECK
        (
            ContractStatus IN ('ACTIVE', 'EXPIRED', 'CANCELLED')
        ),

    CONSTRAINT CK_PARKING_MONTHLY_CONTRACT_Cancellation
        CHECK
        (
            (
                ContractStatus <> 'CANCELLED'
                AND CancelledAt IS NULL
                AND CancelledReason IS NULL
            )
            OR
            (
                ContractStatus = 'CANCELLED'
                AND CancelledAt IS NOT NULL
                AND CancelledReason IS NOT NULL
                AND LEN(LTRIM(RTRIM(CancelledReason))) > 0
            )
        ),

    CONSTRAINT FK_PARKING_MONTHLY_CONTRACT_Customer
        FOREIGN KEY (CustomerID)
        REFERENCES dbo.PARKING_CUSTOMER(CustomerID),

    CONSTRAINT FK_PARKING_MONTHLY_CONTRACT_Vehicle
        FOREIGN KEY (VehicleID)
        REFERENCES dbo.PARKING_CUSTOMER_VEHICLE(VehicleID),

    CONSTRAINT FK_PARKING_MONTHLY_CONTRACT_CreatedBy
        FOREIGN KEY (CreatedBy)
        REFERENCES dbo.PARKING_USER(UserID),

    CONSTRAINT FK_PARKING_MONTHLY_CONTRACT_UpdatedBy
        FOREIGN KEY (UpdatedBy)
        REFERENCES dbo.PARKING_USER(UserID)
);
GO

CREATE UNIQUE INDEX UX_PARKING_MONTHLY_CONTRACT_ActiveVehicle
    ON dbo.PARKING_MONTHLY_CONTRACT(VehicleID)
    WHERE ContractStatus = 'ACTIVE';
GO

CREATE INDEX IX_PARKING_MONTHLY_CONTRACT_Customer
    ON dbo.PARKING_MONTHLY_CONTRACT
    (
        CustomerID,
        ContractStatus,
        EndDate
    );
GO

CREATE SEQUENCE dbo.PARKING_CONTRACT_SEQUENCE
    AS BIGINT
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;
GO