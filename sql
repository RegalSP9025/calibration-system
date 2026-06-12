import os
import glob
from datetime import datetime

# Safe imports with fallback errors to help with training troubleshooting
try:
    import psycopg2
except ImportError as _err:
    psycopg2 = None
    _psycopg2_error = ImportError("psycopg2 is required. Run 'pip install psycopg2-binary'")

try:
    import openpyxl
except ImportError as _err:
    openpyxl = None
    _openpyxl_error = ImportError("openpyxl is required. Run 'pip install openpyxl'")

try:
    from dotenv import load_dotenv
except ImportError:
    def load_dotenv():
        return None

load_dotenv()

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, os.pardir))
TEMPLATES_DIR = os.path.join(ROOT_DIR, "templates")

def get_template_filepath():
    exact = os.path.join(TEMPLATES_DIR, "calibration_template_v2.xlsx")
    if os.path.exists(exact):
        return exact

    candidates = sorted(glob.glob(os.path.join(TEMPLATES_DIR, "calibration_template*.xlsx")))
    if candidates:
        return candidates[0]

    raise FileNotFoundError(
        f"No calibration template found in {TEMPLATES_DIR}. "
        "Expected an Excel file inside the templates folder."
    )

# Column index mapping (0-based) matching your original Excel layout explicitly
COL = {
    "gage_type":           0,
    "sn_gage_used_to_cal": 1,
    "graduation":          2,
    "procedure":           3,
    "procedure_number":    4,
    "date_calibrated":     5,
    "serial_number":       6,
    "manufacturer":        7,
    "model_number":        8,
    "calibrated_by":       9,
    "checkpoint_a_value": 10,
    "A1": 11, "A2": 12, "A3": 13,
    "checkpoint_b_value": 14,
    "B1": 15, "B2": 16, "B3": 17,
    "checkpoint_c_value": 18,
    "C1": 19, "C2": 20, "C3": 21,
    "status":             22,
    "notes":              23,
}

def get_connection():
    if psycopg2 is None:
        raise _psycopg2_error
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", 5432),
        dbname=os.getenv("DB_NAME", "postgres"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD")
    )

def parse_date(val):
    if val is None:
        return None
    if hasattr(val, "date"):
        return val.date()
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%m-%d-%Y", "%m/%d/%y"):
        try:
            return datetime.strptime(str(val).strip(), fmt).date()
        except ValueError:
            continue
    return None

def str_val(val):
    return str(val).strip() if val is not None else None

def read_excel(filepath):
    if openpyxl is None:
        raise _openpyxl_error
    wb = openpyxl.load_workbook(filepath, data_only=True)
    ws = wb["MAIN_INPUT"]
    rows = []
    for row in ws.iter_rows(min_row=2, values_only=True):
        # If there's no serial number on this row, skip it
        if not row or len(row) <= COL["serial_number"] or not row[COL["serial_number"]]:
            continue
        rows.append(row)
    return rows

def upsert_active_calibration(cur, row):
    """
    Inserts a row, or updates it if the serial number already exists.
    This guarantees ONLY the single most recent record exists per gage.
    """
    cur.execute("""
        INSERT INTO active_calibrations (
            serial_number, gage_type, manufacturer, model_number, graduation,
            procedure_name, procedure_number, sn_gage_used_to_cal, 
            date_calibrated, calibrated_by, checkpoint_a_value, 
            checkpoint_b_value, checkpoint_c_value, status, notes, updated_at
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
        ON CONFLICT (serial_number) DO UPDATE SET
            gage_type           = EXCLUDED.gage_type,
            manufacturer        = EXCLUDED.manufacturer,
            model_number        = EXCLUDED.model_number,
            graduation          = EXCLUDED.graduation,
            procedure_name      = EXCLUDED.procedure_name,
            procedure_number    = EXCLUDED.procedure_number,
            sn_gage_used_to_cal = EXCLUDED.sn_gage_used_to_cal,
            date_calibrated     = EXCLUDED.date_calibrated,
            calibrated_by       = EXCLUDED.calibrated_by,
            checkpoint_a_value  = EXCLUDED.checkpoint_a_value,
            checkpoint_b_value  = EXCLUDED.checkpoint_b_value,
            checkpoint_c_value  = EXCLUDED.checkpoint_c_value,
            status              = EXCLUDED.status,
            notes               = EXCLUDED.notes,
            updated_at          = NOW()
        RETURNING serial_number;
    """, (
        str_val(row[COL["serial_number"]]),
        str_val(row[COL["gage_type"]]),
        str_val(row[COL["manufacturer"]]),
        str_val(row[COL["model_number"]]),
        str_val(row[COL["graduation"]]),
        str_val(row[COL["procedure"]]),
        str_val(row[COL["procedure_number"]]),
        str_val(row[COL["sn_gage_used_to_cal"]]),
        parse_date(row[COL["date_calibrated"]]),
        str_val(row[COL["calibrated_by"]]),
        str_val(row[COL["checkpoint_a_value"]]),
        str_val(row[COL["checkpoint_b_value"]]),
        str_val(row[COL["checkpoint_c_value"]]),
        str_val(row[COL["status"]]) or "READY",
        str_val(row[COL["notes"]]),
    ))
    return cur.fetchone()[0]

def insert_measurements(cur, serial_num, row):
    """
    Clears out old run measurements for this serial number and inserts the new ones.
    """
    # First, delete old measurements for this specific tool to keep runs fresh
    cur.execute("DELETE FROM latest_calibration_measurements WHERE gage_serial = %s", (serial_num,))
    
    mapping = [
        ("A", 1, row[COL["A1"]]),
        ("A", 2, row[COL["A2"]]),
        ("A", 3, row[COL["A3"]]),
        ("B", 1, row[COL["B1"]]),
        ("B", 2, row[COL["B2"]]),
        ("B", 3, row[COL["B3"]]),
        ("C", 1, row[COL["C1"]]),
        ("C", 2, row[COL["C2"]]),
        ("C", 3, row[COL["C3"]]),
    ]
    
    for checkpoint, reading_num, value in mapping:
        if value is None or str(value).strip() == "":
            continue
        cur.execute("""
            INSERT INTO latest_calibration_measurements (gage_serial, checkpoint, reading_number, value)
            VALUES (%s, %s, %s, %s)
        """, (serial_num, checkpoint, reading_num, float(value)))

def main():
    try:
        filepath = get_template_filepath()
    except FileNotFoundError as e:
        print(f"\n[ERROR] {e}")
        return

    print(f"Reading data from: {os.path.basename(filepath)}...")
    rows = read_excel(filepath)
    print(f"Found {len(rows)} valid row(s) to process.")

    print("Connecting to Supabase...")
    conn = get_connection()
    cur = conn.cursor()
    imported = 0

    for row in rows:
        serial = str_val(row[COL["serial_number"]])
        date_str = str_val(row[COL["date_calibrated"]])
        try:
            # 1. Sync the core gage/cal row (Insert or Overwrite)
            serial_num = upsert_active_calibration(cur, row)
            
            # 2. Re-populate the 3-run trial measurements table
            insert_measurements(cur, serial_num, row)
            
            conn.commit()
            print(f"  ✓ Synchronized Serial: {serial} (Cal Date: {date_str})")
            imported += 1
        except Exception as e:
            conn.rollback()
            print(f"  ✕ Failed Syncing Serial: {serial} → {e}")

    cur.close()
    conn.close()
    print(f"\nDone! Successfully synchronized {imported}/{len(rows)} rows to your Supabase Database.\n")

if __name__ == "__main__":
    main()
