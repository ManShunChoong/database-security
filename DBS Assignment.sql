/*
# Reset
*/

-- USE master;

-- DROP DATABASE [APU Bus Services];

-- DROP CERTIFICATE TDECert_BusService;

-- DROP LOGIN AnalystDeptHead;
-- DROP LOGIN ServicesDeptHead;
-- DROP LOGIN DatabaseAdmin1;
-- DROP LOGIN Scheduler1;
-- DROP LOGIN Scheduler2;
-- DROP LOGIN Student1;
-- DROP LOGIN Student2;
-- DROP LOGIN Student3;

-- DROP TRIGGER AuditLogon ON ALL SERVER;
-- DROP TRIGGER LimitConnectionAfterOfficeHours ON ALL SERVER;
-- DROP TRIGGER LimitManagementLoginHours ON ALL SERVER;
-- DROP TRIGGER LimitSessions ON ALL SERVER;
-- DROP TRIGGER LimitStudentLoginHours ON ALL SERVER;
-- DROP TRIGGER LimitStudentSessions ON ALL SERVER;
-- DROP TRIGGER MyHostsOnly ON ALL SERVER;

/*
# Create Database
*/

CREATE DATABASE [APU Bus Services];

/*
# Implement Transparent Data Encryption (TDE)
*/

/*
## Chew Cheng Yong TP051338
*/

USE master;

CREATE CERTIFICATE TDECert_BusService 
WITH SUBJECT ='TDECert_BusService';

USE [APU Bus Services];

CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256
ENCRYPTION BY SERVER CERTIFICATE TDECert_BusService;

ALTER DATABASE [APU Bus Services] SET ENCRYPTION ON;

/*
## Wong Poh Yee TP051079
*/

-- USE master;

-- CREATE ASYMMETRIC KEY APUServicesKey
-- WITH ALGORITHM = RSA_2048
-- ENCRYPTION BY PASSWORD = 'Passw0rd';

-- USE [APU Bus Services];

-- CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256
-- ENCRYPTION BY SERVER ASYMMETRIC KEY APUServicesKey;

-- ALTER DATABASE [APU Bus Services] SET ENCRYPTION ON;

/*
# Use Database
*/

USE [APU Bus Services];

/*
# Create Schemas
*/

CREATE SCHEMA Management;

CREATE SCHEMA BusUser;

/*
# Create DDL Triggers
*/

/*
## Chew Cheng Yong TP051338
*/

CREATE TABLE Management.AuditLog_DDL (
    AuditLogID INT IDENTITY(1, 1) NOT NULL,
    LogDate DATETIME DEFAULT GETDATE() NOT NULL,
    UserName SYSNAME DEFAULT USER_NAME() NOT NULL,
    SQLCmd NVARCHAR(max)
);

CREATE or ALTER TRIGGER AuditChange
ON DATABASE
FOR 
    CREATE_TABLE, 
    ALTER_TABLE, 
    DROP_TABLE, 
    CREATE_VIEW, 
    ALTER_VIEW, 
    DROP_VIEW
AS 
	IF (IS_MEMBER('DatabaseAdmins') = 1)
    BEGIN
        DECLARE @SQLCmd NVARCHAR(MAX);
        SELECT @SQLCmd = EVENTDATA().value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)');
        INSERT INTO Management.AuditLog_DDL (SQLCmd) VALUES(@SQLCmd);
    END
    ELSE
    BEGIN
        PRINT 'ERROR: Current user does not have permission to CREATE/DROP/ALTER!!';
        ROLLBACK;
    END;

CREATE or ALTER TRIGGER AuditChange
ON DATABASE
FOR 
    CREATE_TABLE, 
    ALTER_TABLE, 
    DROP_TABLE, 
    CREATE_VIEW, 
    ALTER_VIEW, 
    DROP_VIEW
AS 
BEGIN
    DECLARE @SQLCmd NVARCHAR(MAX);
    SELECT @SQLCmd = EVENTDATA().value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)');
    INSERT INTO Management.AuditLog_DDL (SQLCmd) VALUES(@SQLCmd);
END;

--only database administrator can drop table, however, there are several tables that cannot be deleted
CREATE OR ALTER TRIGGER NoDropTable
ON DATABASE
FOR DROP_TABLE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Schema SYSNAME = EVENTDATA().value('(/EVENT_INSTANCE/SchemaName)[1]', 'sysname');
    DECLARE @Table SYSNAME = EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname');

    IF IS_MEMBER('DatabaseAdmins') = 1
    BEGIN
	    IF @Schema IN ('Management','BusUser') 
        AND @Table IN ('Reservation', 'BusStatus', 'Bus', 'Student', 'Route', 'Schedule', 'Station', 'TimeSlot')
			BEGIN
				PRINT 'ERROR: [' + @Schema + '].[' + @Table + '] cannot be dropped.';
				ROLLBACK;
			END
	    ELSE
			BEGIN
				INSERT INTO Management.AuditTable (
					Event_Data,
					ChangedBy,
					ChangedOn
				)
				VALUES (
					EVENTDATA(),
					USER,
					GETDATE()
				);
			END
    END
END;

CREATE OR ALTER TRIGGER NoCreate
ON DATABASE
FOR 
	CREATE_TABLE,
    CREATE_VIEW
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Schema SYSNAME = EVENTDATA().value('(/EVENT_INSTANCE/SchemaName)[1]', 'sysname');
    IF (IS_MEMBER('DatabaseAdmins') = 1)
    BEGIN
        IF @Schema IN ('Management','BusUser') 
        BEGIN
            INSERT INTO Management.AuditTable (
                Event_Data,
                ChangedBy,
                ChangedOn
            )
            VALUES (
                EVENTDATA(),
                USER,
                GETDATE()
            );
        END
        ELSE
        BEGIN
            PRINT 'ERROR: Cannot create table/view outside '+ @Schema;
            ROLLBACK;
        END
    END
END;

/*
## Choong Man Shun TP051283
*/

CREATE OR ALTER TRIGGER DropTableSafety
ON DATABASE
FOR DROP_TABLE
AS
	PRINT 'You must disable trigger DropTableSafety to drop tables.';
	ROLLBACK;

CREATE OR ALTER TRIGGER AlterTableSafety
ON DATABASE
FOR ALTER_TABLE
AS
	PRINT 'You must disable trigger AlterTableSafety to alter tables.';
	ROLLBACK;

/*
# Create Tables
*/

/*
## Wong Poh Yee TP051079
*/

CREATE TABLE Management.Station (
	StationID INT PRIMARY KEY IDENTITY(1, 1),
	Name VARCHAR(200) UNIQUE NOT NULL,
	ShortName VARCHAR(20) UNIQUE NOT NULL
);

CREATE TABLE Management.Route (
	RouteID INT PRIMARY KEY IDENTITY(1, 1),
	DepartureStationID INT REFERENCES Management.Station(StationID) NOT NULL,
	ArrivalStationID INT REFERENCES Management.Station(StationID) NOT NULL,
	Name VARCHAR(200) UNIQUE NOT NULL,
	CONSTRAINT Route_CK1 CHECK (DepartureStationID <> ArrivalStationID)
);

