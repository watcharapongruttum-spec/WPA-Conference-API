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

cleanup() {
  rm -f rt_A.log rt_B.log rt_*.pid
}

clear_presence() {
  KEYS=$(docker exec redis redis-cli KEYS "chat_open:*")
  if [ -n "$KEYS" ]; then
    docker exec redis redis-cli DEL $KEYS > /dev/null 2>&1
  fi
}

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

# unread ต่อ "คู่แชท"
unread_count_pair() {
  curl -s "$BASE_URL/api/v1/messages/unread_count?sender_id=$2" \
    -H "Authorization: Bearer $1" | jq -r '.unread_count'
}

send_message() {
  curl -s -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$2,\"content\":\"HELLO REALTIME\"}" > /dev/null
}

# ---------- WS ----------
start_ws() {
  TOKEN=$1
  NAME=$2
  TARGET=$3

  LOG="rt_${NAME}.log"
  PID="rt_${NAME}.pid"

  (
    {
      sleep 1

      # SUBSCRIBE ROOM
      echo "{\"command\":\"subscribe\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\",\\\"room_id\\\":$TARGET}\"}"

      sleep 1

      # ENTER ROOM
      echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\",\\\"room_id\\\":$TARGET}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":$TARGET}\"}"

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
clear_presence

step "LOGIN"
TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")

A_ID=$(get_profile_id "$TOKEN_A")
B_ID=$(get_profile_id "$TOKEN_B")

pass "LOGIN OK"

# ---------- WS CONNECT ----------
step "WS CONNECT BOTH OPEN CHAT"
start_ws "$TOKEN_A" "A" "$B_ID"
start_ws "$TOKEN_B" "B" "$A_ID"

# ---------- SEND ----------
step "B SEND MESSAGE TO A"
send_message "$TOKEN_B" "$A_ID"
sleep 3

# ---------- CHECK UNREAD ----------
step "CHECK UNREAD (PAIR ONLY)"
UA=$(unread_count_pair "$TOKEN_A" "$B_ID")
UB=$(unread_count_pair "$TOKEN_B" "$A_ID")

info "UNREAD A FROM B = $UA"
info "UNREAD B FROM A = $UB"

# ---------- CHECK LOG ----------
step "CHECK LOG AUTO SEEN"

if grep -q "bulk_read" rt_A.log || grep -q "message_read" rt_A.log; then
  pass "AUTO SEEN WORKING"
else
  fail "NO AUTO SEEN"
fi

# ---------- RESULT ----------
step "RESULT"

if [ "$UA" = "0" ]; then
  pass "REALTIME SEEN PERFECT"
else
  fail "UNREAD NOT ZERO"
fi

stop_ws "A"
stop_ws "B"

step "END TEST"
