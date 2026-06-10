import os
from datetime import datetime
import psycopg2
from dotenv import load_dotenv

load_dotenv()

def get_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "calibration_db"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD")
    )

def save_to_db(payload):
    conn = get_connection()
    cur = conn.cursor()
    try:
        # 1. Upsert Gage Asset Data
        cur.execute("""
            INSERT INTO gages (serial_number, gage_type, manufacturer, model_number, graduation, procedure, procedure_number)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (serial_number) DO UPDATE SET
                gage_type = EXCLUDED.gage_type,
                manufacturer = EXCLUDED.manufacturer,
                model_number = EXCLUDED.model_number,
                graduation = EXCLUDED.graduation,
                procedure = EXCLUDED.procedure,
                procedure_number = EXCLUDED.procedure_number
            RETURNING id;
        """, (payload['serial_number'], payload['gage_type'], payload['manufacturer'], 
              payload['model_number'], payload['graduation'], payload['procedure'], payload['procedure_number']))
        
        gage_id = cur.fetchone()[0]

        # 2. Insert Historical Calibration Log Entries
        for cal in payload['history']:
            cur.execute("""
                INSERT INTO calibrations (gage_id, sn_gage_used_to_cal, date_calibrated, calibrated_by,
                                         checkpoint_a_value, checkpoint_b_value, checkpoint_c_value, status, notes)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING id;
            """, (gage_id, payload['sn_gage_used_to_cal'], cal['date'], cal['by'],
                  payload['checkpoints']['A'], payload['checkpoints']['B'], payload['checkpoints']['C'],
                  cal['status'], cal['notes']))
            
            cal_id = cur.fetchone()[0]

            # 3. Insert Raw Runs Matrix Info
            for cp in ['A', 'B', 'C']:
                for idx, reading in enumerate(cal['readings'][cp]):
                    if reading is not None:
                        cur.execute("""
                            INSERT INTO calibration_measurements (calibration_id, checkpoint, reading_number, value)
                            VALUES (%s, %s, %s, %s)
                            ON CONFLICT (calibration_id, checkpoint, reading_number) DO UPDATE SET value = EXCLUDED.value;
                        """, (cal_id, cp, idx + 1, float(reading)))
        
        conn.commit()
        print("\n=== Data Successfully Synchronized to Postgres Database! ===")
    except Exception as e:
        conn.rollback()
        print(f"\n[ERROR] Database Write Failure: {e}")
    finally:
        cur.close()
        conn.close()

def quick_prompt():
    print("--- FAST TRACK CALIBRATION DATA ENTRY SYSTEM ---")
    data = {}
    data['serial_number'] = input("Gage Serial Number: ").strip()
    data['gage_type'] = input("Gage Type (e.g. O.D. Micrometer): ").strip()
    data['manufacturer'] = input("Manufacturer: ").strip()
    data['model_number'] = input("Model #: ").strip()
    data['graduation'] = input("Graduation: ").strip()
    data['procedure'] = input("Procedure: ").strip()
    data['procedure_number'] = input("Procedure Number: ").strip()
    data['sn_gage_used_to_cal'] = input("S/N Of Master Gage used to Calibrate: ").strip()
    
    data['checkpoints'] = {
        'A': input("Checkpoint A Target Value (e.g. 9.100): ").strip(),
        'B': input("Checkpoint B Target Value (e.g. 9.500): ").strip(),
        'C': input("Checkpoint C Target Value (e.g. 9.900): ").strip()
    }
    
    data['history'] = []
    
    while True:
        print("\n--- Adding Calibration Event Entry ---")
        cal_date = input("Date Calibrated (MM/DD/YYYY) [or press Enter to wrap up]: ").strip()
        if not cal_date:
            break
            
        cal_by = input("Calibrated By (Initials): ").strip()
        status = input("Status (PASSED/FAILED/READY) [Default: PASSED]: ").strip() or "PASSED"
        notes = input("Notes: ").strip()
        
        readings = {'A': [], 'B': [], 'C': []}
        for cp in ['A', 'B', 'C']:
            print(f"  Enter 3 Run Readings for Checkpoint {cp} (Target: {data['checkpoints'][cp]}):")
            for run in range(1, 4):
                val = input(f"    Run {run} Deviation value (e.g. -0.0001 or 0): ").strip()
                readings[cp].append(float(val) if val else 0.0)
                
        data['history'].append({
            'date': datetime.strptime(cal_date, "%m/%d/%Y").date(),
            'by': cal_by,
            'status': status,
            'notes': notes,
            'readings': readings
        })
        
        more = input("\nAdd another historical log date row for THIS tool? (y/n): ").strip().lower()
        if more != 'y':
            break

    if data['history']:
        save_to_db(data)

if __name__ == "__main__":
    quick_prompt()