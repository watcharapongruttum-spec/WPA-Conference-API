#!/bin/bash
# test_comprehensive.sh
# ทดสอบแบบครอบคลุมทุกฟีเจอร์

set -e

echo "=========================================="
echo "🧪 ทดสอบแบบครอบคลุม"
echo "=========================================="
echo ""

# สี
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# ตัวแปรเก็บผลลัพธ์
PASS=0
FAIL=0

# ฟังก์ชันทดสอบ
run_test() {
    local name=$1
    shift
    echo -n "ทดสอบ $name... "
    if "$@"; then
        print_success "$name"
        ((PASS++))
    else
        print_error "$name"
        ((FAIL++))
    fi
}

echo "1. ทดสอบ WebSocket Connection"
run_test "เชื่อมต่อ WebSocket" timeout 5 bash -c '
    TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjA2LCJleHAiOjE3Njk4MjkxMTUsImlzcyI6IndwYS1jb25mZXJlbmNlLWFwaSJ9.nZBORUrQgTxIBGAXv72-6EE-l1LyZwOM2UT698cI9yE"
    wscat -c "ws://localhost:3000/cable?token=$TOKEN" -H "Origin: http://localhost:3000" <<EOF > /tmp/test.log 2>&1
{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}
EOF
    grep -q "welcome" /tmp/test.log
'

echo ""
echo "2. ทดสอบ REST API"
run_test "ส่งข้อความผ่าน API" bash -c '
    TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjA2LCJleHAiOjE3Njk4MjkxMTUsImlzcyI6IndwYS1jb25mZXJlbmNlLWFwaSJ9.nZBORUrQgTxIBGAXv72-6EE-l1LyZwOM2UT698cI9yE"
    curl -s -X POST http://localhost:3000/api/v1/messages \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d "{\"recipient_id\": 205, \"content\": \"test\"}" \
        | grep -q "content"
'

run_test "ดึงประวัติการแชท" bash -c '
    TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjA2LCJleHAiOjE3Njk4MjkxMTUsImlzcyI6IndwYS1jb25mZXJlbmNlLWFwaSJ9.nZBORUrQgTxIBGAXv72-6EE-l1LyZwOM2UT698cI9yE"
    curl -s -X GET "http://localhost:3000/api/v1/messages/conversation/205" \
        -H "Authorization: Bearer $TOKEN" \
        | grep -q "\[\|{"
'

echo ""
echo "3. ทดสอบการแจ้งเตือน"
run_test "ดึงการแจ้งเตือน" bash -c '
    TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjA2LCJleHAiOjE3Njk4MjkxMTUsImlzcyI6IndwYS1jb25mZXJlbmNlLWFwaSJ9.nZBORUrQgTxIBGAXv72-6EE-l1LyZwOM2UT698cI9yE"
    curl -s -X GET http://localhost:3000/api/v1/notifications \
        -H "Authorization: Bearer $TOKEN" \
        | grep -q "\[\|{"
'

echo ""
echo "4. ทดสอบแชทกลุ่ม"
run_test "สร้างห้องแชทกลุ่ม" rails runner "
    room = ChatRoom.where(title: 'Test Group').first || 
           ChatRoom.create!(title: 'Test Group', room_kind: 'group')
    RoomMember.find_or_create_by!(chat_room: room, delegate_id: 206)
    RoomMember.find_or_create_by!(chat_room: room, delegate_id: 205)
    ChatMessage.create!(chat_room: room, sender_id: 206, content: 'test')
    exit 0
"

echo ""
echo "5. ทดสอบแชท 1:1"
run_test "ส่งข้อความ 1:1" rails runner "
    ChatMessage.create!(
        sender_id: 206,
        recipient_id: 205,
        content: 'test 1:1'
    )
    exit 0
"

echo ""
echo "=========================================="
echo "📊 สรุปผลการทดสอบ"
echo "=========================================="
echo "ผ่าน: $PASS"
echo "ล้มเหลว: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    print_success "การทดสอบทั้งหมดผ่าน!"
    exit 0
else
    print_error "มีการทดสอบที่ล้มเหลว $FAIL รายการ"
    exit 1
fi