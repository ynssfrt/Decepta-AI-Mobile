import sqlite3

try:
    conn = sqlite3.connect('scans.db')
    cursor = conn.cursor()
    
    # Check tables
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = cursor.fetchall()
    print("Tables:", tables)
    
    for table_info in tables:
        table_name = table_info[0]
        cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
        count = cursor.fetchone()[0]
        print(f"Table '{table_name}' count:", count)
        
        if count > 0:
            cursor.execute(f"SELECT * FROM {table_name} LIMIT 5")
            rows = cursor.fetchall()
            print(f"Sample rows from '{table_name}':")
            for row in rows:
                print(row)
                
    conn.close()
except Exception as e:
    print("Error:", e)
