USE [VehicleParkingManagementDB];
GO

CREATE TABLE dbo.PARKING_CUSTOMER
    (
        CustomerID          INT IDENTITY(1,1) NOT NULL,
        CustomerName        NVARCHAR(200) NOT NULL,
        MobileNumber        VARCHAR(20) NOT NULL,
        EmailAddress        NVARCHAR(254) NULL,
        Address             NVARCHAR(500) NULL,
        RegisteredDate      DATETIME2(0) NOT NULL CONSTRAINT DF_PARKING_CUSTOMER_RegisteredDate DEFAULT (SYSUTCDATETIME()),
        ActiveStatus        BIT NOT NULL CONSTRAINT DF_PARKING_CUSTOMER_ActiveStatus DEFAULT (1),

        CreatedAt           DATETIME2(0) NOT NULL CONSTRAINT DF_PARKING_CUSTOMER_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy           INT NULL,
        UpdatedAt           DATETIME2(0) NULL,
        UpdatedBy           INT NULL,

        CONSTRAINT PK_PARKING_CUSTOMER PRIMARY KEY (CustomerID),
        CONSTRAINT CK_PARKING_CUSTOMER_Name CHECK (LEN(LTRIM(RTRIM(CustomerName))) > 0),
        CONSTRAINT CK_PARKING_CUSTOMER_Mobile CHECK (LEN(LTRIM(RTRIM(MobileNumber))) BETWEEN 7 AND 20)
    );