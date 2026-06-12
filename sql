-- 1. Clean up any existing versions of these tables if they exist
DROP TABLE IF EXISTS latest_calibration_measurements;
DROP TABLE IF EXISTS active_calibrations;

-- 2. Create the Master Table: Tracks the asset and its single latest calibration event
CREATE TABLE active_calibrations (
    id                  SERIAL PRIMARY KEY,
    serial_number       VARCHAR(50) UNIQUE NOT NULL,   -- The gage's physical serial number
    gage_type           VARCHAR(100),                  -- e.g. O.D. Micrometer
    manufacturer        VARCHAR(100),                  -- e.g. Starrett
    model_number        VARCHAR(100),                  -- e.g. No.436
    graduation          VARCHAR(20),                   -- e.g. 0.001
    procedure_name      VARCHAR(50),                   -- e.g. DP-140
    procedure_number    VARCHAR(50),                   -- e.g. 04-201
    sn_gage_used_to_cal VARCHAR(50),                   -- Master standard tool serial number
    date_calibrated     DATE NOT NULL,                 -- Date of the latest calibration event
    calibrated_by       VARCHAR(50),                   -- Inspector initials (e.g. ER, CF)
    checkpoint_a_value  VARCHAR(20),                   -- Target value for A (e.g. 9.100)
    checkpoint_b_value  VARCHAR(20),                   -- Target value for B (e.g. 9.500)
    checkpoint_c_value  VARCHAR(20),                   -- Target value for C (e.g. 9.900)
    status              VARCHAR(20) DEFAULT 'READY',   -- READY / PENDING / FAILED
    notes               TEXT,                          -- Any specific comments
    updated_at          TIMESTAMP DEFAULT NOW()        -- Tracks when this row was last touched
);

-- 3. Create the Measurements Run Table: Tracks the individual trial runs linked to the gage
CREATE TABLE latest_calibration_measurements (
    id                  SERIAL PRIMARY KEY,
    gage_serial         VARCHAR(50) REFERENCES active_calibrations(serial_number) ON DELETE CASCADE,
    checkpoint          CHAR(1) NOT NULL,              -- 'A', 'B', or 'C'
    reading_number      INT NOT NULL,                  -- 1, 2, or 3
    value               NUMERIC(10, 5),                -- The raw deviation decimal value (e.g. -0.0001)
    UNIQUE (gage_serial, checkpoint, reading_number)   -- Prevents duplicate entries for the exact same run
);
