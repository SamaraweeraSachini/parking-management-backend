USE [VPMS_001_DB];
GO

CREATE TABLE dbo.VPMS_USER_ROLE
(
	VPR_ROLE_ID INT IDENTITY(1,1) NOT NULL,
    VPR_ROLE_CODE  VARCHAR(2)   NOT NULL,
    VPR_ROLE_NAME  VARCHAR(50)  NOT NULL,
    VPR_DESCRIPTION VARCHAR(200) NULL,

    CONSTRAINT PK_VPMS_USER_ROLE
        PRIMARY KEY (VPR_ROLE_CODE),

	CONSTRAINT UQ_VPMS_PARKINGUSER_ROLE_ID
        UNIQUE (VPR_ROLE_ID),

    CONSTRAINT UQ_VPMS_USER_ROLE_NAME
        UNIQUE (VPR_ROLE_NAME)
);
GO

INSERT INTO dbo.VPMS_USER_ROLE
  (VPR_ROLE_CODE, VPR_ROLE_NAME, VPR_DESCRIPTION)
VALUES
    ('AD', 'Administrator', 'Manages the parking system'),
    ('OP', 'Operator',      'Operates the parking system'),
    ('CU', 'Customer',      'Uses parking services');
GO