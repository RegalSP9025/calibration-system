

DROP TABLE IF EXISTS calibration_measurements;
DROP TABLE IF EXISTS calibrations;
DROP TABLE IF EXISTS gages;

CREATE TABLE gages (
    id              SERIAL PRIMARY KEY,
    serial_number   VARCHAR(50) UNIQUE NOT NULL,
    gage_type       VARCHAR(100),                  -- e.g. O.D. Micrometer
    manufacturer    VARCHAR(100),                  -- e.g. Starrett
    model_number    VARCHAR(100),                  -- e.g. No.436
    graduation      VARCHAR(20),                   -- e.g. 0.001
    procedure       VARCHAR(50),                   -- e.g. DP-140
    procedure_number VARCHAR(50),                  -- e.g. 04-201
    created_at      TIMESTAMP DEFAULT NOW()
);


CREATE TABLE calibrations (
    id                  SERIAL PRIMARY KEY,
    gage_id             INT REFERENCES gages(id) ON DELETE CASCADE,
    sn_gage_used_to_cal VARCHAR(50),               -- e.g. 95901
    date_calibrated     DATE NOT NULL,
    calibrated_by       VARCHAR(50),               -- initials e.g. ER, CF
    checkpoint_a_value  VARCHAR(20),               -- e.g. 9.100
    checkpoint_b_value  VARCHAR(20),               -- e.g. 9.500
    checkpoint_c_value  VARCHAR(20),               -- e.g. 9.900
    status              VARCHAR(20) DEFAULT 'READY',
    notes               TEXT,
    created_at          TIMESTAMP DEFAULT NOW()
);


CREATE TABLE calibration_measurements (
    id              SERIAL PRIMARY KEY,
    calibration_id  INT REFERENCES calibrations(id) ON DELETE CASCADE,
    checkpoint      CHAR(1) NOT NULL,              -- A, B, or C
    reading_number  INT NOT NULL,                  -- 1, 2, or 3
    value           NUMERIC(10, 5),                -- e.g. -0.0001
    UNIQUE (calibration_id, checkpoint, reading_number)
);

CREATE VIEW calibration_summary AS
SELECT
    g.serial_number,
    g.gage_type,
    g.manufacturer,
    g.model_number,
    g.graduation,
    g.procedure,
    g.procedure_number,
    c.sn_gage_used_to_cal,
    c.date_calibrated,
    c.calibrated_by,
    c.status,
    c.notes,
    c.checkpoint_a_value,
    MAX(CASE WHEN m.checkpoint='A' AND m.reading_number=1 THEN m.value END) AS A1,
    MAX(CASE WHEN m.checkpoint='A' AND m.reading_number=2 THEN m.value END) AS A2,
    MAX(CASE WHEN m.checkpoint='A' AND m.reading_number=3 THEN m.value END) AS A3,
    c.checkpoint_b_value,
    MAX(CASE WHEN m.checkpoint='B' AND m.reading_number=1 THEN m.value END) AS B1,
    MAX(CASE WHEN m.checkpoint='B' AND m.reading_number=2 THEN m.value END) AS B2,
    MAX(CASE WHEN m.checkpoint='B' AND m.reading_number=3 THEN m.value END) AS B3,
    c.checkpoint_c_value,
    MAX(CASE WHEN m.checkpoint='C' AND m.reading_number=1 THEN m.value END) AS C1,
    MAX(CASE WHEN m.checkpoint='C' AND m.reading_number=2 THEN m.value END) AS C2,
    MAX(CASE WHEN m.checkpoint='C' AND m.reading_number=3 THEN m.value END) AS C3
FROM gages g
JOIN calibrations c ON c.gage_id = g.id
LEFT JOIN calibration_measurements m ON m.calibration_id = c.id
GROUP BY g.id, c.id
ORDER BY c.date_calibrated DESC;
