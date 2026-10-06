USE [VehicleParkingManagementDB];
GO

CREATE TABLE dbo.PARKING_SPACE
    (
        SpaceID             INT IDENTITY(1,1) NOT NULL,
        VehicleTypeID       INT NOT NULL,
        SpaceCode           VARCHAR(30) NOT NULL,
        SpaceName           NVARCHAR(100) NULL,
        SpaceStatus         VARCHAR(20) NOT NULL CONSTRAINT DF_PARKING_SPACE_SpaceStatus DEFAULT ('AVAILABLE'),
        ActiveStatus        BIT NOT NULL CONSTRAINT DF_PARKING_SPACE_ActiveStatus DEFAULT (1),

        CreatedAt           DATETIME2(0) NOT NULL CONSTRAINT DF_PARKING_SPACE_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy           INT NULL,
        UpdatedAt           DATETIME2(0) NULL,
        UpdatedBy           INT NULL,

        CONSTRAINT PK_PARKING_SPACE PRIMARY KEY (SpaceID),
        CONSTRAINT UQ_PARKING_SPACE_SpaceCode UNIQUE (SpaceCode),
        CONSTRAINT FK_PARKING_SPACE_VehicleType FOREIGN KEY (VehicleTypeID)
            REFERENCES dbo.PARKING_VEHICLE_TYPE (VehicleTypeID),
        CONSTRAINT CK_PARKING_SPACE_SpaceCode CHECK (LEN(LTRIM(RTRIM(SpaceCode))) > 0),
        CONSTRAINT CK_PARKING_SPACE_SpaceStatus CHECK
            (SpaceStatus IN ('AVAILABLE', 'OCCUPIED', 'BLOCKED'))
    );