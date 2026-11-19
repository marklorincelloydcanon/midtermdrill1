-- HarborWing Air - schema (MySQL 8.0.16 or newer, because of CHECK constraints)
-- Run this file first. It deletes and rebuilds the whole database.
-- All times are stored in UTC.

DROP DATABASE IF EXISTS harborwing;
CREATE DATABASE harborwing CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE harborwing;

-- Reference codes (airline_code, aircraft_type_code, status codes, ticket type,
-- travel class) are managed OUTSIDE this database. They are plain columns with
-- no foreign keys, as the drill allows.

-- 1. Booking agents
CREATE TABLE booking_agents (
  agent_id      INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name          VARCHAR(100) NOT NULL,
  other_details VARCHAR(255) NULL,
  PRIMARY KEY (agent_id)
) ENGINE=InnoDB;

-- 2. Passengers
CREATE TABLE passengers (
  passenger_id        INT UNSIGNED NOT NULL AUTO_INCREMENT,
  first_name          VARCHAR(50)  NOT NULL,
  second_name         VARCHAR(50)  NULL,
  last_name           VARCHAR(50)  NOT NULL,
  phone_number        VARCHAR(30)  NULL,
  email_address       VARCHAR(120) NOT NULL,
  address_line_1      VARCHAR(120) NULL,
  address_line_2      VARCHAR(120) NULL,
  city                VARCHAR(80)  NULL,
  state_province_county VARCHAR(80) NULL,
  country             VARCHAR(80)  NULL,
  other_details       VARCHAR(255) NULL,
  PRIMARY KEY (passenger_id),
  UNIQUE KEY uq_passengers_email (email_address),
  KEY idx_passengers_name (last_name, first_name)
) ENGINE=InnoDB;

-- 3. Airports
CREATE TABLE airports (
  airport_code  CHAR(3)      NOT NULL,
  name          VARCHAR(120) NOT NULL,
  location      VARCHAR(120) NOT NULL,
  other_details VARCHAR(255) NULL,
  PRIMARY KEY (airport_code)
) ENGINE=InnoDB;

-- 4. Calendar dates
CREATE TABLE calendar_dates (
  calendar_date   DATE    NOT NULL,
  day_of_month    TINYINT UNSIGNED NOT NULL,
  is_business_day BOOLEAN NOT NULL,
  PRIMARY KEY (calendar_date),
  CONSTRAINT ck_calendar_day CHECK (day_of_month BETWEEN 1 AND 31)
) ENGINE=InnoDB;

-- 5. Flight schedules (flight_number is treated as the unique schedule id)
CREATE TABLE flight_schedules (
  flight_number       VARCHAR(10) NOT NULL,
  airline_code        VARCHAR(5)  NOT NULL,
  aircraft_type_code  VARCHAR(10) NOT NULL,
  origin_airport      CHAR(3)     NOT NULL,
  destination_airport CHAR(3)     NOT NULL,
  scheduled_departure DATETIME    NOT NULL,
  scheduled_arrival   DATETIME    NOT NULL,
  PRIMARY KEY (flight_number),
  KEY idx_sched_route (origin_airport, destination_airport),
  KEY idx_sched_departure (scheduled_departure),
  CONSTRAINT fk_sched_origin FOREIGN KEY (origin_airport)
    REFERENCES airports (airport_code) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_sched_dest FOREIGN KEY (destination_airport)
    REFERENCES airports (airport_code) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT ck_sched_airports CHECK (origin_airport <> destination_airport),
  CONSTRAINT ck_sched_times CHECK (scheduled_arrival > scheduled_departure)
) ENGINE=InnoDB;

-- 6. Flight legs (actual times are NULL until the flight operates)
CREATE TABLE flight_legs (
  leg_id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  flight_number       VARCHAR(10)  NOT NULL,
  origin_airport      CHAR(3)      NOT NULL,
  destination_airport CHAR(3)      NOT NULL,
  actual_departure    DATETIME     NULL,
  actual_arrival      DATETIME     NULL,
  PRIMARY KEY (leg_id),
  KEY idx_legs_flight (flight_number),
  KEY idx_legs_route (origin_airport, destination_airport),
  CONSTRAINT fk_legs_flight FOREIGN KEY (flight_number)
    REFERENCES flight_schedules (flight_number) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_legs_origin FOREIGN KEY (origin_airport)
    REFERENCES airports (airport_code) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_legs_dest FOREIGN KEY (destination_airport)
    REFERENCES airports (airport_code) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT ck_legs_airports CHECK (origin_airport <> destination_airport),
  CONSTRAINT ck_legs_times CHECK (
    actual_departure IS NULL OR actual_arrival IS NULL
    OR actual_arrival > actual_departure)
) ENGINE=InnoDB;

