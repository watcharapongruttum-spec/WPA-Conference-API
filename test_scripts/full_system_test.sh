#!/bin/bash
set -e

#########################################
# CONFIG
#########################################

BASE_URL="http://localhost:3000"
WS_URL="ws://localhost:3000/cable"

EMAIL_A="narisara.lasan@bestgloballogistics.com"
PASSWORD_A="123456"

EMAIL_B="shammi@1shammi1.com"
PASSWORD_B="RNIrSPPICj"

CHAT_MESSAGES=20
SEND_DELAY=0.2

#########################################
# COLORS
#########################################

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

pass(){ echo -e "${GREEN}✅ $1${NC}"; }
fail(){ echo -e "${RED}❌ $1${NC}"; exit 1; }
step(){ echo -e "\n${CYAN}==== $1 ====${NC}"; }

#########################################
# CLEANUP
#########################################

cleanup(){
  pkill -f "wscat -c $WS_URL" 2>/dev/null || true
  rm -f rt_A.log rt_B.log || true
}
trap cleanup EXIT

#########################################
# LOGIN
#########################################

login(){
  curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

get_id(){
  curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1" | jq -r '.id'
}

#########################################
# REALTIME
#########################################

start_ws(){
  TOKEN=$1
  NAME=$2

  (
    {
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"NotificationChannel\"}"}'
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}'
      sleep 999
    } | timeout 60 wscat -c "$WS_URL?token=$TOKEN"
  ) > "rt_${NAME}.log" 2>&1 &

  sleep 2
}

#########################################
# START
#########################################

step "LOGIN"

TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")

[ -z "$TOKEN_A" ] && fail "Login A failed"
[ -z "$TOKEN_B" ] && fail "Login B failed"

A_ID=$(get_id "$TOKEN_A")
B_ID=$(get_id "$TOKEN_B")

pass "Login OK"

#########################################
step "RESET UNREAD STATE"

curl -s -X PATCH $BASE_URL/api/v1/messages/read_all \
  -H "Authorization: Bearer $TOKEN_B" > /dev/null

sleep 1

INITIAL=$(curl -s "$BASE_URL/api/v1/messages/unread_count?sender_id=$A_ID" \
  -H "Authorization: Bearer $TOKEN_B" | jq -r '.unread_count')

[ "$INITIAL" -ne 0 ] && fail "Unread reset failed"

pass "Unread reset"

#########################################
step "START REALTIME"

start_ws "$TOKEN_A" "A"
start_ws "$TOKEN_B" "B"

#########################################
step "SEND CHAT MESSAGES"

for ((i=1;i<=CHAT_MESSAGES;i++)); do
  curl -s -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$B_ID,\"content\":\"chat message $i\"}" > /dev/null
  sleep $SEND_DELAY
done

sleep 2
pass "Messages sent"

#########################################
step "VERIFY UNREAD COUNT"

UNREAD=$(curl -s "$BASE_URL/api/v1/messages/unread_count?sender_id=$A_ID" \
  -H "Authorization: Bearer $TOKEN_B" | jq -r '.unread_count')

echo "Unread at B: $UNREAD (expected $CHAT_MESSAGES)"

[ "$UNREAD" -ne "$CHAT_MESSAGES" ] && fail "Unread mismatch"

pass "Unread correct"

#########################################
step "VERIFY REALTIME DELIVERY COUNT"

REALTIME_COUNT=$(grep -c "new_message" rt_B.log || true)

echo "Realtime events: $REALTIME_COUNT (expected >= $CHAT_MESSAGES)"

[ "$REALTIME_COUNT" -lt "$CHAT_MESSAGES" ] && fail "Realtime missing messages"

pass "Realtime delivery correct"

#########################################
step "READ ALL"

curl -s -X PATCH $BASE_URL/api/v1/messages/read_all \
  -H "Authorization: Bearer $TOKEN_B" > /dev/null

sleep 1

UNREAD_AFTER=$(curl -s "$BASE_URL/api/v1/messages/unread_count?sender_id=$A_ID" \
  -H "Authorization: Bearer $TOKEN_B" | jq -r '.unread_count')

[ "$UNREAD_AFTER" -ne 0 ] && fail "Read did not clear unread"

pass "Read cleared unread"

#########################################
step "LATENCY CHECK"

START=$(date +%s%3N)
curl -s -X POST $BASE_URL/api/v1/messages \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"recipient_id\":$B_ID,\"content\":\"latency\"}" > /dev/null
END=$(date +%s%3N)

echo "REST latency = $((END-START)) ms"

#########################################
pass "CHAT SYSTEM TEST COMPLETE"
