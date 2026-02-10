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
NC='\033[0m'

pass() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; }
info() { echo -e "${YELLOW}ℹ️ $1${NC}"; }

# ---------- CLEAN ----------
cleanup() {
  rm -f rt_A.log rt_B.log rt_A.pid rt_B.pid
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
  RESP=$(curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}")

  TOKEN=$(echo "$RESP" | jq -r '.token' 2>/dev/null)

  if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
    echo ""
  else
    echo "$TOKEN"
  fi
}

# ---------- PROFILE ----------
get_profile_id() {
  RESP=$(curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1")
  echo "$RESP" | jq -r '.id'
}

# ---------- UNREAD ----------
unread_count() {
  COUNT=$(curl -s $BASE_URL/api/v1/messages/unread_count \
    -H "Authorization: Bearer $1" | jq -r '.unread_count')

  if [ "$COUNT" = "null" ] || [ -z "$COUNT" ]; then
    echo 0
  else
    echo $COUNT
  fi
}

# ---------- SEND ----------
send_message() {
  RESP=$(curl -s -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$2,\"content\":\"AUTO TEST\"}")

  echo "$RESP" | jq -r '.id'
}

# ---------- EDIT ----------
edit_message() {
  curl -s -X PATCH $BASE_URL/api/v1/messages/$2 \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d '{"content":"EDITED AUTO"}' > /dev/null
}

# ---------- DELETE ----------
delete_message() {
  curl -s -X DELETE $BASE_URL/api/v1/messages/$2 \
    -H "Authorization: Bearer $1" > /dev/null
}

# ---------- ASSERT ----------
assert_event() {
  EVENT=$1
  FILE=$2

  if grep -q "$EVENT" "$FILE" 2>/dev/null; then
    pass "$EVENT OK"
  else
    fail "$EVENT FAIL"
    echo "------ LOG $FILE ------"
    cat "$FILE"
  fi
}

# ---------- WS ----------
start_ws() {
  TOKEN=$1
  NAME=$2
  TARGET=$3
  AUTO_ENTER=$4

  LOG="rt_${NAME}.log"
  PID="rt_${NAME}.pid"

  rm -f "$LOG" "$PID"

  (
    {
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}'
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"NotificationChannel\"}"}'

      if [ "$AUTO_ENTER" = "yes" ]; then
        sleep 1
        echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\"}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":$TARGET}\"}"
      fi

      sleep 999
    } | wscat -c "$WS_URL?token=$TOKEN"
  ) > "$LOG" 2>&1 &

  echo $! > "$PID"
  pass "WS $NAME"
  sleep 3
}

stop_ws() {
  PID="rt_$1.pid"
  if [ -f "$PID" ]; then
    kill $(cat "$PID") 2>/dev/null
    rm "$PID"
    pass "STOP WS $1"
  fi
}

# ================= START =================
echo "==== CHAT FULL TEST ===="

TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")

[ -z "$TOKEN_A" ] && fail "LOGIN A FAIL" && exit
[ -z "$TOKEN_B" ] && fail "LOGIN B FAIL" && exit
pass "LOGIN OK"

A_ID=$(get_profile_id "$TOKEN_A")
B_ID=$(get_profile_id "$TOKEN_B")

# ---------- OPEN WS (NO ENTER) ----------
start_ws "$TOKEN_A" "A" "$B_ID" "no"
start_ws "$TOKEN_B" "B" "$A_ID" "no"

# ---------- UNREAD BEFORE ----------
UB=$(unread_count "$TOKEN_B")
info "UNREAD B BEFORE=$UB"

# ---------- SEND ----------
MSG_ID=$(send_message "$TOKEN_A" "$B_ID")
sleep 2
assert_event "new_message" rt_B.log

UA=$(unread_count "$TOKEN_B")
info "UNREAD B AFTER=$UA"

if [ "$UA" -gt "$UB" ]; then
  pass "UNREAD INCREASE OK"
else
  fail "UNREAD NOT INCREASE"
fi

# ---------- ENTER ROOM ----------
info "ENTER ROOM B"
stop_ws "B"
start_ws "$TOKEN_B" "B" "$A_ID" "yes"
sleep 3
assert_event "message_read" rt_A.log

# ---------- EDIT ----------
edit_message "$TOKEN_A" "$MSG_ID"
sleep 2
assert_event "message_updated" rt_B.log

# ---------- DELETE ----------
delete_message "$TOKEN_A" "$MSG_ID"
sleep 2
assert_event "message_deleted" rt_B.log

# ---------- NOTIFICATION ----------
assert_event "new_notification" rt_B.log

stop_ws "A"
stop_ws "B"

echo "==== END TEST ===="