CREATE TABLE Management.TimeSlot (
	TimeSlotID INT PRIMARY KEY IDENTITY(1, 1),
	DepartureDatetime DATETIME NOT NULL,
	ArrivalDatetime DATETIME NOT NULL,
	CONSTRAINT TimeSlot_CK1 CHECK (DepartureDatetime < ArrivalDatetime)
);

/*
## Chew Cheng Yong TP051338
*/

CREATE TABLE Management.BusStatus (
	StatusID INT PRIMARY KEY IDENTITY(1, 1),
	Name VARCHAR(200) UNIQUE NOT NULL
);

CREATE TABLE Management.Bus (
	BusID INT PRIMARY KEY IDENTITY(1, 1),
	PlateNumber VARCHAR(8) UNIQUE NOT NULL CHECK (DATALENGTH(PlateNumber) >= 7),
	Capacity INT NOT NULL CHECK (Capacity > 0),
	StatusID INT REFERENCES Management.BusStatus(StatusID) NOT NULL
);

CREATE TABLE Management.Schedule (
	ScheduleID INT PRIMARY KEY IDENTITY(1, 1),
	RouteID INT REFERENCES Management.Route(RouteID) NOT NULL,
	TimeSlotID INT REFERENCES Management.TimeSlot(TimeSlotID) NOT NULL,
	BusID INT REFERENCES Management.Bus(BusID) NOT NULL,
	AvailableCapacity INT NOT NULL CHECK (AvailableCapacity >= 0)
);

/*
## Choong Man Shun TP051283
*/

CREATE TABLE BusUser.Student (
	StudentID INT PRIMARY KEY IDENTITY(1, 1),
	Name VARCHAR(200) NOT NULL,
	UserName AS CAST(CONCAT('Student', StudentID) 
		AS VARCHAR(200)) PERSISTED UNIQUE NOT NULL,
	Password VARCHAR(200) NOT NULL,
	EncryptedPasswordByKey VARBINARY(1000),
	EncryptedPasswordByCert VARBINARY(1000)
);

CREATE TABLE BusUser.Reservation (
	ReservationID INT PRIMARY KEY IDENTITY(1, 1),
	StudentID INT REFERENCES BusUser.Student(StudentID) NOT NULL,
	ScheduleID INT REFERENCES Management.Schedule(ScheduleID) NOT NULL,
	ConfirmationNumber AS CAST(ReservationID + 100 AS INT) 
		PERSISTED UNIQUE NOT NULL,
	Cancelled BIT NOT NULL DEFAULT 0,
	Datetime DATETIME NOT NULL DEFAULT GETDATE(),
	CONSTRAINT Reservation_AK1 UNIQUE (StudentID, ScheduleID)
);

/*
# Implement Column Level Encryption
*/

/*
## Choong Man Shun TP051283
*/

CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Passw0rd';  

CREATE CERTIFICATE StudentPasswordCertificate 
WITH SUBJECT = 'StudentPassword';

/*
## Wong Poh Yee TP051079
*/

-- CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Passw0rd';

CREATE ASYMMETRIC KEY AsymmetricKey 
WITH ALGORITHM = RSA_2048;

CREATE SYMMETRIC KEY Symmetrickey 
WITH ALGORITHM = AES_256
ENCRYPTION BY ASYMMETRIC KEY AsymmetricKey;

OPEN SYMMETRIC KEY Symmetrickey
DECRYPTION BY ASYMMETRIC KEY AsymmetricKey;

/*
# Create Views
*/

/*
## Wong Poh Yee TP051079
*/

CREATE OR ALTER VIEW Management.[Weekly Reporting]
AS
SELECT ScheduleTable.*, Bookings, Cancellations
FROM (
    SELECT
        Route.Name AS Route, 
        YEAR(TimeSlot.DepartureDatetime) AS Year,
        CONCAT('Week ', DATEPART(ISO_WEEK, TimeSlot.DepartureDatetime)) AS Week,
        COUNT(*) AS Schedules,
        COUNT(CASE WHEN TimeSlot.ArrivalDatetime < GETDATE() THEN 1 END) AS [Completed Trips]
    FROM Management.Schedule
    JOIN Management.Route ON Schedule.RouteID = Route.RouteID
    JOIN Management.TimeSlot ON Schedule.TimeSlotID = TimeSlot.TimeSlotID
    GROUP BY 
        Route.Name, 
        YEAR(TimeSlot.DepartureDatetime),
        DATEPART(ISO_WEEK, TimeSlot.DepartureDatetime)
) AS ScheduleTable 
JOIN (
    SELECT 
        Route.Name AS Route, 
        YEAR(TimeSlot.DepartureDatetime) AS Year,
        CONCAT('Week ', DATEPART(ISO_WEEK, TimeSlot.DepartureDatetime)) AS Week,
        COUNT(CASE WHEN Reservation.Cancelled = 0 THEN 1 END) AS Bookings,
        COUNT(CASE WHEN Reservation.Cancelled = 1 THEN 1 END) AS Cancellations
    FROM Management.Schedule
    JOIN Management.Route ON Schedule.RouteID = Route.RouteID
    JOIN Management.TimeSlot ON Schedule.TimeSlotID = TimeSlot.TimeSlotID
    LEFT JOIN BusUser.Reservation ON Schedule.ScheduleID = Reservation.ScheduleID
    GROUP BY 
        Route.Name, 
        YEAR(TimeSlot.DepartureDatetime),
        DATEPART(ISO_WEEK, TimeSlot.DepartureDatetime)
) AS BookingTable
    ON ScheduleTable.Route = BookingTable.Route 
    AND ScheduleTable.Year = BookingTable.Year
    AND ScheduleTable.Week = BookingTable.Week
ORDER BY Route, Year, Week OFFSET 0 ROWS;

CREATE OR ALTER VIEW Management.[Monthly Reporting]
AS
SELECT ScheduleTable.*, Bookings, Cancellations
FROM (
    SELECT
        Route.Name AS Route, 
        FORMAT(TimeSlot.DepartureDatetime, 'yyyy-MM') AS Month,
        COUNT(*) AS Schedules,
        COUNT(CASE WHEN TimeSlot.ArrivalDatetime < GETDATE() THEN 1 END) AS [Completed Trips]
    FROM Management.Schedule
    JOIN Management.Route ON Schedule.RouteID = Route.RouteID
    JOIN Management.TimeSlot ON Schedule.TimeSlotID = TimeSlot.TimeSlotID
    GROUP BY 
        Route.Name, 
        FORMAT(TimeSlot.DepartureDatetime, 'yyyy-MM')
) AS ScheduleTable 
JOIN (
    SELECT 
        Route.Name AS Route, 
        FORMAT(TimeSlot.DepartureDatetime, 'yyyy-MM') AS Month,
        COUNT(CASE WHEN Reservation.Cancelled = 0 THEN 1 END) AS Bookings,
        COUNT(CASE WHEN Reservation.Cancelled = 1 THEN 1 END) AS Cancellations
    FROM Management.Schedule
    JOIN Management.Route ON Schedule.RouteID = Route.RouteID
    JOIN Management.TimeSlot ON Schedule.TimeSlotID = TimeSlot.TimeSlotID
    LEFT JOIN BusUser.Reservation ON Schedule.ScheduleID = Reservation.ScheduleID
    GROUP BY 
        Route.Name, 
        FORMAT(TimeSlot.DepartureDatetime, 'yyyy-MM')
) AS BookingTable
    ON ScheduleTable.Route = BookingTable.Route 
    AND ScheduleTable.Month = BookingTable.Month
