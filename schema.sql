-- IEFMDB TAE-2 IMPLEMENTATION
-- Integrated E-Ticketing & Fleet Operations Management Database
-- Target RDBMS: MySQL 8.0
-- Schema follows the TAE-1 approved entities and attributes.

DROP DATABASE IF EXISTS IEFMDB;
CREATE DATABASE IEFMDB;
USE IEFMDB;

SET FOREIGN_KEY_CHECKS = 0;

DROP VIEW IF EXISTS vw_route_revenue;
DROP VIEW IF EXISTS vw_vehicle_operations;

DROP TRIGGER IF EXISTS trg_maintenance_vehicle_status;
DROP TRIGGER IF EXISTS trg_payment_confirm_ticket;

DROP PROCEDURE IF EXISTS BOOK_TICKET;

DROP TABLE IF EXISTS PAYMENT;
DROP TABLE IF EXISTS TICKET;
DROP TABLE IF EXISTS MAINTENANCE_LOG;
DROP TABLE IF EXISTS SEAT;
DROP TABLE IF EXISTS SCHEDULE;
DROP TABLE IF EXISTS ROUTE_STOP;
DROP TABLE IF EXISTS STOP;
DROP TABLE IF EXISTS ROUTE;
DROP TABLE IF EXISTS DRIVER;
DROP TABLE IF EXISTS VEHICLE;
DROP TABLE IF EXISTS PASSENGER;

SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE PASSENGER (
    PassengerID      INT PRIMARY KEY,
    FirstName        VARCHAR(50) NOT NULL,
    LastName         VARCHAR(50) NOT NULL,
    Email            VARCHAR(100) NOT NULL UNIQUE,
    Phone            VARCHAR(15) NOT NULL,
    DOB              DATE,
    Gender           VARCHAR(10),
    Address          VARCHAR(255),
    RegistrationDate DATE NOT NULL
) ENGINE=InnoDB;

CREATE TABLE VEHICLE (
    VehicleID       INT PRIMARY KEY,
    RegNo           VARCHAR(20) NOT NULL UNIQUE,
    VIN             VARCHAR(30) NOT NULL UNIQUE,
    Make            VARCHAR(50) NOT NULL,
    Model           VARCHAR(50) NOT NULL,
    Year            INT NOT NULL,
    Capacity        INT NOT NULL,
    FuelType        VARCHAR(20) NOT NULL,
    CurrentMileage  DECIMAL(10,2) NOT NULL DEFAULT 0,
    Status          VARCHAR(20) NOT NULL DEFAULT 'Active'
        CHECK (Status IN ('Active','In-Shop','Inactive'))
) ENGINE=InnoDB;

CREATE TABLE DRIVER (
    DriverID       INT PRIMARY KEY,
    FirstName      VARCHAR(50) NOT NULL,
    LastName       VARCHAR(50) NOT NULL,
    LicenseNo      VARCHAR(30) NOT NULL UNIQUE,
    LicenseExpiry  DATE NOT NULL,
    Phone          VARCHAR(15) NOT NULL,
    HireDate       DATE NOT NULL,
    Status         VARCHAR(20) NOT NULL DEFAULT 'Active'
        CHECK (Status IN ('Active','Suspended','Inactive'))
) ENGINE=InnoDB;

CREATE TABLE ROUTE (
    RouteID        INT PRIMARY KEY,
    RouteName      VARCHAR(100) NOT NULL,
    Source         VARCHAR(100) NOT NULL,
    Destination    VARCHAR(100) NOT NULL,
    TotalDistance  DECIMAL(8,2) NOT NULL,
    EstDuration    INT NOT NULL
) ENGINE=InnoDB;

CREATE TABLE STOP (
    StopID       INT PRIMARY KEY,
    StopName     VARCHAR(100) NOT NULL,
    Latitude     DECIMAL(9,6),
    Longitude    DECIMAL(9,6),
    StopType     VARCHAR(20) NOT NULL
        CHECK (StopType IN ('Terminal','Major','Regular'))
) ENGINE=InnoDB;

CREATE TABLE ROUTE_STOP (
    RouteID             INT NOT NULL,
    StopID              INT NOT NULL,
    StopOrder           INT NOT NULL,
    DistanceFromSource  DECIMAL(8,2) NOT NULL,
    PRIMARY KEY (RouteID, StopID),
    UNIQUE KEY uq_route_stop_order (RouteID, StopOrder),
    CONSTRAINT fk_rs_route FOREIGN KEY (RouteID) REFERENCES ROUTE(RouteID),
    CONSTRAINT fk_rs_stop  FOREIGN KEY (StopID) REFERENCES STOP(StopID)
) ENGINE=InnoDB;

