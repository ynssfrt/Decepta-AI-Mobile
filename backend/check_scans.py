import sqlite3

try:
    conn = sqlite3.connect('C:/Users/yunus/.gemini/antigravity/scratch/Decepta-AI-Web/backend/scans.db')
    cursor = conn.cursor()
    cursor.execute("SELECT id, total_reviews, photo_reviews_count, platform_score, true_trust_score, bot_percentage, url FROM scans WHERE url LIKE '%HBCV0000AVDJUW%'")
    rows = cursor.fetchall()
    print("Scans:")
    for row in rows:
        print(row)
    conn.close()
except Exception as e:
    print("Error:", e)
