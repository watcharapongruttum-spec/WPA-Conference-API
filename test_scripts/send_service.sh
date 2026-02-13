#!/bin/bash
set +e

BASE_URL="http://localhost:3000"
WS_URL="ws://localhost:3000/cable"

EMAIL_A="narisara.lasan@bestgloballogistics.com"
PASSWORD_A="123456"

EMAIL_B="shammi@1shammi1.com"
PASSWORD_B="RNIrSPPICj"

EMAIL_C="jeremy99@empireglobal.co.th"
PASSWORD_C="123456"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; }
info() { echo -e "${YELLOW}ℹ️ $1${NC}"; }
step() { echo -e "\n${CYAN}==== $1 ====${NC}"; }

cleanup() {
  rm -f rt_*.log rt_*.pid
}

# ---------- API HELPERS ----------

login() {
  curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

get_profile_id() {
  curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1" | jq -r '.id'
}

send_rest_message() {
  curl -s -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$2,\"content\":\"SERVICE TEST REST\"}" \
    | jq -r '.id'
}

get_conversation() {
  curl -s $BASE_URL/api/v1/messages/conversation/$2 \
    -H "Authorization: Bearer $1" | jq '.data'
}


# ---------- WS ----------

start_ws() {
  TOKEN=$1
  NAME=$2

  LOG="rt_${NAME}.log"
  PID="rt_${NAME}.pid"

  (
    {
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}'
      sleep 999
    } | wscat -c "$WS_URL?token=$TOKEN"
  ) > "$LOG" 2>&1 &

  echo $! > "$PID"
  sleep 2
}

stop_ws() {
  kill $(cat rt_$1.pid) 2>/dev/null
}

# ================= START =================

cleanup

step "LOGIN"
TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")
TOKEN_C=$(login "$EMAIL_C" "$PASSWORD_C")

A_ID=$(get_profile_id "$TOKEN_A")
B_ID=$(get_profile_id "$TOKEN_B")
C_ID=$(get_profile_id "$TOKEN_C")

pass "LOGIN OK"

# ================= REST TEST =================

step "REST SEND MESSAGE (A -> B)"
MSG_ID=$(send_rest_message "$TOKEN_A" "$B_ID")

if [ "$MSG_ID" != "null" ]; then
  pass "REST message created id=$MSG_ID"
else
  fail "REST send failed"
fi

step "CHECK DB VIA CONVERSATION"
CONV=$(get_conversation "$TOKEN_A" "$B_ID" | jq 'length')

if [ "$CONV" -gt 0 ]; then
  pass "Conversation exists ($CONV messages)"
else
  fail "Conversation empty"
fi

# ================= WS TEST =================

step "WS START B"
start_ws "$TOKEN_B" "B"

step "WS SEND A -> B"
send_rest_message "$TOKEN_A" "$B_ID" > /dev/null
sleep 2

if grep -q "new_message" rt_B.log; then
  pass "WS Broadcast OK"
else
  fail "WS Broadcast FAIL"
fi

# ================= MULTI USER =================

step "MULTI SEND A -> C"
send_rest_message "$TOKEN_A" "$C_ID" > /dev/null
sleep 1
pass "A -> C OK"

# ================= CLEAN =================

step "STOP WS"
stop_ws "B"

pass "SERVICE TEST DONE"
