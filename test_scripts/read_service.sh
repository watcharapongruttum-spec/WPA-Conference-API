#!/bin/bash
set +e

BASE_URL="http://localhost:3000"
WS_URL="ws://localhost:3000/cable"

EMAIL_A="narisara.lasan@bestgloballogistics.com"
PASSWORD_A="123456"

EMAIL_B="shammi@1shammi1.com"
PASSWORD_B="RNIrSPPICj"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; }
info() { echo -e "${YELLOW}ℹ️ $1${NC}"; }
step() { echo -e "\n${CYAN}==== $1 ====${NC}"; }

login() {
  curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

get_profile_id() {
  curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1" | jq -r '.id'
}

send_message() {
  curl -s -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$2,\"content\":\"READ TEST\"}" | jq -r '.id'
}

start_ws() {
  TOKEN=$1
  NAME=$2

  LOG="ws_${NAME}.log"
  (
    {
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}'
      sleep 999
    } | wscat -c "$WS_URL?token=$TOKEN"
  ) > "$LOG" 2>&1 &
}

step "LOGIN"
TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")

A_ID=$(get_profile_id "$TOKEN_A")
B_ID=$(get_profile_id "$TOKEN_B")
pass "LOGIN OK"

step "START WS B"
start_ws "$TOKEN_B" "B"
sleep 2

step "SEND 3 MSG A -> B"
for i in {1..3}
do
  send_message "$TOKEN_A" "$B_ID" > /dev/null
done
pass "A -> B SENT"

step "ENTER ROOM B"
wscat -c "$WS_URL?token=$TOKEN_B" <<EOF
{"command":"message","identifier":"{\"channel\":\"ChatChannel\"}","data":"{\"action\":\"enter_room\",\"user_id\":$A_ID}"}
EOF
pass "ENTER ROOM SENT"

sleep 2

step "CHECK UNREAD COUNT"
COUNT=$(curl -s $BASE_URL/api/v1/messages/unread_count \
  -H "Authorization: Bearer $TOKEN_B" | jq -r '.unread_count')

echo "Unread: $COUNT"

step "READ ALL"
curl -s -X PATCH $BASE_URL/api/v1/messages/read_all \
  -H "Authorization: Bearer $TOKEN_B" > /dev/null
pass "READ ALL DONE"

echo ""
echo "🎯 TEST FINISHED"
