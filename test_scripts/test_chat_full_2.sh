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
debug() { echo -e "${CYAN}🐞 $1${NC}"; }

pretty_json() {
  echo "$1" | jq . 2>/dev/null || echo "$1"
}

assert_realtime() {
  KEY=$1
  DESC=$2
  LOG_FILE=$3

  if grep -q "$KEY" "$LOG_FILE"; then
    pass "REALTIME OK → $DESC"
  else
    fail "REALTIME FAIL → $DESC"
  fi
}

# ---------- LOGIN ----------
login() {
  EMAIL=$1
  PASSWORD=$2

  RESP=$(curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

  TOKEN=$(echo "$RESP" | jq -r '.token' 2>/dev/null)
  echo "$TOKEN"
}

# ---------- REST ----------
request() {
  USER=$1
  TOKEN=$2
  METHOD=$3
  URL=$4
  DATA=$5

  echo ""
  debug "[$USER] $METHOD $URL"
  debug "TIME: $(date +%H:%M:%S)"

  if [ -n "$DATA" ]; then
    debug "BODY RAW:"
    echo "$DATA"
    debug "BODY JSON:"
    pretty_json "$DATA"
  fi

  if [ -z "$DATA" ]; then
    RESP=$(curl -s -w "\n%{http_code}" -X $METHOD $URL \
      -H "Authorization: Bearer $TOKEN")
  else
    RESP=$(curl -s -w "\n%{http_code}" -X $METHOD $URL \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "$DATA")
  fi

  BODY=$(echo "$RESP" | head -n -1)
  CODE=$(echo "$RESP" | tail -n1)

  debug "HTTP: $CODE"
  debug "RESPONSE RAW:"
  echo "$BODY"
  debug "RESPONSE JSON:"
  pretty_json "$BODY"

  LAST_CODE=$CODE
  LAST_BODY=$BODY
}

# ---------- REALTIME ----------
start_realtime_listener() {
  TOKEN=$1
  NAME=$2

  LOG_FILE="realtime_${NAME}.log"
  PID_FILE="realtime_${NAME}.pid"

  info "START REALTIME $NAME"
  rm -f $LOG_FILE $PID_FILE

  (
    {
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}'
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"NotificationChannel\"}"}'
      sleep 999
    } | wscat -c "$WS_URL?token=$TOKEN"
  ) > $LOG_FILE 2>&1 &

  PID=$!
  echo $PID > $PID_FILE
  pass "Realtime $NAME PID=$PID"

  sleep 3
}

stop_realtime_listener() {
  NAME=$1
  PID_FILE="realtime_${NAME}.pid"

  if [ -f $PID_FILE ]; then
    PID=$(cat $PID_FILE)
    kill $PID 2>/dev/null
    rm $PID_FILE
    pass "Stopped Realtime $NAME"
  fi
}

# ================= START =================
echo "================ CHAT DEBUG FULL ================"

info "Login A"
TOKEN_A=$(login $EMAIL_A $PASSWORD_A)
[ -z "$TOKEN_A" ] && fail "Login A Failed" && exit 1 || pass "A OK"

request "A" "$TOKEN_A" GET "$BASE_URL/api/v1/profile"
A_ID=$(echo "$LAST_BODY" | jq -r '.id')

info "Login B"
TOKEN_B=$(login $EMAIL_B $PASSWORD_B)
[ -z "$TOKEN_B" ] && fail "Login B Failed" && exit 1 || pass "B OK"

request "B" "$TOKEN_B" GET "$BASE_URL/api/v1/profile"
B_ID=$(echo "$LAST_BODY" | jq -r '.id')

# เปิด realtime 2 คน
start_realtime_listener "$TOKEN_A" "A"
start_realtime_listener "$TOKEN_B" "B"

# ---------- SEND ----------
info "A SEND → B"
request "A" "$TOKEN_A" POST "$BASE_URL/api/v1/messages" \
  "{\"recipient_id\":$B_ID,\"content\":\"hello realtime\"}"

MSG_ID=$(echo "$LAST_BODY" | jq -r '.id')

sleep 3
assert_realtime "new_message" "Send Message" "realtime_B.log"
assert_realtime "new_notification" "Notification" "realtime_B.log"

# ---------- EDIT ----------
info "A EDIT"
request "A" "$TOKEN_A" PUT "$BASE_URL/api/v1/messages/$MSG_ID" \
  '{"content":"edited realtime"}'

sleep 2
assert_realtime "message_updated" "Edit Message" "realtime_B.log"

# ---------- DELETE ----------
info "A DELETE"
request "A" "$TOKEN_A" DELETE "$BASE_URL/api/v1/messages/$MSG_ID"

sleep 2
assert_realtime "message_deleted" "Delete Message" "realtime_B.log"

# ---------- READ ----------
info "B READ ALL"
request "B" "$TOKEN_B" PATCH "$BASE_URL/api/v1/messages/read_all"

sleep 2
assert_realtime "message_read" "Read Message" "realtime_A.log"

# ---------- ROOM ----------
info "CREATE ROOM"
request "A" "$TOKEN_A" POST "$BASE_URL/api/v1/chat_rooms" \
  '{"title":"DebugRoom","room_kind":"group"}'

ROOM_ID=$(echo "$LAST_BODY" | jq -r '.id')

info "DELETE ROOM"
request "A" "$TOKEN_A" DELETE "$BASE_URL/api/v1/chat_rooms/$ROOM_ID"

# ---------- STOP ----------
stop_realtime_listener "A"
stop_realtime_listener "B"

echo ""
info "REALTIME SUMMARY A"
grep '"type"' realtime_A.log

echo ""
info "REALTIME SUMMARY B"
grep '"type"' realtime_B.log

echo ""
pass "ALL DONE"
echo "================ END ================"
