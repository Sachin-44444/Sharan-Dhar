-- IEFMDB TAE-2 ADVANCED QUERIES & OPTIMIZATION
USE IEFMDB;

-- ============================================================
-- 1. MULTI-TABLE JOIN
-- ============================================================
SELECT
    t.TicketID,
    CONCAT(p.FirstName,' ',p.LastName) AS PassengerName,
    r.RouteName,
    r.Source,
    r.Destination,
    s.DepartureTime,
    CONCAT(v.Make,' ',v.Model) AS Vehicle,
    CONCAT(d.FirstName,' ',d.LastName) AS DriverName,
    se.SeatNo,
    t.FareAmount,
    pay.Status AS PaymentStatus
FROM TICKET t
JOIN PASSENGER p ON p.PassengerID = t.PassengerID
JOIN SCHEDULE s ON s.ScheduleID = t.ScheduleID
JOIN ROUTE r ON r.RouteID = s.RouteID
JOIN VEHICLE v ON v.VehicleID = s.VehicleID
JOIN DRIVER d ON d.DriverID = s.DriverID
JOIN SEAT se ON se.SeatID = t.SeatID
LEFT JOIN PAYMENT pay ON pay.TicketID = t.TicketID
ORDER BY s.DepartureTime DESC;

-- ============================================================
-- 2. CORRELATED SUBQUERY
-- Vehicles whose mileage is above the average mileage
-- for their own fuel type.
-- ============================================================
SELECT
    v.VehicleID,
    v.RegNo,
    v.FuelType,
    v.CurrentMileage
FROM VEHICLE v
WHERE v.CurrentMileage >
(
    SELECT AVG(v2.CurrentMileage)
    FROM VEHICLE v2
    WHERE v2.FuelType = v.FuelType
)
ORDER BY v.FuelType, v.CurrentMileage DESC;

-- ============================================================
-- 3. AGGREGATE ANALYTICS
-- ============================================================
SELECT
    r.RouteID,
    r.RouteName,
    COUNT(t.TicketID) AS TicketsSold,
    COALESCE(SUM(CASE WHEN p.Status='Success' THEN p.Amount ELSE 0 END),0) AS Revenue
FROM ROUTE r
JOIN SCHEDULE s ON s.RouteID = r.RouteID
LEFT JOIN TICKET t ON t.ScheduleID = s.ScheduleID
LEFT JOIN PAYMENT p ON p.TicketID = t.TicketID
GROUP BY r.RouteID, r.RouteName
ORDER BY Revenue DESC;

-- ============================================================
-- 4. WINDOW FUNCTION
-- ============================================================
SELECT
    RouteID,
    RouteName,
    TicketCount,
    TotalRevenue,
    RANK() OVER (ORDER BY TotalRevenue DESC) AS RevenueRank
FROM vw_route_revenue;

-- ============================================================
-- 5. DATABASE VIEWS
-- ============================================================
SELECT * FROM vw_route_revenue ORDER BY TotalRevenue DESC;
SELECT * FROM vw_vehicle_operations ORDER BY Revenue DESC;

-- ============================================================
-- 6. STORED PROCEDURE EXAMPLE
-- Run with IDs that are not already used.
-- Uncomment to execute:
-- CALL BOOK_TICKET(9999, 1, 1, 1, 450.00, 'QR-DEMO-9999');
-- ============================================================

-- ============================================================
-- 7. TRIGGER DEMONSTRATION
-- Insert a maintenance record with a due date in the past.
-- The trigger should change VEHICLE.Status to 'In-Shop'.
-- Uncomment to execute:
-- INSERT INTO MAINTENANCE_LOG
-- (LogID, VehicleID, ServiceDate, ServiceType, Description, Cost, NextServiceDue, MileageAtService)
-- VALUES
-- (9999, 1, CURDATE(), 'Trigger Test', 'TAE-2 trigger demonstration', 1000.00, CURDATE(), 12345.00);
-- SELECT VehicleID, Status FROM VEHICLE WHERE VehicleID=1;
-- ============================================================

