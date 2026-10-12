USE [VehicleParkingManagementDB_V2];
GO

CREATE TABLE dbo.PARKING_USER
(
    UserID INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_PARKING_USER PRIMARY KEY,

    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,

    FullName AS LTRIM(RTRIM(CONCAT(FirstName, N' ', LastName))),

    Username NVARCHAR(100) NOT NULL CONSTRAINT UQ_PARKING_USER_Username UNIQUE,

    PasswordHash NVARCHAR(500) NOT NULL,
    UserRole CHAR(1) NOT NULL,

    ActiveStatus BIT NOT NULL CONSTRAINT DF_PARKING_USER_Active DEFAULT (1),

    CreatedAt DATETIME2(0) NOT NULL
        CONSTRAINT DF_PARKING_USER_CreatedAt
        DEFAULT (SYSUTCDATETIME()),

    CreatedBy INT NULL,
    UpdatedAt DATETIME2(0) NULL,
    UpdatedBy INT NULL,

    CONSTRAINT CK_PARKING_USER_Role CHECK (UserRole IN ('A', 'O')),

    CONSTRAINT CK_PARKING_USER_Name
        CHECK
        (
            LEN(LTRIM(RTRIM(FirstName))) > 0
            AND LEN(LTRIM(RTRIM(LastName))) > 0
        ),

    CONSTRAINT CK_PARKING_USER_Username
        CHECK (LEN(LTRIM(RTRIM(Username))) > 0),

    CONSTRAINT CK_PARKING_USER_PasswordHash
        CHECK (LEN(LTRIM(RTRIM(PasswordHash))) > 0),

    CONSTRAINT FK_PARKING_USER_CreatedBy
        FOREIGN KEY (CreatedBy)
        REFERENCES dbo.PARKING_USER(UserID),

    CONSTRAINT FK_PARKING_USER_UpdatedBy
        FOREIGN KEY (UpdatedBy)
        REFERENCES dbo.PARKING_USER(UserID)
);
GO