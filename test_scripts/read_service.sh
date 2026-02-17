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

# ---------------- CLEANUP ----------------

cleanup() {
  pkill -f wscat 2>/dev/null
  rm -f received_ids.txt ws_*.pid
}
trap cleanup EXIT

# ---------------- LOGIN ----------------

login() {
  curl --max-time 5 -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

get_profile_id() {
  curl --max-time 5 -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1" | jq -r '.id'
}

unread_count() {
  curl --max-time 5 -s $BASE_URL/api/v1/messages/unread_count \
    -H "Authorization: Bearer $1" | jq -r '.unread_count'
}

send_message() {
  TS=$(date +%s%3N)
  curl --max-time 5 -s -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$2,\"content\":\"TS:$TS\"}" > /dev/null
}

# ---------------- WS ----------------

start_ws() {
  TOKEN=$1
  NAME=$2
  TARGET=$3
  AUTO_ENTER=$4

  (
    {
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}'
      sleep 1

      if [ "$AUTO_ENTER" = "yes" ]; then
        echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\"}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":$TARGET}\"}"
      fi

      sleep 9999
    } | wscat -c "$WS_URL?token=$TOKEN" 2>/dev/null
  ) | while read line; do

      MESSAGE_TYPE=$(echo "$line" | jq -r '.message.type // empty' 2>/dev/null)

      if [ "$MESSAGE_TYPE" = "new_message" ]; then
        ID=$(echo "$line" | jq -r '.message.id')
        CONTENT=$(echo "$line" | jq -r '.message.content')

        # กัน duplicate แบบ atomic
        (
          flock -x 200
          if grep -q "^$ID$" received_ids.txt 2>/dev/null; then
            echo -e "${RED}[WS-$NAME][DUPLICATE $ID]${NC}"
          else
            echo "$ID" >> received_ids.txt
          fi
        ) 200>lockfile

        SENT_TS=$(echo $CONTENT | cut -d':' -f2)
        NOW=$(date +%s%3N)
        DIFF=$((NOW-SENT_TS))

        echo -e "${YELLOW}[WS-$NAME][LATENCY ${DIFF}ms]${NC}"
      fi

    done &

  echo $! > ws_${NAME}.pid
}

stop_ws() {
  if [ -f ws_$1.pid ]; then
    kill $(cat ws_$1.pid) 2>/dev/null
    rm -f ws_$1.pid
  fi
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

# ---------------- CONNECT WS ----------------

step "CONNECT WS"

start_ws "$TOKEN_A" "A" "$B_ID" "no"
start_ws "$TOKEN_B" "B" "$A_ID" "no"
start_ws "$TOKEN_C" "C" "$A_ID" "no"

sleep 3

# ---------------- BASIC FLOW ----------------

step "B -> A"
send_message "$TOKEN_B" "$A_ID"
sleep 2

step "C -> A"
send_message "$TOKEN_C" "$A_ID"
sleep 2

step "CHECK UNREAD BEFORE"
U1=$(unread_count "$TOKEN_A")
info "UNREAD A = $U1"

# ---------------- ENTER ROOM ----------------

step "A ENTER ROOM B"
stop_ws "A"
start_ws "$TOKEN_A" "A_ROOM_B" "$B_ID" "yes"
sleep 3

U2=$(unread_count "$TOKEN_A")
info "UNREAD AFTER B = $U2"

step "A ENTER ROOM C"
stop_ws "A_ROOM_B"
start_ws "$TOKEN_A" "A_ROOM_C" "$C_ID" "yes"
sleep 3

U3=$(unread_count "$TOKEN_A")
info "UNREAD AFTER C = $U3"

# ---------------- STRESS ----------------

step "STRESS TEST 50 MESSAGES"

START=$(date +%s%3N)

for i in {1..50}; do
  send_message "$TOKEN_B" "$A_ID"
done

END=$(date +%s%3N)
TOTAL=$((END-START))
info "50 sequential messages sent in ${TOTAL}ms"

sleep 5

U_STRESS=$(unread_count "$TOKEN_A")
info "UNREAD AFTER STRESS = $U_STRESS"

# ---------------- MULTI DEVICE ----------------

step "MULTI DEVICE TEST"

start_ws "$TOKEN_A" "A_DEVICE1" "$B_ID" "yes"
start_ws "$TOKEN_A" "A_DEVICE2" "$B_ID" "yes"

sleep 2
send_message "$TOKEN_B" "$A_ID"
sleep 3

# ---------------- RESULT ----------------

step "FINAL RESULT"

echo "BEFORE = $U1"
echo "AFTER B = $U2"
echo "AFTER C = $U3"

if [ "$U3" = "0" ]; then
  pass "UNREAD FLOW PERFECT"
else
  fail "UNREAD BUG"
fi

pass "ALL TEST COMPLETE"