ORDER BY Route, Month OFFSET 0 ROWS;

/*
## Choong Man Shun TP051283
*/

CREATE OR ALTER VIEW BusUser.[Student Profile]
WITH SCHEMABINDING
AS
SELECT 
    StudentID AS [Student ID], 
    Name, 
    UserName,
    EncryptedPasswordByCert AS [Encrypted Password]
FROM BusUser.Student;

CREATE OR ALTER VIEW BusUser.[Bus Availability Checking]
WITH SCHEMABINDING
AS
SELECT 
	ScheduleID AS [Schedule ID],
	Route.Name AS Route,
	CAST(DepartureDatetime AS DATE) AS Date,
	CAST(DepartureDatetime AS TIME) AS [Departure Time],
	CAST(ArrivalDatetime AS TIME) AS [Arrival Time],
	PlateNumber AS [Plate Number],
	CONCAT(AvailableCapacity, '/', Capacity) AS Capacity
FROM Management.Schedule
LEFT JOIN Management.Route
	ON Schedule.RouteID = Route.RouteID
LEFT JOIN Management.TimeSlot
	ON Schedule.TimeSlotID = TimeSlot.TimeSlotID
LEFT JOIN Management.Bus
	ON Schedule.BusID = Bus.BusID
WHERE DepartureDatetime BETWEEN GETDATE() 
AND DATEADD(day, 14, GETDATE())
ORDER BY DepartureDatetime, Route.RouteID OFFSET 0 ROWS;

CREATE OR ALTER VIEW BusUser.[Student Booking]
WITH SCHEMABINDING
AS
SELECT 
	Reservation.StudentID AS [Student ID], 
	Student.Name, 
    UserName,
	ReservationID AS [Reservation ID], 
	ConfirmationNumber AS [Confirmation Number], 
	Cancelled, 
	Datetime AS [Reservation Datetime],
	Reservation.ScheduleID AS [Schedule ID],
	Route.Name AS Route,
	CAST(DepartureDatetime AS DATE) AS Date,
	CAST(DepartureDatetime AS TIME) AS [Departure Time],
	CAST(ArrivalDatetime AS TIME) AS [Arrival Time],
	PlateNumber AS [Plate Number],
	BusStatus.Name AS [Bus Status]
FROM BusUser.Student
JOIN BusUser.Reservation
	ON Student.StudentID = Reservation.StudentID
LEFT JOIN Management.Schedule
	ON Reservation.ScheduleID = Schedule.ScheduleID
LEFT JOIN Management.Route
	ON Schedule.RouteID = Route.RouteID
LEFT JOIN Management.TimeSlot
	ON Schedule.TimeSlotID = TimeSlot.TimeSlotID
LEFT JOIN Management.Bus ON Schedule.BusID = Bus.BusID
LEFT JOIN Management.BusStatus 
	ON Bus.StatusID = BusStatus.StatusID;

CREATE OR ALTER VIEW BusUser.[Student Booking Cancelling]
WITH SCHEMABINDING
AS
SELECT 
	Student.StudentID AS [Student ID], 
	Student.Name, 
    UserName,
	ReservationID AS [Reservation ID], 
	ConfirmationNumber AS [Confirmation Number], 
	Cancelled, 
	Datetime AS [Reservation Datetime],
	Route.Name AS Route,
	DepartureDatetime AS [Departure Datetime],
	ArrivalDatetime AS [Arrival Datetime],
	PlateNumber AS [Plate Number]
FROM BusUser.Student
JOIN BusUser.Reservation
	ON Student.StudentID = Reservation.StudentID
LEFT JOIN Management.Schedule
	ON Reservation.ScheduleID = Schedule.ScheduleID
LEFT JOIN Management.Route
	ON Schedule.RouteID = Route.RouteID
LEFT JOIN Management.TimeSlot
	ON Schedule.TimeSlotID = TimeSlot.TimeSlotID
LEFT JOIN Management.Bus ON Schedule.BusID = Bus.BusID
WHERE DepartureDatetime > GETDATE();

/*
# Create DML Triggers
*/

/*
## Wong Poh Yee TP051079
*/

CREATE TABLE Management.AuditLog_Schedule (
	AuditLogID INT IDENTITY(1, 1) NOT NULL,
	LogDate DATETIME DEFAULT GETDATE(),
	UserName SYSNAME DEFAULT USER_NAME(),
	ScheduleID INT,
	RouteID INT,
	TimeSlotID INT,
	BusID INT,
	AvailableCapacity INT,
	UserAction VARCHAR(20)
)

CREATE or ALTER TRIGGER Management.AuditScheduleChange
ON Management.Schedule
AFTER INSERT, UPDATE, DELETE
AS 
BEGIN
    INSERT INTO Management.AuditLog_Schedule 
    (ScheduleID, RouteID, TimeSlotID, BusID, AvailableCapacity, UserAction)
    SELECT ScheduleID, RouteID, TimeSlotID, BusID, AvailableCapacity, 'INSERT'
    FROM inserted

    INSERT INTO Management.AuditLog_Schedule
    (ScheduleID, RouteID, TimeSlotID, BusID, AvailableCapacity, UserAction)
    SELECT ScheduleID, RouteID, TimeSlotID, BusID, AvailableCapacity, 'DELETE'
    FROM deleted 
END;

CREATE TABLE Management.AuditLog_Route (
	AuditLogID INT IDENTITY(1, 1) NOT NULL,
	LogDate DATETIME DEFAULT GETDATE(),
	UserName SYSNAME DEFAULT USER_NAME(),
	RouteID INT,
	DepartureStationID INT,
	ArrivalStationID INT,
	Name VARCHAR(200),
	UserAction VARCHAR(20)
)

CREATE or ALTER TRIGGER Management.AuditRouteChange
ON Management.Route
AFTER INSERT, UPDATE, DELETE
AS 
BEGIN
    INSERT INTO Management.AuditLog_Route 
    (RouteID, DepartureStationID, ArrivalStationID, Name, UserAction)
    SELECT RouteID, DepartureStationID, ArrivalStationID, Name, 'INSERT'
    FROM inserted

    INSERT INTO Management.AuditLog_Route
    (RouteID, DepartureStationID, ArrivalStationID, Name, UserAction)
    SELECT RouteID, DepartureStationID, ArrivalStationID, Name, 'DELETE'
    FROM deleted 
END;

CREATE TABLE Management.AuditLog_TimeSlot (
	AuditLogID INT IDENTITY(1, 1) NOT NULL,
	LogDate DATETIME DEFAULT GETDATE(),
	UserName SYSNAME DEFAULT USER_NAME(),
	TimeSlotID INT,
	DepartureDatetime DATETIME,
	ArrivalDatetime DATETIME,
	UserAction VARCHAR(20)
)

