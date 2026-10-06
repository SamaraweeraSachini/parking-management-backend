USE [VehicleParkingManagementDB];
GO

CREATE TABLE dbo.PARKING_RATE
    (
        RateID              INT IDENTITY(1,1) NOT NULL,
        VehicleTypeID       INT NOT NULL,
        RateName            NVARCHAR(100) NOT NULL,
        RateAmount          DECIMAL(12,2) NOT NULL,
        RateUnit            VARCHAR(20) NOT NULL CONSTRAINT DF_PARKING_RATE_RateUnit DEFAULT ('HOURLY'),
        EffectiveFrom       DATETIME2(0) NOT NULL CONSTRAINT DF_PARKING_RATE_EffectiveFrom DEFAULT (SYSUTCDATETIME()),
        EffectiveTo         DATETIME2(0) NULL,
        ActiveStatus        BIT NOT NULL CONSTRAINT DF_PARKING_RATE_ActiveStatus DEFAULT (1),

        CreatedAt           DATETIME2(0) NOT NULL CONSTRAINT DF_PARKING_RATE_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy           INT NULL,
        UpdatedAt           DATETIME2(0) NULL,
        UpdatedBy           INT NULL,

        CONSTRAINT PK_PARKING_RATE PRIMARY KEY (RateID),
        CONSTRAINT FK_PARKING_RATE_VehicleType FOREIGN KEY (VehicleTypeID)
            REFERENCES dbo.PARKING_VEHICLE_TYPE (VehicleTypeID),
        CONSTRAINT CK_PARKING_RATE_Amount CHECK (RateAmount >= 0),
        CONSTRAINT CK_PARKING_RATE_Unit CHECK (RateUnit IN ('HOURLY', 'DAILY')),
        CONSTRAINT CK_PARKING_RATE_EffectivePeriod CHECK
            (EffectiveTo IS NULL OR EffectiveTo > EffectiveFrom)
    );