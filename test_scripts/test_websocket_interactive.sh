#!/bin/bash
# test_websocket_interactive.sh
# ทดสอบ WebSocket แบบ interactive (เปิด 2 หน้าต่าง)

echo "=========================================="
echo "🧪 ทดสอบแชท 1:1 แบบเรียลไทม์"
echo "=========================================="
echo ""

echo "📋 คำแนะนำ:"
echo "1. เปิด 2 หน้าต่างเทอร์มินัล"
echo "2. รันสคริปต์นี้ในแต่ละหน้าต่าง"
echo "3. เลือกบทบาท (ผู้ส่ง หรือ ผู้รับ)"
echo ""
echo "กด Enter เพื่อดำเนินการต่อ..."
read

# โทเค็น
TOKEN_206="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjA2LCJleHAiOjE3Njk4MjkxMTUsImlzcyI6IndwYS1jb25mZXJlbmNlLWFwaSJ9.nZBORUrQgTxIBGAXv72-6EE-l1LyZwOM2UT698cI9yE"
TOKEN_205="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjA1LCJleHAiOjE3Njk3NjE1NDMsImlzcyI6IndwYS1jb25mZXJlbmNlLWFwaSJ9.kwE1tnSuKSMP0pe7sXNUY6fVeI3aYLvX6K0X04WZefY"

echo "เลือกบทบาท:"
echo "1. ผู้ส่ง (ID 206 - Poonam)"
echo "2. ผู้รับ (ID 205 - Chloe)"
echo ""
read -p "เลือก (1 หรือ 2): " choice

if [ "$choice" = "1" ]; then
    echo ""
    echo "👤 คุณเลือก: ผู้ส่ง (ID 206)"
    echo ""
    echo "กำลังเชื่อมต่อ WebSocket..."
    wscat -c "ws://localhost:3000/cable?token=$TOKEN_206" -H "Origin: http://localhost:3000"
    
elif [ "$choice" = "2" ]; then
    echo ""
    echo "👤 คุณเลือก: ผู้รับ (ID 205)"
    echo ""
    echo "กำลังเชื่อมต่อ WebSocket..."
    wscat -c "ws://localhost:3000/cable?token=$TOKEN_205" -H "Origin: http://localhost:3000"
    
else
    echo "❌ เลือกไม่ถูกต้อง"
    exit 1
fi