CREATE or ALTER TRIGGER Management.AuditTimeSlotChange
ON Management.TimeSlot
AFTER INSERT, UPDATE, DELETE
AS 
BEGIN
    INSERT INTO Management.AuditLog_TimeSlot 
    (TimeSlotID, DepartureDatetime, ArrivalDatetime, UserAction)
    SELECT TimeSlotID, DepartureDatetime, ArrivalDatetime, 'INSERT'
    FROM inserted

    INSERT INTO Management.AuditLog_TimeSlot
    (TimeSlotID, DepartureDatetime, ArrivalDatetime, UserAction)
    SELECT TimeSlotID, DepartureDatetime, ArrivalDatetime, 'DELETE'
    FROM deleted 
END;

/*
## Choong Man Shun TP051283
*/

CREATE TABLE BusUser.AuditLog_Student (
	AuditLogID INT IDENTITY(1, 1) NOT NULL,
	LogDate DATETIME DEFAULT GETDATE(),
	AuditUserName SYSNAME DEFAULT USER_NAME(),
	StudentID INT,
	Name VARCHAR(200),
	UserName VARCHAR(200),
	Password VARCHAR(200),
	UserAction VARCHAR(20)
);

CREATE or ALTER TRIGGER BusUser.AuditStudentChange
ON BusUser.Student
AFTER INSERT, UPDATE, DELETE
AS 
BEGIN
    INSERT INTO BusUser.AuditLog_Student 
    (StudentID, Name, UserName, Password, UserAction)
    SELECT StudentID, Name, UserName, Password, 'INSERT'
    FROM inserted

    INSERT INTO BusUser.AuditLog_Student
    (StudentID, Name, UserName, Password, UserAction)
    SELECT StudentID, Name, UserName, Password, 'DELETE'
    FROM deleted 
END;

CREATE OR ALTER TRIGGER BusUser.HandleReservation
ON BusUser.Reservation
INSTEAD OF INSERT
AS
BEGIN
    UPDATE Management.Schedule
    SET AvailableCapacity = AvailableCapacity - (
        SELECT COUNT(*) 
        FROM inserted 
        WHERE ScheduleID = Schedule.ScheduleID
    )
    WHERE ScheduleID IN (SELECT ScheduleID FROM inserted);

    INSERT BusUser.Reservation (StudentID, ScheduleID)
    SELECT StudentID, ScheduleID FROM inserted;
END;

CREATE OR ALTER TRIGGER BusUser.HandleCancellation
ON BusUser.Reservation
INSTEAD OF UPDATE
AS
BEGIN
    DECLARE @rowCount AS INT;
    SET @rowCount = (SELECT COUNT(*) FROM inserted);

    IF @rowCount = 0
        PRINT '0 reservation updated.'
    ELSE IF @rowCount > 1
        PRINT 'Update for multiple reservations is not allowed.'
    ELSE
    BEGIN
        DECLARE @reservationID AS INT;
        SET @reservationID = (SELECT ReservationID FROM inserted);
        
        DECLARE @cancelled AS BIT;
        SET @cancelled = (SELECT Cancelled FROM inserted);
        
        DECLARE @scheduleID AS INT;
        SET @scheduleID = (SELECT ScheduleID FROM inserted);
        
        IF @cancelled = (SELECT Cancelled FROM deleted)
            PRINT CONCAT(
                'Reservation (ID=', 
                @reservationID, 
                ') is ALREADY ', 
                CASE WHEN @cancelled = 0 THEN 'not ' END, 
                'cancelled.'
            )
        ELSE
        BEGIN
            UPDATE Management.Schedule
            SET AvailableCapacity = (
                SELECT AvailableCapacity 
                FROM Management.Schedule 
                WHERE ScheduleID = @scheduleID
            ) + CASE WHEN @cancelled = 1 THEN 1 ELSE -1 END
            WHERE ScheduleID = @scheduleID;

            UPDATE BusUser.Reservation 
            SET Cancelled = @cancelled
            WHERE ReservationID = @reservationID;
            PRINT CONCAT(
                'Reservation (ID=', 
                @reservationID, 
                ') is NOW ', 
                CASE WHEN @cancelled = 0 THEN 'not ' END, 
                'cancelled.'
            );
        END
    END
END;

/*
# Insert into Tables
*/

/*
## Wong Poh Yee TP051079
*/

INSERT INTO Management.Station
VALUES
('APU Main Campus', 'APU'),
('Bukit Jalil LRT Station', 'Bukit Jalil'),
('Serdang KTM Station', 'Serdang KTM'),
('Bandar Tasek Selatan Bus Terminal', 'BTS');

DECLARE @StationShortName1 AS VARCHAR(20), 
		@StationShortName2 AS VARCHAR(20), 
		@StationShortName3 AS VARCHAR(20), 
		@StationShortName4 AS VARCHAR(20);

SELECT @StationShortName1 = (SELECT ShortName FROM Management.Station WHERE StationID = 1), 
	   @StationShortName2 = (SELECT ShortName FROM Management.Station WHERE StationID = 2), 
	   @StationShortName3 = (SELECT ShortName FROM Management.Station WHERE StationID = 3), 
	   @StationShortName4 = (SELECT ShortName FROM Management.Station WHERE StationID = 4);

INSERT INTO Management.Route
VALUES
(1, 2, @StationShortName1 + ' - ' + @StationShortName2),
(2, 1, @StationShortName2 + ' - ' + @StationShortName1),
(1, 3, @StationShortName1 + ' - ' + @StationShortName3),
(3, 1, @StationShortName3 + ' - ' + @StationShortName1),
(1, 4, @StationShortName1 + ' - ' + @StationShortName4),
(4, 1, @StationShortName4 + ' - ' + @StationShortName1);

INSERT INTO Management.TimeSlot
VALUES
('2022-06-01 06:00:00', '2022-06-01 07:00:00'),
('2022-06-01 07:00:00', '2022-06-01 08:00:00'),
('2022-06-01 09:00:00', '2022-06-01 10:00:00'),
('2022-06-01 10:00:00', '2022-06-01 11:00:00'),
('2022-06-01 11:00:00', '2022-06-01 12:00:00'),
('2022-06-01 14:00:00', '2022-06-01 15:00:00'),
('2022-06-01 16:00:00', '2022-06-01 17:00:00'),
('2022-06-01 18:00:00', '2022-06-01 19:00:00'),
('2022-06-01 20:00:00', '2022-06-01 21:00:00'),
('2022-06-01 21:00:00', '2022-06-01 22:00:00'),

('2022-06-08 06:00:00', '2022-06-08 07:00:00'),
('2022-06-08 07:00:00', '2022-06-08 08:00:00'),
('2022-06-08 09:00:00', '2022-06-08 10:00:00'),
('2022-06-08 10:00:00', '2022-06-08 11:00:00'),
('2022-06-08 11:00:00', '2022-06-08 12:00:00'),
('2022-06-08 14:00:00', '2022-06-08 15:00:00'),
('2022-06-08 16:00:00', '2022-06-08 17:00:00'),
('2022-06-08 18:00:00', '2022-06-08 19:00:00'),
('2022-06-08 20:00:00', '2022-06-08 21:00:00'),
('2022-06-08 21:00:00', '2022-06-08 22:00:00'),