-- ============================================================
-- 8. EXPLAIN BENCHMARK #1 — BEFORE INDEX
-- Run this section BEFORE creating the non-primary indexes.
-- ============================================================
EXPLAIN
SELECT
    r.RouteID,
    r.RouteName,
    COUNT(t.TicketID) AS TicketCount,
    COALESCE(SUM(CASE WHEN p.Status='Success' THEN p.Amount ELSE 0 END),0) AS Revenue
FROM ROUTE r
JOIN SCHEDULE s ON s.RouteID = r.RouteID
JOIN TICKET t ON t.ScheduleID = s.ScheduleID
JOIN PAYMENT p ON p.TicketID = t.TicketID
WHERE r.RouteID BETWEEN 1 AND 80
  AND p.Status = 'Success'
GROUP BY r.RouteID, r.RouteName
ORDER BY Revenue DESC;

-- ============================================================
-- EXPLAIN BENCHMARK #2 — BEFORE INDEX
-- ============================================================
EXPLAIN
SELECT
    t.TicketID,
    p.FirstName,
    p.LastName,
    r.RouteName,
    s.DepartureTime,
    pay.Amount
FROM TICKET t
JOIN PASSENGER p ON p.PassengerID=t.PassengerID
JOIN SCHEDULE s ON s.ScheduleID=t.ScheduleID
JOIN ROUTE r ON r.RouteID=s.RouteID
JOIN PAYMENT pay ON pay.TicketID=t.TicketID
WHERE s.RouteID BETWEEN 1 AND 80
  AND pay.Status='Success'
  AND s.DepartureTime >= '2026-03-01';

-- ============================================================
-- 9. ADD NON-PRIMARY INDEXES
-- These are intentionally NOT in schema.sql so that the
-- before/after EXPLAIN comparison is meaningful.
-- ============================================================
CREATE INDEX idx_schedule_route_departure
    ON SCHEDULE(RouteID, DepartureTime);

CREATE INDEX idx_ticket_schedule
    ON TICKET(ScheduleID);

CREATE INDEX idx_payment_ticket_status
    ON PAYMENT(TicketID, Status);

-- ============================================================
-- 10. EXPLAIN BENCHMARK #1 — AFTER INDEX
-- ============================================================
EXPLAIN
SELECT
    r.RouteID,
    r.RouteName,
    COUNT(t.TicketID) AS TicketCount,
    COALESCE(SUM(CASE WHEN p.Status='Success' THEN p.Amount ELSE 0 END),0) AS Revenue
FROM ROUTE r
JOIN SCHEDULE s ON s.RouteID = r.RouteID
JOIN TICKET t ON t.ScheduleID = s.ScheduleID
JOIN PAYMENT p ON p.TicketID = t.TicketID
WHERE r.RouteID BETWEEN 1 AND 80
  AND p.Status = 'Success'
GROUP BY r.RouteID, r.RouteName
ORDER BY Revenue DESC;

-- ============================================================
-- 11. EXPLAIN BENCHMARK #2 — AFTER INDEX
-- ============================================================
EXPLAIN
SELECT
    t.TicketID,
    p.FirstName,
    p.LastName,
    r.RouteName,
    s.DepartureTime,
    pay.Amount
FROM TICKET t
JOIN PASSENGER p ON p.PassengerID=t.PassengerID
JOIN SCHEDULE s ON s.ScheduleID=t.ScheduleID
JOIN ROUTE r ON r.RouteID=s.RouteID
JOIN PAYMENT pay ON pay.TicketID=t.TicketID
WHERE s.RouteID BETWEEN 1 AND 80
  AND pay.Status='Success'
  AND s.DepartureTime >= '2026-03-01';

-- Optional: inspect created indexes.
SHOW INDEX FROM SCHEDULE;
SHOW INDEX FROM TICKET;
SHOW INDEX FROM PAYMENT;