CREATE TABLE SCHEDULE (
    ScheduleID     INT PRIMARY KEY,
    RouteID        INT NOT NULL,
    VehicleID      INT NOT NULL,
    DriverID       INT NOT NULL,
    DepartureTime  DATETIME NOT NULL,
    ArrivalTime    DATETIME,
    DayOfWeek      VARCHAR(10) NOT NULL,
    Status         VARCHAR(20) NOT NULL DEFAULT 'Scheduled'
        CHECK (Status IN ('Scheduled','Completed','Cancelled')),
    CONSTRAINT fk_schedule_route
        FOREIGN KEY (RouteID) REFERENCES ROUTE(RouteID),
    CONSTRAINT fk_schedule_vehicle
        FOREIGN KEY (VehicleID) REFERENCES VEHICLE(VehicleID),
    CONSTRAINT fk_schedule_driver
        FOREIGN KEY (DriverID) REFERENCES DRIVER(DriverID)
) ENGINE=InnoDB;

CREATE TABLE SEAT (
    SeatID      INT PRIMARY KEY,
    VehicleID   INT NOT NULL,
    SeatNo      VARCHAR(10) NOT NULL,
    SeatType    VARCHAR(20) NOT NULL DEFAULT 'Standard',
    Status      VARCHAR(20) NOT NULL DEFAULT 'Available'
        CHECK (Status IN ('Available','Blocked')),
    UNIQUE KEY uq_vehicle_seat (VehicleID, SeatNo),
    CONSTRAINT fk_seat_vehicle
        FOREIGN KEY (VehicleID) REFERENCES VEHICLE(VehicleID)
) ENGINE=InnoDB;

CREATE TABLE TICKET (
    TicketID      INT PRIMARY KEY,
    PassengerID   INT NOT NULL,
    ScheduleID    INT NOT NULL,
    SeatID        INT NOT NULL,
    FareAmount    DECIMAL(10,2) NOT NULL,
    BookingDate   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    TicketStatus  VARCHAR(20) NOT NULL DEFAULT 'Pending'
        CHECK (TicketStatus IN ('Pending','Confirmed','Cancelled','Used')),
    QRHash        VARCHAR(255) NOT NULL UNIQUE,
    UNIQUE KEY uq_schedule_seat (ScheduleID, SeatID),
    CONSTRAINT fk_ticket_passenger
        FOREIGN KEY (PassengerID) REFERENCES PASSENGER(PassengerID),
    CONSTRAINT fk_ticket_schedule
        FOREIGN KEY (ScheduleID) REFERENCES SCHEDULE(ScheduleID),
    CONSTRAINT fk_ticket_seat
        FOREIGN KEY (SeatID) REFERENCES SEAT(SeatID)
) ENGINE=InnoDB;

CREATE TABLE PAYMENT (
    PaymentID       INT PRIMARY KEY,
    TicketID        INT NOT NULL,
    Amount          DECIMAL(10,2) NOT NULL,
    PaymentMethod   VARCHAR(30) NOT NULL,
    TransactionRef  VARCHAR(100) UNIQUE,
    PaymentDate     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    Status          VARCHAR(20) NOT NULL DEFAULT 'Pending'
        CHECK (Status IN ('Pending','Success','Failed','Refunded')),
    CONSTRAINT fk_payment_ticket
        FOREIGN KEY (TicketID) REFERENCES TICKET(TicketID)
) ENGINE=InnoDB;

CREATE TABLE MAINTENANCE_LOG (
    LogID              INT PRIMARY KEY,
    VehicleID          INT NOT NULL,
    ServiceDate        DATE NOT NULL,
    ServiceType        VARCHAR(50) NOT NULL,
    Description        TEXT,
    Cost               DECIMAL(10,2),
    NextServiceDue     DATE,
    MileageAtService   DECIMAL(10,2),
    CONSTRAINT fk_maintenance_vehicle
        FOREIGN KEY (VehicleID) REFERENCES VEHICLE(VehicleID)
) ENGINE=InnoDB;

-- Functional trigger:
-- When a maintenance record is inserted and the next service date is due,
-- the vehicle is automatically marked In-Shop.
DELIMITER $$