('2022-07-22 06:00:00', '2022-07-22 07:00:00'),
('2022-07-22 07:00:00', '2022-07-22 08:00:00'),
('2022-07-22 09:00:00', '2022-07-22 10:00:00'),
('2022-07-22 10:00:00', '2022-07-22 11:00:00'),
('2022-07-22 11:00:00', '2022-07-22 12:00:00'),
('2022-07-22 14:00:00', '2022-07-22 15:00:00'),
('2022-07-22 16:00:00', '2022-07-22 17:00:00'),
('2022-07-22 18:00:00', '2022-07-22 19:00:00'),
('2022-07-22 20:00:00', '2022-07-22 21:00:00'),
('2022-07-22 21:00:00', '2022-07-22 22:00:00'),

('2022-09-03 06:00:00', '2022-09-03 07:00:00'),
('2022-09-03 07:00:00', '2022-09-03 08:00:00'),
('2022-09-03 09:00:00', '2022-09-03 10:00:00'),
('2022-09-03 10:00:00', '2022-09-03 11:00:00'),
('2022-09-03 11:00:00', '2022-09-03 12:00:00'),
('2022-09-03 14:00:00', '2022-09-03 15:00:00'),
('2022-09-03 16:00:00', '2022-09-03 17:00:00'),
('2022-09-03 18:00:00', '2022-09-03 19:00:00'),
('2022-09-03 20:00:00', '2022-09-03 21:00:00'),
('2022-09-03 21:00:00', '2022-09-03 22:00:00'); 

/*
## Chew Cheng Yong TP051338
*/

INSERT INTO Management.BusStatus
VALUES
('Operating'),
('Resting'),
('Down');

DECLARE @DownStatusID AS INT;

SELECT @DownStatusID = (SELECT StatusID FROM Management.BusStatus WHERE Name = 'Down');

INSERT INTO Management.Bus
VALUES
('WB1234A', 40, @DownStatusID),
('WB5678A', 40, @DownStatusID),
('WB1011A', 40, @DownStatusID),
('WB1213A', 40, @DownStatusID),
('WB1415A', 40, @DownStatusID),
('WB1234B', 40, @DownStatusID),
('WBA1234A', 40, @DownStatusID),
('WB3412C', 40, @DownStatusID),
('WA1334A', 40, @DownStatusID),
('WA1134B', 40, @DownStatusID),
('WBD3334A', 40, @DownStatusID),
('WB1256D', 40, @DownStatusID);

INSERT INTO Management.Schedule
SELECT RouteID, TimeSlotID, BusID, 40 
FROM (
	SELECT 1 AS RouteID, 1 AS BusID
	UNION
	SELECT 1, 2
	UNION
	SELECT 2, 3
	UNION
	SELECT 2, 4
	UNION
	SELECT 3, 5
	UNION
	SELECT 3, 6
	UNION
	SELECT 4, 7
	UNION
	SELECT 4, 8
	UNION
	SELECT 5, 9
	UNION
	SELECT 5, 10
	UNION
	SELECT 6, 11
	UNION
	SELECT 6, 12
) AS RouteBus
CROSS JOIN Management.TimeSlot;

/*
## Choong Man Shun TP051283
*/

INSERT INTO BusUser.Student
(Name, Password)
VALUES
('Man Shun', 'Passw0rd'),
('Cheng Yong', 'Passw0rd'),
('Poh Yee', 'Passw0rd'),
('Riya', 'Passw0rd'),
('Ernest', 'Passw0rd'),
('Diamond', 'Passw0rd'),
('Michelle', 'Passw0rd'),
('Crystal', 'Passw0rd'),
('Sukie', 'Passw0rd'),
('Hashim', 'Passw0rd'),

('Sariah', 'Passw0rd'),
('Julie', 'Passw0rd'),
('Nydia', 'Passw0rd'),
('Cristiana', 'Passw0rd'),
('Emma', 'Passw0rd'),
('Nicodema', 'Passw0rd'),
('Jason', 'Passw0rd'),
('Jessica', 'Passw0rd'),
('Gozzo', 'Passw0rd'),
('Sikandar', 'Passw0rd'),

('Esther', 'Passw0rd'),
('Ryousuke', 'Passw0rd'),
('Domitius', 'Passw0rd'),
('Brighid', 'Passw0rd'),
('Epifanio', 'Passw0rd'),
('Abdul', 'Passw0rd'),
('Sigdag', 'Passw0rd'),
('Freyr', 'Passw0rd'),
('Newen', 'Passw0rd'),
('Ralf', 'Passw0rd'),

('Clodagh', 'Passw0rd'),
('Niall', 'Passw0rd'),
('Kyllikki', 'Passw0rd'),
('Nonhelema', 'Passw0rd'),
('Ningal', 'Passw0rd'),
('Filip', 'Passw0rd'),
('Ammar', 'Passw0rd'),
('Kosmas', 'Passw0rd'),
('Jaylene', 'Passw0rd'),
('Edith', 'Passw0rd'),

('Remedios', 'Passw0rd'),
('Izabel', 'Passw0rd'),
('Ally', 'Passw0rd'),
('Odeserundiye', 'Passw0rd'),
('Cai', 'Passw0rd'),
('Jaquan', 'Passw0rd'),
('Sipho', 'Passw0rd'),
('Yash', 'Passw0rd'),
('Goibniu', 'Passw0rd'),
('Lulu', 'Passw0rd');

UPDATE BusUser.Student
SET EncryptedPasswordByCert = ENCRYPTBYCERT(
    CERT_ID('StudentPasswordCertificate'), Password
);

UPDATE BusUser.Student
SET EncryptedPasswordByKey = ENCRYPTBYKEY(
    KEY_GUID('Symmetrickey'), 
    Password, 
    1, 
    HASHBYTES('SHA2_256', CONVERT(varbinary, StudentID))
);

INSERT INTO BusUser.Reservation
(StudentID, ScheduleID)
VALUES 
(1, 1),
(2, 1),
(3, 1),
(4, 1),
(5, 1),
(6, 1),
(7, 1),
(8, 1),
(9, 1),
(10, 1),

(11, 1),
(12, 1),
(13, 1),
(14, 1),
(15, 1),
(16, 1),
(17, 1),
(18, 1),
(19, 1),
(20, 1),

(21, 1),
(22, 1),
(23, 1),
(24, 1),
(25, 1),
(26, 1),
(27, 1),
(28, 1),
(29, 1),
(30, 1),

(31, 1),
(32, 1),
(33, 1),
(34, 1),
(35, 1),
(36, 1),
(37, 1),
(38, 1),
(39, 1),
(40, 1),

(1, 2),
(2, 2),
(3, 2),
(4, 2),
(5, 2),
(6, 2),
(1, 3),
(2, 3),
(1, 4),
(3, 5);

UPDATE BusUser.Reservation
SET Cancelled = 1
WHERE StudentID = 6 AND ScheduleID = 2;

/*
# Create Roles
*/

/*
## Wong Poh Yee TP051079
*/

CREATE ROLE Management;

/*
## Chew Cheng Yong TP051338
*/

CREATE ROLE DatabaseAdmins;

CREATE ROLE Schedulers;

/*
## Choong Man Shun TP051283
*/

CREATE ROLE Students;

/*
# Creates Logins
*/

/*
## Wong Poh Yee TP051079
*/

