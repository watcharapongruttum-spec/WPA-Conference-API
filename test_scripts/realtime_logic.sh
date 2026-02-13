#!/bin/bash
set +e

BASE_URL="http://localhost:3000"
WS_URL="ws://localhost:3000/cable"

EMAIL_A="narisara.lasan@bestgloballogistics.com"
PASSWORD_A="123456"

EMAIL_B="shammi@1shammi1.com"
PASSWORD_B="RNIrSPPICj"

DB_CONTAINER="my-postgres-17"
DB_NAME="wpa_development"
DB_USER="postgres"

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

login() {
  curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

get_profile_id() {
  curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1" | jq -r '.id'
}

reset_read_for_users() {
  A=$1
  B=$2

  docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -c "
    UPDATE chat_messages
    SET read_at = NOW(),
        delivered_at = NULL;
  " > /dev/null
}

send_message() {
  curl -s -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$2,\"content\":\"TEST LEVEL2\"}" > /dev/null
}

last_unread_count() {
  docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
    SELECT COUNT(*)
    FROM chat_messages
    WHERE recipient_id = $1
    AND read_at IS NULL;
  " | xargs
}

last_delivered() {
  docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
    SELECT delivered_at
    FROM chat_messages
    WHERE recipient_id = $1
    ORDER BY id DESC
    LIMIT 1;
  " | xargs
}

start_ws() {
  TOKEN=$1
  NAME=$2
  TARGET=$3

  LOG="rt_${NAME}.log"
  PID="rt_${NAME}.pid"

  (
    {
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}'
      sleep 1

      # enter room
      echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\"}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":$TARGET}\"}"
      sleep 2

      # debounce
      for i in {1..5}; do
        echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\"}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":$TARGET}\"}"
        sleep 0.3
      done

      # typing
      echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\"}\",\"data\":\"{\\\"action\\\":\\\"typing\\\",\\\"target_id\\\":$TARGET}\"}"

      sleep 999
    } | wscat -c "$WS_URL?token=$TOKEN"
  ) > "$LOG" 2>&1 &

  echo $! > "$PID"
  sleep 4
}

stop_ws() {
  kill $(cat rt_$1.pid) 2>/dev/null
}

# ================= START =================

step "LOGIN"
TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")

A_ID=$(get_profile_id "$TOKEN_A")
B_ID=$(get_profile_id "$TOKEN_B")

pass "LOGIN OK"

step "RESET READ STATE"
reset_read_for_users "$A_ID" "$B_ID"
pass "RESET OK"

cleanup
clear_presence

# ---------- SEND INITIAL ----------
step "SEND 3 MSG B -> A"
send_message "$TOKEN_B" "$A_ID"
send_message "$TOKEN_B" "$A_ID"
send_message "$TOKEN_B" "$A_ID"
sleep 2

U1=$(last_unread_count "$A_ID")
info "UNREAD BEFORE ENTER = $U1"

# ---------- WS ENTER ----------
step "A ENTER ROOM"
start_ws "$TOKEN_A" "A" "$B_ID"

U2=$(last_unread_count "$A_ID")
info "UNREAD AFTER ENTER = $U2"

D1=$(last_delivered "$A_ID")
info "DELIVERED AFTER ENTER = $D1"

if [ "$U2" = "0" ]; then
  pass "AUTO SEEN OK"
else
  fail "AUTO SEEN FAIL"
fi

# ---------- TTL ----------
step "TTL TEST"
stop_ws "A"
info "WAIT 65s..."
sleep 65

send_message "$TOKEN_B" "$A_ID"
sleep 2

U3=$(last_unread_count "$A_ID")
info "UNREAD AFTER TTL MSG = $U3"

D2=$(last_delivered "$A_ID")
info "DELIVERED AFTER TTL MSG = $D2"

if [ "$U3" = "1" ]; then
  pass "TTL OK"
else
  fail "TTL FAIL"
fi

step "END LEVEL 2 TEST"
