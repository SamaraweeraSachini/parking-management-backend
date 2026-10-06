USE [VehicleParkingManagementDB];
GO

CREATE TABLE dbo.PARKING_USER
    (
        UserID              INT IDENTITY(1,1) NOT NULL,
        FirstName           NVARCHAR(100) NOT NULL,
        LastName            NVARCHAR(100) NOT NULL,
        FullName            AS LTRIM(RTRIM(CONCAT(FirstName, N' ', LastName))),
        Username            NVARCHAR(100) NOT NULL,
        PasswordHash        NVARCHAR(500) NOT NULL,
        UserRole            CHAR(1) NOT NULL,
        ActiveStatus        BIT NOT NULL CONSTRAINT DF_PARKING_USER_ActiveStatus DEFAULT (1),

        CreatedAt           DATETIME2(0) NOT NULL CONSTRAINT DF_PARKING_USER_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy           INT NULL,
        UpdatedAt           DATETIME2(0) NULL,
        UpdatedBy           INT NULL,

        CONSTRAINT PK_PARKING_USER PRIMARY KEY (UserID),
        CONSTRAINT UQ_PARKING_USER_Username UNIQUE (Username),
        CONSTRAINT CK_PARKING_USER_UserRole CHECK (UserRole IN ('A', 'O')),
        CONSTRAINT CK_PARKING_USER_Name CHECK
        (
            LEN(LTRIM(RTRIM(FirstName))) > 0
            AND LEN(LTRIM(RTRIM(LastName))) > 0
        )
    );