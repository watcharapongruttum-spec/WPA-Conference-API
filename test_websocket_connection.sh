#!/bin/bash
echo "=========================================="
echo "ทดสอบการเชื่อมต่อ WebSocket"
echo "=========================================="

# ใช้โทเค็นของผู้ใช้ที่มีอยู่ (เปลี่ยนเป็นโทเค็นจริงของคุณ)
TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjA2LCJleHAiOjE3Njk4MjkxMTUsImlzcyI6IndwYS1jb25mZXJlbmNlLWFwaSJ9.nZBORUrQgTxIBGAXv72-6EE-l1LyZwOM2UT698cI9yE"

echo "1. เชื่อมต่อ WebSocket..."
wscat -c "ws://localhost:3000/cable?token=$TOKEN" -H "Origin: http://localhost:3000" <<'MSG'
{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}
MSG

echo ""
echo "2. เชื่อมต่อ NotificationChannel..."
wscat -c "ws://localhost:3000/cable?token=$TOKEN" -H "Origin: http://localhost:3000" <<'MSG'
{"command":"subscribe","identifier":"{\"channel\":\"NotificationChannel\"}"}
MSG
