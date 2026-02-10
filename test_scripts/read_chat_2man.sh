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
  rm -f rt_A.log rt_B.log rt_C.log rt_*.pid
}

clear_presence() {
  KEYS=$(docker exec redis redis-cli KEYS "chat_open:*")
  if [ -n "$KEYS" ]; then
    docker exec redis redis-cli DEL $KEYS > /dev/null 2>&1
  fi
}

cleanup
clear_presence

# ---------- LOGIN ----------
login() {
  curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

get_profile_id() {
  curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1" | jq -r '.id'
}

unread_count() {
  curl -s $BASE_URL/api/v1/messages/unread_count \
    -H "Authorization: Bearer $1" | jq -r '.unread_count'
}

send_message() {
  curl -s -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$2,\"content\":\"TEST MSG\"}" > /dev/null
}

start_ws() {
  TOKEN=$1
  NAME=$2
  TARGET=$3
  AUTO_ENTER=$4

  LOG="rt_${NAME}.log"
  PID="rt_${NAME}.pid"

  (
    {
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}'
      sleep 1
      if [ "$AUTO_ENTER" = "yes" ]; then
        echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\"}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":$TARGET}\"}"
      fi
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

step "LOGIN"
TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")
TOKEN_C=$(login "$EMAIL_C" "$PASSWORD_C")

A_ID=$(get_profile_id "$TOKEN_A")
B_ID=$(get_profile_id "$TOKEN_B")
C_ID=$(get_profile_id "$TOKEN_C")

pass "LOGIN OK"

# ---------- WS CONNECT ----------
step "WS CONNECT"
start_ws "$TOKEN_A" "A" "$B_ID" "no"
start_ws "$TOKEN_B" "B" "$A_ID" "no"
start_ws "$TOKEN_C" "C" "$A_ID" "no"

# ---------- SEND ----------
step "B -> A"
send_message "$TOKEN_B" "$A_ID"
sleep 1

step "C -> A"
send_message "$TOKEN_C" "$A_ID"
sleep 2

# ---------- CHECK UNREAD ----------
step "CHECK UNREAD A BEFORE"
U1=$(unread_count "$TOKEN_A")
info "UNREAD A = $U1"

# ---------- ENTER ROOM B ----------
step "A ENTER ROOM B"
stop_ws "A"
start_ws "$TOKEN_A" "A" "$B_ID" "yes"
sleep 3

U2=$(unread_count "$TOKEN_A")
info "UNREAD A AFTER B = $U2"

# ---------- ENTER ROOM C ----------
step "A ENTER ROOM C"
stop_ws "A"
start_ws "$TOKEN_A" "A" "$C_ID" "yes"
sleep 3

U3=$(unread_count "$TOKEN_A")
info "UNREAD A AFTER C = $U3"

# ---------- RESULT ----------
step "RESULT"

echo "BEFORE = $U1"
echo "AFTER B = $U2"
echo "AFTER C = $U3"

if [ "$U3" = "0" ]; then
  pass "UNREAD FLOW PERFECT"
else
  fail "UNREAD NOT ZERO"
fi

stop_ws "A"
stop_ws "B"
stop_ws "C"

step "END TEST"
