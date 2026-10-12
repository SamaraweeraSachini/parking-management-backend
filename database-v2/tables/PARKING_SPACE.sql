USE [VehicleParkingManagementDB_V2];
GO

CREATE TABLE dbo.PARKING_SPACE
(
    SpaceID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PARKING_SPACE PRIMARY KEY,

    VehicleTypeID INT NOT NULL,

    SpaceCode VARCHAR(30) NOT NULL CONSTRAINT UQ_PARKING_SPACE_Code UNIQUE,

    SpaceName NVARCHAR(100) NULL,

    SpaceStatus VARCHAR(20) NOT NULL
        CONSTRAINT DF_PARKING_SPACE_Status DEFAULT ('AVAILABLE'),

    BlockReason NVARCHAR(500) NULL,

    ActiveStatus BIT NOT NULL CONSTRAINT DF_PARKING_SPACE_Active DEFAULT (1),

    CreatedAt DATETIME2(0) NOT NULL
        CONSTRAINT DF_PARKING_SPACE_CreatedAt
        DEFAULT (SYSUTCDATETIME()),

    CreatedBy INT NULL,
    UpdatedAt DATETIME2(0) NULL,
    UpdatedBy INT NULL,

    CONSTRAINT CK_PARKING_SPACE_Code
        CHECK (LEN(LTRIM(RTRIM(SpaceCode))) > 0),

    CONSTRAINT CK_PARKING_SPACE_Status
        CHECK
        (
            SpaceStatus IN ('AVAILABLE', 'OCCUPIED', 'BLOCKED', 'RESERVED')
        ),

    CONSTRAINT CK_PARKING_SPACE_BlockReason
        CHECK
        (
            (
                SpaceStatus = 'BLOCKED'
                AND BlockReason IS NOT NULL
                AND LEN(LTRIM(RTRIM(BlockReason))) > 0
            )
            OR
            (
                SpaceStatus <> 'BLOCKED'
                AND BlockReason IS NULL
            )
        ),

    CONSTRAINT FK_PARKING_SPACE_VehicleType
        FOREIGN KEY (VehicleTypeID)
        REFERENCES dbo.PARKING_VEHICLE_TYPE(VehicleTypeID),

    CONSTRAINT FK_PARKING_SPACE_CreatedBy
        FOREIGN KEY (CreatedBy)
        REFERENCES dbo.PARKING_USER(UserID),

    CONSTRAINT FK_PARKING_SPACE_UpdatedBy
        FOREIGN KEY (UpdatedBy)
        REFERENCES dbo.PARKING_USER(UserID)
);
GO

CREATE INDEX IX_PARKING_SPACE_Allocation
    ON dbo.PARKING_SPACE
    (
        VehicleTypeID,
        ActiveStatus,
        SpaceStatus
    );
GO