CREATE LOGIN AnalystDeptHead
WITH PASSWORD = 'Passw0rd',
DEFAULT_DATABASE = [APU Bus Services],
CHECK_POLICY = ON,
CHECK_EXPIRATION = OFF;

CREATE LOGIN ServicesDeptHead
WITH PASSWORD = 'Passw0rd',
DEFAULT_DATABASE = [APU Bus Services],
CHECK_POLICY = ON,
CHECK_EXPIRATION = OFF;

/*
## Chew Cheng Yong TP051338
*/

CREATE LOGIN DatabaseAdmin1
WITH PASSWORD = '$tr0ngP@$$w0rd',
DEFAULT_DATABASE = [APU Bus Services],
CHECK_POLICY = ON,
CHECK_EXPIRATION = OFF;

CREATE LOGIN Scheduler1
WITH PASSWORD = '$tr0ngP@$$w0rd',
DEFAULT_DATABASE = [APU Bus Services],
CHECK_POLICY = ON,
CHECK_EXPIRATION = OFF;

CREATE LOGIN Scheduler2
WITH PASSWORD = '$tr0ngP@$$w0rd',
DEFAULT_DATABASE = [APU Bus Services],
CHECK_POLICY = ON,
CHECK_EXPIRATION = OFF;

/*
## Choong Man Shun TP051283
*/

CREATE LOGIN Student1
WITH PASSWORD = 'Passw0rd',
DEFAULT_DATABASE = [APU Bus Services],
CHECK_POLICY = ON,
CHECK_EXPIRATION = OFF;

CREATE LOGIN Student2
WITH PASSWORD = 'Passw0rd',
DEFAULT_DATABASE = [APU Bus Services],
CHECK_POLICY = ON,
CHECK_EXPIRATION = OFF;

CREATE LOGIN Student3
WITH PASSWORD = 'Passw0rd',
DEFAULT_DATABASE = [APU Bus Services],
CHECK_POLICY = ON,
CHECK_EXPIRATION = OFF;

/*
# Create Users
*/

/*
## Wong Poh Yee TP051079
*/

-- Create management users with login 
CREATE USER AnalystDeptHead FOR LOGIN AnalystDeptHead;
CREATE USER ServicesDeptHead FOR LOGIN ServicesDeptHead;

-- Create management users without login
CREATE USER BusDeptHead WITHOUT LOGIN;

/*
## Chew Cheng Yong TP051338
*/

-- Create database admin user with login
CREATE USER DatabaseAdmin1 FOR LOGIN DatabaseAdmin1;

-- Create database admin user without login
CREATE USER DatabaseAdmin2 WITHOUT LOGIN;
CREATE USER DatabaseAdmin3 WITHOUT LOGIN;

-- Create scheduler user with login
CREATE USER Scheduler1 FOR LOGIN Scheduler1;
CREATE USER Scheduler2 FOR LOGIN Scheduler2;

-- Create scheduler user without login
CREATE USER Scheduler3 WITHOUT LOGIN;

/*
## Choong Man Shun TP051283
*/

-- Create student users with login
CREATE USER Student1 FOR LOGIN Student1;
CREATE USER Student2 FOR LOGIN Student2;
CREATE USER Student3 FOR LOGIN Student3;

-- Create student users without login
CREATE USER Student4 WITHOUT LOGIN;
CREATE USER Student5 WITHOUT LOGIN;
CREATE USER Student6 WITHOUT LOGIN;
CREATE USER Student7 WITHOUT LOGIN;
CREATE USER Student8 WITHOUT LOGIN;
CREATE USER Student9 WITHOUT LOGIN;
CREATE USER Student10 WITHOUT LOGIN;
CREATE USER Student11 WITHOUT LOGIN;
CREATE USER Student12 WITHOUT LOGIN;
CREATE USER Student13 WITHOUT LOGIN;
CREATE USER Student14 WITHOUT LOGIN;
CREATE USER Student15 WITHOUT LOGIN;
CREATE USER Student16 WITHOUT LOGIN;
CREATE USER Student17 WITHOUT LOGIN;
CREATE USER Student18 WITHOUT LOGIN;
CREATE USER Student19 WITHOUT LOGIN;
CREATE USER Student20 WITHOUT LOGIN;
CREATE USER Student21 WITHOUT LOGIN;
CREATE USER Student22 WITHOUT LOGIN;
CREATE USER Student23 WITHOUT LOGIN;
CREATE USER Student24 WITHOUT LOGIN;
CREATE USER Student25 WITHOUT LOGIN;
CREATE USER Student26 WITHOUT LOGIN;
CREATE USER Student27 WITHOUT LOGIN;
CREATE USER Student28 WITHOUT LOGIN;
CREATE USER Student29 WITHOUT LOGIN;
CREATE USER Student30 WITHOUT LOGIN;
CREATE USER Student31 WITHOUT LOGIN;
CREATE USER Student32 WITHOUT LOGIN;
CREATE USER Student33 WITHOUT LOGIN;
CREATE USER Student34 WITHOUT LOGIN;
CREATE USER Student35 WITHOUT LOGIN;
CREATE USER Student36 WITHOUT LOGIN;
CREATE USER Student37 WITHOUT LOGIN;
CREATE USER Student38 WITHOUT LOGIN;
CREATE USER Student39 WITHOUT LOGIN;
CREATE USER Student40 WITHOUT LOGIN;
CREATE USER Student41 WITHOUT LOGIN;
CREATE USER Student42 WITHOUT LOGIN;
CREATE USER Student43 WITHOUT LOGIN;
CREATE USER Student44 WITHOUT LOGIN;
CREATE USER Student45 WITHOUT LOGIN;
CREATE USER Student46 WITHOUT LOGIN;
CREATE USER Student47 WITHOUT LOGIN;
CREATE USER Student48 WITHOUT LOGIN;
CREATE USER Student49 WITHOUT LOGIN;
CREATE USER Student50 WITHOUT LOGIN;

/*
# Add Users to Role
*/

/*
## Wong Poh Yee TP051079
*/

ALTER ROLE Management ADD MEMBER BusDeptHead;
ALTER ROLE Management ADD MEMBER AnalystDeptHead;
ALTER ROLE Management ADD MEMBER ServicesDeptHead;

/*
## Chew Cheng Yong TP051338
*/

ALTER ROLE DatabaseAdmins ADD MEMBER DatabaseAdmin1;
ALTER ROLE DatabaseAdmins ADD MEMBER DatabaseAdmin2;
ALTER ROLE DatabaseAdmins ADD MEMBER DatabaseAdmin3;

ALTER ROLE Schedulers ADD MEMBER Scheduler1;
ALTER ROLE Schedulers ADD MEMBER Scheduler2;
ALTER ROLE Schedulers ADD MEMBER Scheduler3;

/*
## Choong Man Shun TP051283
*/

