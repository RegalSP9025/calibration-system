"""
import_excel.py  v2
Reads calibration_template_v2.xlsx and imports into PostgreSQL.
Usage: python scripts/import_excel.py
"""

import glob
import os
from datetime import datetime

try:
    import psycopg2
except ImportError as _err:
    raise ImportError("psycopg2 is required to run this script. Install it with 'pip install psycopg2-binary' or see requirements.txt") from _err

try:
    import openpyxl
except ImportError as _err:
    raise ImportError("openpyxl is required to read Excel files. Install it with 'pip install openpyxl' or see requirements.txt") from _err

try:
    from dotenv import load_dotenv
except ImportError:
    def load_dotenv():
        pass

load_dotenv()

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, os.pardir))
TEMPLATES_DIR = os.path.join(ROOT_DIR, "templates")


def get_template_filepath():
    exact = os.path.join(TEMPLATES_DIR, "calibration_template_v2.xlsx")
    if os.path.exists(exact):
        return exact

    candidates = sorted(glob.glob(os.path.join(TEMPLATES_DIR, "calibration_template_v2*.xlsx")))
    if candidates:
        if len(candidates) > 1:
            print(f"Using first matching template file: {os.path.basename(candidates[0])}")
        return candidates[0]

    raise FileNotFoundError(
        f"No calibration template found in {TEMPLATES_DIR}. "
        "Expected file named calibration_template_v2.xlsx or calibration_template_v2*.xlsx"
    )


# Column index map (0-based) matching template v2
COL = {
    "gage_type":          0,
    "sn_gage_used_to_cal":1,
    "graduation":         2,
    "procedure":          3,
    "procedure_number":   4,
    "date_calibrated":    5,
    "serial_number":      6,
    "manufacturer":       7,
    "model_number":       8,
    "calibrated_by":      9,
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
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", 5432),
        dbname=os.getenv("DB_NAME", "calibration_db"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD")
    )

def parse_date(val):
    if val is None:
        return None
    if hasattr(val, "date"):
        return val.date()
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%m-%d-%Y"):
        try:
            return datetime.strptime(str(val).strip(), fmt).date()
        except ValueError:
            continue
    return None

def str_val(val):
    return str(val).strip() if val is not None else None

def read_excel(filepath):
    wb = openpyxl.load_workbook(filepath, data_only=True)
    ws = wb["MAIN_INPUT"]
    rows = []
    for row in ws.iter_rows(min_row=2, values_only=True):
        if not row[COL["serial_number"]]:
            continue
        rows.append(row)
    return rows

def upsert_gage(cur, row):
    cur.execute("""
        INSERT INTO gages (serial_number, gage_type, manufacturer, model_number,
                           graduation, procedure, procedure_number)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (serial_number) DO UPDATE
        SET gage_type        = EXCLUDED.gage_type,
            manufacturer     = EXCLUDED.manufacturer,
            model_number     = EXCLUDED.model_number,
            graduation       = EXCLUDED.graduation,
            procedure        = EXCLUDED.procedure,
            procedure_number = EXCLUDED.procedure_number
        RETURNING id
    """, (
        str_val(row[COL["serial_number"]]),
        str_val(row[COL["gage_type"]]),
        str_val(row[COL["manufacturer"]]),
        str_val(row[COL["model_number"]]),
        str_val(row[COL["graduation"]]),
        str_val(row[COL["procedure"]]),
        str_val(row[COL["procedure_number"]]),
    ))
    return cur.fetchone()[0]

def insert_calibration(cur, gage_id, row):
    cur.execute("""
        INSERT INTO calibrations (
            gage_id, sn_gage_used_to_cal, date_calibrated, calibrated_by,
            checkpoint_a_value, checkpoint_b_value, checkpoint_c_value,
            status, notes)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
        RETURNING id
    """, (
        gage_id,
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

def insert_measurements(cur, cal_id, row):
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
        if value is None:
            continue
        cur.execute("""
            INSERT INTO calibration_measurements
                (calibration_id, checkpoint, reading_number, value)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (calibration_id, checkpoint, reading_number)
            DO UPDATE SET value = EXCLUDED.value
        """, (cal_id, checkpoint, reading_num, float(value)))

def main():
    filepath = get_template_filepath()
    print(f"Reading {filepath}...")
    rows = read_excel(filepath)
    print(f"Found {len(rows)} record(s).")

    conn = get_connection()
    cur = conn.cursor()
    imported = 0

    for row in rows:
        serial = str_val(row[COL["serial_number"]])
        date   = str_val(row[COL["date_calibrated"]])
        try:
            gage_id = upsert_gage(cur, row)
            cal_id  = insert_calibration(cur, gage_id, row)
            insert_measurements(cur, cal_id, row)
            conn.commit()
            print(f"  âœ“ Serial: {serial}  Date: {date}")
            imported += 1
        except Exception as e:
            conn.rollback()
            print(f"  âœ— Failed Serial: {serial}  Date: {date}  â†’  {e}")

    cur.close()
    conn.close()
    print(f"\nDone. {imported}/{len(rows)} records imported.")

print("DB:", os.getenv("DB_NAME"))
print("PORT:", os.getenv("DB_PORT"))
if __name__ == "__main__":
    main()