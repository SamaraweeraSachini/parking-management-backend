USE [VehicleParkingManagementDB];
GO

CREATE TABLE dbo.PARKING_VEHICLE_TYPE
    (
        VehicleTypeID       INT IDENTITY(1,1) NOT NULL,
        TypeName            NVARCHAR(100) NOT NULL,
        Description         NVARCHAR(500) NULL,
        ActiveStatus        BIT NOT NULL CONSTRAINT DF_PARKING_VEHICLE_TYPE_ActiveStatus DEFAULT (1),

        CreatedAt           DATETIME2(0) NOT NULL CONSTRAINT DF_PARKING_VEHICLE_TYPE_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy           INT NULL,
        UpdatedAt           DATETIME2(0) NULL,
        UpdatedBy           INT NULL,

        CONSTRAINT PK_PARKING_VEHICLE_TYPE PRIMARY KEY (VehicleTypeID),
        CONSTRAINT UQ_PARKING_VEHICLE_TYPE_TypeName UNIQUE (TypeName),
        CONSTRAINT CK_PARKING_VEHICLE_TYPE_TypeName CHECK (LEN(LTRIM(RTRIM(TypeName))) > 0)
    );