ALTER ROLE Students ADD MEMBER Student1;
ALTER ROLE Students ADD MEMBER Student2;
ALTER ROLE Students ADD MEMBER Student3;
ALTER ROLE Students ADD MEMBER Student4;
ALTER ROLE Students ADD MEMBER Student5;
ALTER ROLE Students ADD MEMBER Student6;
ALTER ROLE Students ADD MEMBER Student7;
ALTER ROLE Students ADD MEMBER Student8;
ALTER ROLE Students ADD MEMBER Student9;
ALTER ROLE Students ADD MEMBER Student10;
ALTER ROLE Students ADD MEMBER Student11;
ALTER ROLE Students ADD MEMBER Student12;
ALTER ROLE Students ADD MEMBER Student13;
ALTER ROLE Students ADD MEMBER Student14;
ALTER ROLE Students ADD MEMBER Student15;
ALTER ROLE Students ADD MEMBER Student16;
ALTER ROLE Students ADD MEMBER Student17;
ALTER ROLE Students ADD MEMBER Student18;
ALTER ROLE Students ADD MEMBER Student19;
ALTER ROLE Students ADD MEMBER Student20;
ALTER ROLE Students ADD MEMBER Student21;
ALTER ROLE Students ADD MEMBER Student22;
ALTER ROLE Students ADD MEMBER Student23;
ALTER ROLE Students ADD MEMBER Student24;
ALTER ROLE Students ADD MEMBER Student25;
ALTER ROLE Students ADD MEMBER Student26;
ALTER ROLE Students ADD MEMBER Student27;
ALTER ROLE Students ADD MEMBER Student28;
ALTER ROLE Students ADD MEMBER Student29;
ALTER ROLE Students ADD MEMBER Student30;
ALTER ROLE Students ADD MEMBER Student31;
ALTER ROLE Students ADD MEMBER Student32;
ALTER ROLE Students ADD MEMBER Student33;
ALTER ROLE Students ADD MEMBER Student34;
ALTER ROLE Students ADD MEMBER Student35;
ALTER ROLE Students ADD MEMBER Student36;
ALTER ROLE Students ADD MEMBER Student37;
ALTER ROLE Students ADD MEMBER Student38;
ALTER ROLE Students ADD MEMBER Student39;
ALTER ROLE Students ADD MEMBER Student40;
ALTER ROLE Students ADD MEMBER Student41;
ALTER ROLE Students ADD MEMBER Student42;
ALTER ROLE Students ADD MEMBER Student43;
ALTER ROLE Students ADD MEMBER Student44;
ALTER ROLE Students ADD MEMBER Student45;
ALTER ROLE Students ADD MEMBER Student46;
ALTER ROLE Students ADD MEMBER Student47;
ALTER ROLE Students ADD MEMBER Student48;
ALTER ROLE Students ADD MEMBER Student49;
ALTER ROLE Students ADD MEMBER Student50;

/*
# Implement Object Level Security
*/

/*
## Wong Poh Yee TP051079
*/

GRANT SELECT ON Management.[Weekly Reporting] TO Management;

GRANT SELECT ON Management.[Monthly Reporting] TO Management;

/*
## Chew Cheng Yong TP051338
*/

GRANT CONTROL
ON SCHEMA::[Management]
TO DatabaseAdmins
WITH GRANT OPTION;

GRANT CONTROL
ON SCHEMA::[BusUser]
TO DatabaseAdmins
WITH GRANT OPTION;

--once grant create permission, then it can perform delete/drop
GRANT CREATE VIEW TO [DatabaseAdmins]
GRANT CREATE TABLE TO [DatabaseAdmins]

GRANT SELECT, INSERT, UPDATE, DELETE
ON Management.Route
TO Schedulers;

GRANT SELECT, INSERT, UPDATE, DELETE
ON Management.Schedule
TO Schedulers;

GRANT SELECT, INSERT, UPDATE, DELETE
ON Management.TimeSlot
TO Schedulers;

GRANT SELECT, INSERT, UPDATE
ON Management.Station
TO Schedulers;

GRANT SELECT, INSERT, UPDATE
ON Management.Bus
TO Schedulers;

GRANT SELECT
ON Management.BusStatus
TO Schedulers;

/*
## Choong Man Shun TP051283
*/

GRANT SELECT, UPDATE ON BusUser.[Student Profile] TO Students;

GRANT SELECT ON BusUser.[Bus Availability Checking] TO Students;

GRANT SELECT, INSERT ON BusUser.[Student Booking] TO Students;

GRANT SELECT ON BusUser.[Student Booking Cancelling] TO Students;

GRANT UPDATE ON BusUser.[Student Booking Cancelling](Cancelled) TO Students;

/*
# Implement Row Level Security (RLS)
*/

/*
## Choong Man Shun (TP051283)
*/

CREATE SCHEMA Security;

CREATE FUNCTION Security.tvf_securitypredicate
(@UserName AS nvarchar(100))
    RETURNS TABLE
WITH SCHEMABINDING
AS
    RETURN SELECT 1 AS tvf_securitypredicate_result
WHERE @UserName = USER_NAME() 
OR USER_NAME() = 'dbo'
OR IS_MEMBER('DatabaseAdmins') = 1;

CREATE SECURITY POLICY Security.StudentProfileFilter
ADD FILTER PREDICATE 
    Security.tvf_securitypredicate(UserName)
ON BusUser.[Student Profile];

CREATE SECURITY POLICY Security.StudentBookingFilter
ADD FILTER PREDICATE 
    Security.tvf_securitypredicate(UserName)
ON BusUser.[Student Booking];

CREATE SECURITY POLICY Security.StudentBookingCancellingFilter
ADD FILTER PREDICATE 
    Security.tvf_securitypredicate(UserName)
ON BusUser.[Student Booking Cancelling];

/*
# Create Logon Triggers
*/

/*
## Wong Poh Yee TP051079
*/

CREATE OR ALTER TRIGGER LimitSessions 
ON ALL SERVER
FOR LOGON 
AS
BEGIN
    IF ORIGINAL_LOGIN() LIKE 'AnalystDeptHead' OR ORIGINAL_LOGIN() LIKE 'ServicesDeptHead' 
    AND (
        SELECT COUNT(*) FROM sys.dm_exec_sessions 
        WHERE is_user_process = 1 
        AND original_login_name = ORIGINAL_LOGIN()
    ) > 5
    BEGIN
        PRINT 'Maximum connection allowed per user is 5 only';
        ROLLBACK;
    END
END;

CREATE OR ALTER TRIGGER LimitManagementLoginHours 
ON ALL SERVER
FOR LOGON 
AS
BEGIN
    IF ORIGINAL_LOGIN() LIKE 'AnalystDeptHead' OR ORIGINAL_LOGIN() LIKE 'ServicesDeptHead' 
    AND DATEPART(HOUR, GETDATE()) BETWEEN 0 AND 5
    BEGIN
        PRINT 'You are only allowed to log in after 6am and before 12am.';
        ROLLBACK;
    END
END;

/*
## Chew Cheng Yong TP051338
*/

CREATE OR ALTER TRIGGER LimitSchedulerSessions 
ON ALL SERVER
FOR LOGON 
AS
BEGIN
    IF ORIGINAL_LOGIN() LIKE 'Scheduler%'
    AND (
        SELECT COUNT(*) FROM sys.dm_exec_sessions 
        WHERE is_user_process = 1 
        AND original_login_name = ORIGINAL_LOGIN()
    ) > 5
    BEGIN
        PRINT 'Maximum connection allowed per scheduler user is 5 only.';
        ROLLBACK;
    END
END;

