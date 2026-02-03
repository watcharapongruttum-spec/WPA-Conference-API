#!/bin/bash
set -e

BASE_URL="https://wpa-docker.onrender.com"
WS_URL="wss://wpa-docker.onrender.com/cable"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; }
info() { echo -e "ℹ️  $1"; }

echo "=================================="
echo "🧪 TEST CHAT SYSTEM"
echo "=================================="

# ---------------- REQUIREMENTS ----------------
command -v jq >/dev/null || { echo "ต้องติดตั้ง jq"; exit 1; }
command -v wscat >/dev/null || { echo "ต้องติดตั้ง wscat"; exit 1; }

# ---------------- SERVER ----------------
echo "1. Server"
curl -s $BASE_URL >/dev/null && ok "Server OK" || fail "Server Down"

# ---------------- LOGIN ----------------
echo ""
echo "2. Login"

LOGIN=$(curl -s -X POST "$BASE_URL/api/v1/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"shammi@1shammi1.com","password":"RNIrSPPICj"}')

TOKEN=$(echo $LOGIN | jq -r '.token')

if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
  fail "Login Failed"
  echo "$LOGIN"
  exit 1
fi

ok "Login OK"
info "TOKEN OK"

# ---------------- WEBSOCKET ----------------
echo ""
echo "3. WebSocket"

timeout 8s wscat -c "$WS_URL?token=$TOKEN" \
  -H "Origin: $BASE_URL" <<EOF > /tmp/ws.log 2>&1
{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}
EOF

if grep -q '"type":"welcome"' /tmp/ws.log; then
  ok "WebSocket Welcome OK"
else
  fail "No welcome"
  echo "---- WS LOG ----"
  cat /tmp/ws.log
fi

# ---------------- REST SEND ----------------
echo ""
echo "4. REST Send"

CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$BASE_URL/api/v1/messages" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"recipient_id":205,"content":"API TEST"}')

[ "$CODE" = "201" ] && ok "Send OK" || fail "Send $CODE"

# ---------------- REST HISTORY ----------------
echo ""
echo "5. History"

CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v1/messages/conversation/205")

[ "$CODE" = "200" ] && ok "History OK" || fail "History $CODE"

# ---------------- NOTIFICATIONS ----------------
echo ""
echo "6. Notifications"

CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v1/notifications")

[ "$CODE" = "200" ] && ok "Notification OK" || fail "Notification Fail"

# ---------------- GROUP CHAT VIA API ----------------
echo ""
echo "7. Group Chat (API)"

ROOM_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/chat_rooms" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"title":"TestRoom","room_kind":"group"}')

ROOM_ID=$(echo $ROOM_RESPONSE | jq -r '.id')

if [ -z "$ROOM_ID" ] || [ "$ROOM_ID" = "null" ]; then
  fail "Create Room Fail"
  echo "$ROOM_RESPONSE"
else
  ok "Room Created ID=$ROOM_ID"
fi

# ---------------- 1:1 ----------------
echo ""
echo "8. 1:1 Chat"

CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$BASE_URL/api/v1/messages" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"recipient_id":205,"content":"1:1 TEST"}')

[ "$CODE" = "201" ] && ok "1:1 OK" || fail "1:1 $CODE"

echo ""
echo "=================================="
ok "TEST DONE"
echo "=================================="
