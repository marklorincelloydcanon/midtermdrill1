USE harborwing;

-- ===== Row count of every table (each must show 50 or more) =====
SELECT 'booking_agents' AS table_name, COUNT(*) AS row_count FROM booking_agents
UNION ALL SELECT 'passengers',           COUNT(*) FROM passengers
UNION ALL SELECT 'airports',             COUNT(*) FROM airports
UNION ALL SELECT 'calendar_dates',       COUNT(*) FROM calendar_dates
UNION ALL SELECT 'flight_schedules',     COUNT(*) FROM flight_schedules
UNION ALL SELECT 'flight_legs',          COUNT(*) FROM flight_legs
UNION ALL SELECT 'flight_costs',         COUNT(*) FROM flight_costs
UNION ALL SELECT 'reservations',         COUNT(*) FROM reservations
UNION ALL SELECT 'payments',             COUNT(*) FROM payments
UNION ALL SELECT 'reservation_payments', COUNT(*) FROM reservation_payments
UNION ALL SELECT 'reservation_legs',     COUNT(*) FROM reservation_legs;

-- Change these values to try other rows
SET @res_id  = 1;
SET @leg_id  = 1;
SET @flight  = (SELECT flight_number FROM flight_costs ORDER BY valid_from LIMIT 1);
SET @aircraft = (SELECT aircraft_type_code FROM flight_costs ORDER BY valid_from LIMIT 1);
SET @on_date = '2026-08-15';

-- ===== Query 1: a reservation with passenger, agent, payments and legs =====
-- Payments and legs are summed in SEPARATE sub-queries. If we joined both
-- tables directly, every payment would repeat once per leg and the total
-- would be too big.
SELECT r.reservation_id,
       CONCAT(p.first_name, ' ', p.last_name) AS passenger,
       COALESCE(a.name, 'Direct booking')     AS booking_agent,
       r.party_size,
       COALESCE(pay.payment_count, 0)         AS payment_count,
       COALESCE(pay.total_paid, 0)            AS total_paid,
       COALESCE(lg.leg_count, 0)              AS leg_count,
       lg.legs
FROM reservations r
JOIN passengers p ON p.passenger_id = r.passenger_id
LEFT JOIN booking_agents a ON a.agent_id = r.agent_id
LEFT JOIN (SELECT rp.reservation_id,
                  COUNT(*) AS payment_count,
                  SUM(py.payment_amount) AS total_paid
           FROM reservation_payments rp
           JOIN payments py ON py.payment_id = rp.payment_id
           GROUP BY rp.reservation_id) pay ON pay.reservation_id = r.reservation_id
LEFT JOIN (SELECT rl.reservation_id,
                  COUNT(*) AS leg_count,
                  GROUP_CONCAT(CONCAT(fl.flight_number, ' ', fl.origin_airport, '->', fl.destination_airport)
                               ORDER BY fl.leg_id SEPARATOR '; ') AS legs
           FROM reservation_legs rl
           JOIN flight_legs fl ON fl.leg_id = rl.leg_id
           GROUP BY rl.reservation_id) lg ON lg.reservation_id = r.reservation_id
WHERE r.reservation_id = @res_id;

-- ===== Query 2: reservations that use a particular leg =====
SELECT r.reservation_id, r.reservation_status_code, r.party_size,
       p.first_name, p.last_name
FROM reservation_legs rl
JOIN reservations r ON r.reservation_id = rl.reservation_id
JOIN passengers p   ON p.passenger_id = r.passenger_id
WHERE rl.leg_id = @leg_id
ORDER BY r.reservation_id;

-- ===== Query 3: payments linked to a reservation =====
SELECT py.payment_id, py.payment_status_code, py.payment_date, py.payment_amount
FROM reservation_payments rp
JOIN payments py ON py.payment_id = rp.payment_id
WHERE rp.reservation_id = @res_id
ORDER BY py.payment_date;

-- ===== Query 4: flight cost for a flight, aircraft type and date =====
SELECT flight_number, aircraft_type_code, valid_from, valid_to, cost_amount
FROM flight_costs
WHERE flight_number = @flight
  AND aircraft_type_code = @aircraft
  AND @on_date BETWEEN valid_from AND valid_to;