CREATE TRIGGER trg_maintenance_vehicle_status
AFTER INSERT ON MAINTENANCE_LOG
FOR EACH ROW
BEGIN
    IF NEW.NextServiceDue IS NOT NULL AND NEW.NextServiceDue <= CURDATE() THEN
        UPDATE VEHICLE
        SET Status = 'In-Shop'
        WHERE VehicleID = NEW.VehicleID;
    END IF;
END$$

-- Payment-success trigger:
-- A ticket is confirmed only after a successful payment.
CREATE TRIGGER trg_payment_confirm_ticket
AFTER INSERT ON PAYMENT
FOR EACH ROW
BEGIN
    IF NEW.Status = 'Success' THEN
        UPDATE TICKET
        SET TicketStatus = 'Confirmed'
        WHERE TicketID = NEW.TicketID
          AND TicketStatus = 'Pending';
    END IF;
END$$

-- Stored procedure for controlled ticket booking.
CREATE PROCEDURE BOOK_TICKET (
    IN p_TicketID INT,
    IN p_PassengerID INT,
    IN p_ScheduleID INT,
    IN p_SeatID INT,
    IN p_FareAmount DECIMAL(10,2),
    IN p_QRHash VARCHAR(255)
)
BEGIN
    DECLARE v_schedule_vehicle INT;
    DECLARE v_seat_vehicle INT;
    DECLARE v_exists INT DEFAULT 0;

    START TRANSACTION;

    SELECT VehicleID INTO v_schedule_vehicle
    FROM SCHEDULE
    WHERE ScheduleID = p_ScheduleID
    FOR UPDATE;

    IF v_schedule_vehicle IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid ScheduleID';
    END IF;

    SELECT VehicleID INTO v_seat_vehicle
    FROM SEAT
    WHERE SeatID = p_SeatID
    FOR UPDATE;

    IF v_seat_vehicle IS NULL OR v_seat_vehicle <> v_schedule_vehicle THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Seat does not belong to the scheduled vehicle';
    END IF;

    SELECT COUNT(*) INTO v_exists
    FROM TICKET
    WHERE ScheduleID = p_ScheduleID
      AND SeatID = p_SeatID
      AND TicketStatus IN ('Pending','Confirmed','Used');

    IF v_exists > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Seat already booked for this schedule';
    END IF;

    INSERT INTO TICKET
        (TicketID, PassengerID, ScheduleID, SeatID, FareAmount, BookingDate, TicketStatus, QRHash)
    VALUES
        (p_TicketID, p_PassengerID, p_ScheduleID, p_SeatID, p_FareAmount,
         CURRENT_TIMESTAMP, 'Pending', p_QRHash);

    COMMIT;
END$$

DELIMITER ;

-- Summary View 1: route-wise revenue and ticket volume.
CREATE VIEW vw_route_revenue AS
SELECT
    r.RouteID,
    r.RouteName,
    r.Source,
    r.Destination,
    COUNT(t.TicketID) AS TicketCount,
    COALESCE(SUM(CASE WHEN p.Status = 'Success' THEN p.Amount ELSE 0 END),0) AS TotalRevenue,
    ROUND(AVG(t.FareAmount),2) AS AverageFare
FROM ROUTE r
LEFT JOIN SCHEDULE s ON s.RouteID = r.RouteID
LEFT JOIN TICKET t ON t.ScheduleID = s.ScheduleID
LEFT JOIN PAYMENT p ON p.TicketID = t.TicketID
GROUP BY r.RouteID, r.RouteName, r.Source, r.Destination;

-- Summary View 2: vehicle operations and maintenance.
CREATE VIEW vw_vehicle_operations AS
SELECT
    v.VehicleID,
    v.RegNo,
    v.Make,
    v.Model,
    v.Status,
    COUNT(DISTINCT s.ScheduleID) AS ScheduleCount,
    COUNT(DISTINCT t.TicketID) AS TicketCount,
    COALESCE(SUM(CASE WHEN p.Status='Success' THEN p.Amount ELSE 0 END),0) AS Revenue,
    COUNT(DISTINCT m.LogID) AS MaintenanceCount,
    MAX(m.ServiceDate) AS LastServiceDate
FROM VEHICLE v
LEFT JOIN SCHEDULE s ON s.VehicleID = v.VehicleID
LEFT JOIN TICKET t ON t.ScheduleID = s.ScheduleID
LEFT JOIN PAYMENT p ON p.TicketID = t.TicketID
LEFT JOIN MAINTENANCE_LOG m ON m.VehicleID = v.VehicleID
GROUP BY v.VehicleID, v.RegNo, v.Make, v.Model, v.Status;
