#!/bin/bash
set +e

#########################################
# CONFIG
#########################################

BASE_URL="http://localhost:3000"
WS_URL="ws://localhost:3000/cable"

EMAIL_A="narisara.lasan@bestgloballogistics.com"
PASSWORD_A="123456"

EMAIL_B="shammi@1shammi1.com"
PASSWORD_B="RNIrSPPICj"

DB_CONTAINER="my-postgres-17"
DB_NAME="wpa_development"
DB_USER="postgres"

#########################################
# COLORS
#########################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass(){ echo -e "${GREEN}✅ $1${NC}"; }
fail(){ echo -e "${RED}❌ $1${NC}"; }
info(){ echo -e "${YELLOW}ℹ️ $1${NC}"; }
step(){ echo -e "\n${CYAN}==== $1 ====${NC}"; }

#########################################
# CLEANUP
#########################################

cleanup(){
  pkill -f "wscat -c $WS_URL" 2>/dev/null
  rm -f rt_A.log rt_B.log rt_*.pid
}

clear_presence(){
  KEYS=$(docker exec redis redis-cli KEYS "chat_open:*")
  if [ -n "$KEYS" ]; then
    docker exec redis redis-cli DEL $KEYS > /dev/null 2>&1
  fi
}

#########################################
# API HELPERS
#########################################

login(){
  curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

profile_id(){
  curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1" | jq -r '.id'
}

send_message(){
  curl -s -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$2,\"content\":\"REALTIME TEST\"}" > /dev/null
}

unread_pair(){
  curl -s "$BASE_URL/api/v1/messages/unread_count?sender_id=$2" \
    -H "Authorization: Bearer $1" | jq -r '.unread_count'
}

#########################################
# DB HELPERS
#########################################

reset_read_state(){
  docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -c "
    UPDATE chat_messages
    SET read_at = NOW(),
        delivered_at = NULL;
  " > /dev/null
}

db_unread(){
  docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
    SELECT COUNT(*)
    FROM chat_messages
    WHERE recipient_id = $1
    AND read_at IS NULL;
  " | xargs
}

db_last_delivered(){
  docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
    SELECT delivered_at
    FROM chat_messages
    WHERE recipient_id = $1
    ORDER BY id DESC
    LIMIT 1;
  " | xargs
}

#########################################
# WS
#########################################

start_ws(){
  TOKEN=$1
  NAME=$2
  TARGET=$3

  LOG="rt_${NAME}.log"
  PID="rt_${NAME}.pid"

  (
    {
      sleep 1

      # subscribe room
      echo "{\"command\":\"subscribe\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\",\\\"room_id\\\":$TARGET}\"}"

      sleep 1

      # enter room
      echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\",\\\"room_id\\\":$TARGET}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":$TARGET}\"}"

      # debounce test
      for i in {1..5}; do
        sleep 0.3
        echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\",\\\"room_id\\\":$TARGET}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":$TARGET}\"}"
      done

      # typing
      sleep 1
      echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\",\\\"room_id\\\":$TARGET}\",\"data\":\"{\\\"action\\\":\\\"typing\\\",\\\"target_id\\\":$TARGET}\"}"

      sleep 999
    } | wscat -c "$WS_URL?token=$TOKEN"
  ) > "$LOG" 2>&1 &

  echo $! > "$PID"
  sleep 4
}

stop_ws(){
  kill $(cat rt_$1.pid) 2>/dev/null
}

#########################################
# START TEST
#########################################

cleanup
clear_presence

step "LOGIN"

TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")

A_ID=$(profile_id "$TOKEN_A")
B_ID=$(profile_id "$TOKEN_B")

pass "LOGIN OK"

#########################################
step "RESET STATE"

reset_read_state
pass "DB RESET OK"

#########################################
step "SEND INITIAL 3 MESSAGES B -> A"

send_message "$TOKEN_B" "$A_ID"
send_message "$TOKEN_B" "$A_ID"
send_message "$TOKEN_B" "$A_ID"
sleep 2

U1=$(db_unread "$A_ID")
info "UNREAD BEFORE ENTER = $U1"

#########################################
step "A ENTER ROOM (AUTO SEEN TEST)"

start_ws "$TOKEN_A" "A" "$B_ID"

U2=$(db_unread "$A_ID")
D1=$(db_last_delivered "$A_ID")

info "UNREAD AFTER ENTER = $U2"
info "DELIVERED AFTER ENTER = $D1"

if [ "$U2" = "0" ]; then
  pass "AUTO SEEN OK"
else
  fail "AUTO SEEN FAIL"
fi

#########################################
step "TTL PRESENCE TEST"

stop_ws "A"
info "WAIT 65s..."
sleep 65

send_message "$TOKEN_B" "$A_ID"
sleep 2

U3=$(db_unread "$A_ID")
info "UNREAD AFTER TTL MSG = $U3"

if [ "$U3" = "1" ]; then
  pass "TTL OK"
else
  fail "TTL FAIL"
fi

#########################################
step "REALTIME BOTH OPEN TEST"

start_ws "$TOKEN_A" "A" "$B_ID"
start_ws "$TOKEN_B" "B" "$A_ID"

send_message "$TOKEN_B" "$A_ID"
sleep 3

UA=$(unread_pair "$TOKEN_A" "$B_ID")
UB=$(unread_pair "$TOKEN_B" "$A_ID")

info "UNREAD A FROM B = $UA"
info "UNREAD B FROM A = $UB"

if grep -q "bulk_read" rt_A.log || grep -q "message_read" rt_A.log; then
  pass "AUTO SEEN REALTIME EVENT OK"
else
  fail "NO AUTO SEEN EVENT"
fi

if [ "$UA" = "0" ]; then
  pass "PAIR UNREAD ZERO OK"
else
  fail "PAIR UNREAD FAIL"
fi

#########################################
step "END REALTIME FULL AUDIT"

stop_ws "A"
stop_ws "B"
cleanup
