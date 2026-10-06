USE [VehicleParkingManagementDB];
GO

CREATE TABLE dbo.PARKING_CUSTOMER_VEHICLE
    (
        VehicleID           INT IDENTITY(1,1) NOT NULL,
        CustomerID          INT NULL,
        VehicleTypeID       INT NOT NULL,
        VehicleNumber       VARCHAR(30) NOT NULL,
        VehicleMake         NVARCHAR(100) NULL,
        VehicleModel        NVARCHAR(100) NULL,
        VehicleColour       NVARCHAR(50) NULL,
        ActiveStatus        BIT NOT NULL CONSTRAINT DF_PARKING_CUSTOMER_VEHICLE_ActiveStatus DEFAULT (1),

        CreatedAt           DATETIME2(0) NOT NULL CONSTRAINT DF_PARKING_CUSTOMER_VEHICLE_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy           INT NULL,
        UpdatedAt           DATETIME2(0) NULL,
        UpdatedBy           INT NULL,

        CONSTRAINT PK_PARKING_CUSTOMER_VEHICLE PRIMARY KEY (VehicleID),
        CONSTRAINT UQ_PARKING_CUSTOMER_VEHICLE_VehicleNumber UNIQUE (VehicleNumber),
        CONSTRAINT FK_PARKING_CUSTOMER_VEHICLE_Customer FOREIGN KEY (CustomerID)
            REFERENCES dbo.PARKING_CUSTOMER (CustomerID),
        CONSTRAINT FK_PARKING_CUSTOMER_VEHICLE_VehicleType FOREIGN KEY (VehicleTypeID)
            REFERENCES dbo.PARKING_VEHICLE_TYPE (VehicleTypeID),
        CONSTRAINT CK_PARKING_CUSTOMER_VEHICLE_Number CHECK
            (LEN(LTRIM(RTRIM(VehicleNumber))) > 0)
    );