#!/bin/bash
echo "=========================================="
echo "ทดสอบการส่งข้อความผ่าน REST API"
echo "=========================================="

TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjA2LCJleHAiOjE3Njk4MjkxMTUsImlzcyI6IndwYS1jb25mZXJlbmNlLWFwaSJ9.nZBORUrQgTxIBGAXv72-6EE-l1LyZwOM2UT698cI9yE"

echo "1. ส่งข้อความใหม่ผ่าน API..."
curl -X POST http://localhost:3000/api/v1/messages \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "recipient_id": 205,
    "content": "ทดสอบส่งข้อความผ่าน REST API"
  }'

echo ""
echo ""
echo "2. ดูประวัติการสนทนา..."
curl -X GET "http://localhost:3000/api/v1/messages/conversation/205" \
  -H "Authorization: Bearer $TOKEN"

echo ""
echo ""
echo "3. ดูการแจ้งเตือน..."
curl -X GET http://localhost:3000/api/v1/notifications \
  -H "Authorization: Bearer $TOKEN"
