-- Create the main table matching your Excel template columns explicitly
CREATE TABLE public."RegalPatelTest" (
    id                  SERIAL PRIMARY KEY,
    serial_number       VARCHAR(50) UNIQUE NOT NULL,   -- The unique tool key
    gage_type           VARCHAR(100),                  -- e.g., O.D. Micrometer
    manufacturer        VARCHAR(100),                  -- e.g., Starrett
    model_number        VARCHAR(100),                  -- e.g., No.436
    graduation          VARCHAR(20),                   
    procedure_name      VARCHAR(50),                   
    procedure_number    VARCHAR(50),                   
    sn_gage_used_to_cal VARCHAR(50),                   
    date_calibrated     DATE,                          -- Tracks the 2026 date
    calibrated_by       VARCHAR(50),                   -- Inspector initials
    checkpoint_a_value  VARCHAR(20),                   -- Target values
    checkpoint_b_value  VARCHAR(20),                   
    checkpoint_c_value  VARCHAR(20),                   
    status              VARCHAR(20) DEFAULT 'READY',   -- READY / PENDING / FAILED
    notes               TEXT,                          
    updated_at          TIMESTAMP DEFAULT NOW()        
);
