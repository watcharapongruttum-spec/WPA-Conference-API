#!/bin/bash
echo "=========================================="
echo "ทดสอบการส่งข้อความ 1:1 ผ่าน WebSocket"
echo "=========================================="

# โทเค็นของผู้ส่ง (เปลี่ยนเป็นโทเค็นจริง)
TOKEN_SENDER="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjA2LCJleHAiOjE3Njk4MjkxMTUsImlzcyI6IndwYS1jb25mZXJlbmNlLWFwaSJ9.nZBORUrQgTxIBGAXv72-6EE-l1LyZwOM2UT698cI9yE"

# โทเค็นของผู้รับ (เปลี่ยนเป็นโทเค็นจริงของผู้รับ)
TOKEN_RECEIVER="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjA1LCJleHAiOjE3Njk3NjE1NDMsImlzcyI6IndwYS1jb25mZXJlbmNlLWFwaSJ9.kwE1tnSuKSMP0pe7sXNUY6fVeI3aYLvX6K0X04WZefY"

# ID ของผู้รับ (เปลี่ยนเป็น ID จริง)
RECIPIENT_ID=205

echo "เปิด 2 หน้าต่างเทอร์มินัล:"
echo ""
echo "หน้าต่างที่ 1 (ผู้รับ - ID $RECIPIENT_ID):"
echo "wscat -c \"ws://localhost:3000/cable?token=$TOKEN_RECEIVER\" -H \"Origin: http://localhost:3000\""
echo "พิมพ์: {\"command\":\"subscribe\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\"}\"}"
echo ""
echo "หน้าต่างที่ 2 (ผู้ส่ง):"
echo "wscat -c \"ws://localhost:3000/cable?token=$TOKEN_SENDER\" -H \"Origin: http://localhost:3000\""
echo "พิมพ์: {\"command\":\"subscribe\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\"}\"}"
echo ""
echo "จากนั้นในหน้าต่างที่ 2 (ผู้ส่ง) ส่งข้อความ:"
echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\"}\",\"data\":\"{\\\"action\\\":\\\"send_message\\\",\\\"recipient_id\\\":$RECIPIENT_ID,\\\"content\\\":\\\"ทดสอบแชท 1:1\\\"}\"}"
echo ""
echo "ตรวจสอบว่า:"
echo "✅ ผู้ส่งเห็นข้อความที่ส่งกลับมา"
echo "✅ ผู้รับเห็นข้อความใหม่ปรากฏทันที"