-- 7. Flight costs (one row per flight + aircraft type + start date)
CREATE TABLE flight_costs (
  flight_number      VARCHAR(10)  NOT NULL,
  aircraft_type_code VARCHAR(10)  NOT NULL,
  valid_from         DATE         NOT NULL,
  valid_to           DATE         NOT NULL,
  cost_amount        DECIMAL(10,2) NOT NULL,
  PRIMARY KEY (flight_number, aircraft_type_code, valid_from),
  KEY idx_costs_valid_from (valid_from),
  KEY idx_costs_valid_to (valid_to),
  CONSTRAINT fk_costs_flight FOREIGN KEY (flight_number)
    REFERENCES flight_schedules (flight_number) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT fk_costs_from FOREIGN KEY (valid_from)
    REFERENCES calendar_dates (calendar_date) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_costs_to FOREIGN KEY (valid_to)
    REFERENCES calendar_dates (calendar_date) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT ck_costs_dates  CHECK (valid_to >= valid_from),
  CONSTRAINT ck_costs_amount CHECK (cost_amount >= 0)
) ENGINE=InnoDB;

-- 8. Reservations
CREATE TABLE reservations (
  reservation_id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  passenger_id           INT UNSIGNED NOT NULL,
  agent_id               INT UNSIGNED NULL,
  reservation_status_code VARCHAR(10) NOT NULL,
  ticket_type_code       VARCHAR(10)  NOT NULL,
  travel_class_code      VARCHAR(10)  NOT NULL,
  created_at             DATETIME     NOT NULL,
  party_size             SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (reservation_id),
  KEY idx_res_passenger (passenger_id),
  KEY idx_res_agent (agent_id),
  KEY idx_res_created (created_at),
  CONSTRAINT fk_res_passenger FOREIGN KEY (passenger_id)
    REFERENCES passengers (passenger_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_res_agent FOREIGN KEY (agent_id)
    REFERENCES booking_agents (agent_id) ON DELETE SET NULL ON UPDATE RESTRICT,
  CONSTRAINT ck_res_party CHECK (party_size > 0)
) ENGINE=InnoDB;

-- 9. Payments
CREATE TABLE payments (
  payment_id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  payment_status_code VARCHAR(10)  NOT NULL,
  payment_date        DATETIME     NOT NULL,
  payment_amount      DECIMAL(10,2) NOT NULL,
  PRIMARY KEY (payment_id),
  KEY idx_pay_date (payment_date),
  CONSTRAINT ck_pay_amount CHECK (payment_amount > 0)
) ENGINE=InnoDB;

-- 10. Linking table: reservation <-> payment (many to many)
CREATE TABLE reservation_payments (
  reservation_id INT UNSIGNED NOT NULL,
  payment_id     INT UNSIGNED NOT NULL,
  PRIMARY KEY (reservation_id, payment_id),
  KEY idx_rp_payment (payment_id),
  CONSTRAINT fk_rp_res FOREIGN KEY (reservation_id)
    REFERENCES reservations (reservation_id) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT fk_rp_pay FOREIGN KEY (payment_id)
    REFERENCES payments (payment_id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB;

-- 11. Linking table: reservation <-> flight leg (many to many)
CREATE TABLE reservation_legs (
  reservation_id INT UNSIGNED NOT NULL,
  leg_id         INT UNSIGNED NOT NULL,
  PRIMARY KEY (reservation_id, leg_id),
  KEY idx_rl_leg (leg_id),
  CONSTRAINT fk_rl_res FOREIGN KEY (reservation_id)
    REFERENCES reservations (reservation_id) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT fk_rl_leg FOREIGN KEY (leg_id)
    REFERENCES flight_legs (leg_id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB;