CREATE OR ALTER TRIGGER LimitDatabaseAdminsSessions 
ON ALL SERVER
FOR LOGON 
AS
BEGIN
    IF ORIGINAL_LOGIN() LIKE 'DatabaseAdmin%'
    AND (
        SELECT COUNT(*) FROM sys.dm_exec_sessions 
        WHERE is_user_process = 1 
        AND original_login_name = ORIGINAL_LOGIN()
    ) > 5
    BEGIN
        PRINT 'Maximum connection allowed per database administrator is 5 only.';
        ROLLBACK;
    END
END;

--add ur host_name() inside the list, if not ltr cannot log in
CREATE OR ALTER TRIGGER MyHostsOnly
ON ALL SERVER
FOR LOGON
AS
BEGIN
    -- White list of allowed hostnames are defined here.
    IF HOST_NAME() NOT IN ('ProdBox', 'QaBox', 'DevBox', 'UserBox', 'LAPTOP-1QS5DC0S', 'MANSHUN', 'Evangelines-M1-Air')
    BEGIN
        RAISERROR('You are not allowed to login from this hostname.', 16, 1);
        ROLLBACK;
    END 
END

--add ur suser_name() inside the list, if not ltr cannot log in
CREATE OR ALTER TRIGGER LimitConnectionAfterOfficeHours
ON ALL SERVER FOR LOGON 
AS
BEGIN
    IF ORIGINAL_LOGIN() IN ('Scheduler1', 'Scheduler2', 'Scheduler3') 
    AND SUSER_NAME() NOT IN ('sa','LAPTOP-1QS5DC0S\chewc') 
    AND (DATEPART(HOUR, GETDATE()) < 8 
    OR DATEPART (HOUR, GETDATE()) > 18)
    BEGIN
        PRINT 'You are not authorized to login after office hours';
        ROLLBACK;
    END
END

/*
## Choong Man Shun (TP051283)
*/

CREATE TABLE Management.AuditLog_Logon (
	AuditLogID INT IDENTITY(1, 1) NOT NULL,
	LogDate DATETIME DEFAULT GETDATE(),
	UserName SYSNAME DEFAULT ORIGINAL_LOGIN(),
	Spid SMALLINT
);

GRANT INSERT ON Management.AuditLog_Logon TO Students;
GRANT INSERT ON Management.AuditLog_Logon TO Management;
GRANT INSERT ON Management.AuditLog_Logon TO DatabaseAdmins 
WITH GRANT OPTION;
GRANT INSERT ON Management.AuditLog_Logon TO Schedulers;

CREATE OR ALTER TRIGGER AuditLogon
ON ALL SERVER 
FOR LOGON 
AS
    INSERT INTO [APU Bus Services].Management.AuditLog_Logon 
    (Spid)
    VALUES (@@SPID);

CREATE OR ALTER TRIGGER LimitStudentSessions 
ON ALL SERVER
FOR LOGON 
AS
BEGIN
    IF ORIGINAL_LOGIN() LIKE 'Student%'
    AND (
        SELECT COUNT(*) FROM sys.dm_exec_sessions 
        WHERE is_user_process = 1 
        AND original_login_name = ORIGINAL_LOGIN()
    ) > 3
    BEGIN
        PRINT 'Maximum connection allowed per student user is 3 only.';
        ROLLBACK;
    END
END;

CREATE OR ALTER TRIGGER LimitStudentLoginHours 
ON ALL SERVER
FOR LOGON 
AS
BEGIN
    IF ORIGINAL_LOGIN() LIKE 'Student%'
    AND DATEPART(HOUR, GETDATE()) NOT BETWEEN 6 AND 22
    BEGIN
        PRINT 'You are only allowed to log in after 6am and before 10pm.';
        ROLLBACK;
    END
END;

/*
# Extra
*/

SELECT 
	StudentID, 
	Name, 
	EncryptedPasswordByCert, 
	CAST(
		DECRYPTBYCERT(
			CERT_ID('StudentPasswordCertificate'), 
			EncryptedPasswordByCert
		) AS VARCHAR
	) AS DecryptedPasswordByCert,
	EncryptedPasswordByKey,
	CAST(
		DECRYPTBYKEY(
			EncryptedPasswordByKey, 
			1, 
			HASHBYTES('SHA2_256', CONVERT(varbinary, StudentID))
		) AS VARCHAR
	) AS DecryptedPasswordByKey
FROM BusUser.Student;

SELECT 
	ScheduleID, 
	CASE
		WHEN Cancelled = 1
		THEN 'Yes'
		ELSE 'No'
	END AS Cancelled, 
	COUNT(*) AS Count
FROM BusUser.Reservation
GROUP BY Cancelled, ScheduleID;

SELECT 
    Schedule.*, 
    COUNT(Reservation.ReservationID) AS ReservationCount 
FROM Management.Schedule 
JOIN (
    SELECT * FROM BusUser.Reservation WHERE Cancelled = 0
) AS Reservation
    ON Schedule.ScheduleID = Reservation.ScheduleID 
GROUP BY 
    Schedule.ScheduleID, RouteID, TimeSlotID, BusID, AvailableCapacity;

-- -- Exceed capacity (not allowed)
-- INSERT INTO BusUser.Reservation
-- (StudentID, ScheduleID)
-- VALUES 
-- (50, 1);

/*
## Student
*/

-- Student: View SQL student table (not allowed)
-- EXECUTE AS USER = 'Student1';
-- SELECT * FROM BusUser.Student;
-- REVERT;

-- Student: View profile
EXECUTE AS USER = 'Student1';
PRINT USER_NAME();
SELECT * FROM BusUser.[Student Profile];
REVERT;

-- Student: Change profile password
DECLARE @newPassword VARBINARY(2000);
SELECT @newPassword = ENCRYPTBYCERT(CERT_ID('StudentPasswordCertificate'), 'NewPassw0rd');

EXECUTE AS USER = 'Student1';

UPDATE BusUser.[Student Profile] 
SET [Encrypted Password] = @newPassword
WHERE [Student ID] = 1;

REVERT;

SELECT * FROM BusUser.[Bus Availability Checking];

-- Student: Place booking
EXECUTE AS USER = 'Student1';

INSERT BusUser.[Student Booking]
([Student ID], [Schedule ID])
VALUES
(1, 101);

REVERT;

-- Student: View booking
EXECUTE AS USER = 'Student1';

SELECT * FROM BusUser.[Student Booking];

REVERT;

-- Student: Cancel booking
EXECUTE AS USER = 'Student1';

UPDATE BusUser.[Student Booking Cancelling]
SET Cancelled = 1
WHERE [Reservation ID] = 51;

REVERT;

/*
## Managment
*/

EXECUTE AS USER = 'AnalystDeptHead';
SELECT * FROM Management.[Monthly Reporting];
REVERT;

EXECUTE AS USER = 'AnalystDeptHead';
SELECT * FROM Management.[Weekly Reporting];
REVERT;

/*
## Auditing
*/

SELECT * FROM Management.AuditLog_Logon;
-- DELETE Management.AuditLog_Logon;

SELECT * FROM Management.AuditLog_DDL;

SELECT * FROM BusUser.AuditLog_Student;

SELECT * FROM Management.AuditLog_Schedule;

SELECT * FROM Management.AuditLog_Route;

SELECT * FROM Management.AuditLog_TimeSlot;