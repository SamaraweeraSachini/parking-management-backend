USE [VehicleParkingManagementDB_V2];
GO

CREATE TABLE dbo.PARKING_APP_SETTINGS
(
    SettingsID INT NOT NULL
        CONSTRAINT PK_PARKING_APP_SETTINGS PRIMARY KEY,

    FacilityName NVARCHAR(100) NOT NULL,
    Address NVARCHAR(300) NULL,
    ContactNumber NVARCHAR(30) NULL,
    ReceiptMessage NVARCHAR(300) NOT NULL,

    DailyThresholdHours INT NOT NULL
        CONSTRAINT DF_PARKING_APP_SETTINGS_Threshold DEFAULT (6),

    MonthlyCapacityPercentage DECIMAL(5,2) NULL,

    UpdatedAt DATETIME2(0) NULL,
    UpdatedBy INT NULL,

    CONSTRAINT CK_PARKING_APP_SETTINGS_Singleton
        CHECK (SettingsID = 1),

    CONSTRAINT CK_PARKING_APP_SETTINGS_Name
        CHECK (LEN(LTRIM(RTRIM(FacilityName))) > 0),

    CONSTRAINT CK_PARKING_APP_SETTINGS_ReceiptMessage
        CHECK (LEN(LTRIM(RTRIM(ReceiptMessage))) > 0),

    CONSTRAINT CK_PARKING_APP_SETTINGS_Threshold
        CHECK (DailyThresholdHours BETWEEN 1 AND 24),

    CONSTRAINT CK_PARKING_APP_SETTINGS_MonthlyCapacity
        CHECK
        (
            MonthlyCapacityPercentage IS NULL
            OR MonthlyCapacityPercentage BETWEEN 0 AND 100
        ),

    CONSTRAINT FK_PARKING_APP_SETTINGS_UpdatedBy
        FOREIGN KEY (UpdatedBy)
        REFERENCES dbo.PARKING_USER(UserID)
);
GO

INSERT dbo.PARKING_APP_SETTINGS
(
    SettingsID,
    FacilityName,
    ReceiptMessage,
    DailyThresholdHours,
    MonthlyCapacityPercentage
)
VALUES
(
    1,
    N'Vehicle Parking',
    N'Thank you for parking with us.',
    6,
    NULL
);
GO