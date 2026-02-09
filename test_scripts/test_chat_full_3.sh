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

# ---------------- LOGIN ----------------
login() {
  EMAIL=$1
  PASSWORD=$2

  RESP=$(curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

  TOKEN=$(echo "$RESP" | jq -r '.token' 2>/dev/null)
  echo "$TOKEN"
}

# ---------------- PROFILE ----------------
get_profile_id() {
  TOKEN=$1
  RESP=$(curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $TOKEN")
  echo "$RESP" | jq -r '.id'
}

# ---------------- SEND MESSAGE ----------------
send_message() {
  TOKEN=$1
  RECIPIENT_ID=$2

  curl -s -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$RECIPIENT_ID,\"content\":\"AUTO SEEN TEST\"}"
}

# ---------------- REALTIME ----------------
start_listener() {
  TOKEN=$1
  NAME=$2
  TARGET_ID=$3

  LOG_FILE="rt_${NAME}.log"
  PID_FILE="rt_${NAME}.pid"

  info "START WS $NAME"
  rm -f $LOG_FILE $PID_FILE

  (
    {
      sleep 1
      # SUB CHAT
      echo '{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}'
      sleep 1

      # SUB NOTI (ช่วย debug)
      echo '{"command":"subscribe","identifier":"{\"channel\":\"NotificationChannel\"}"}'
      sleep 1

      # B เปิดห้อง A
      if [ "$NAME" = "B" ]; then
        echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\"}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":$TARGET_ID}\"}"
        sleep 2   # ให้ Redis set ทัน
      fi

      sleep 999
    } | wscat -c "$WS_URL?token=$TOKEN"
  ) > $LOG_FILE 2>&1 &

  PID=$!
  echo $PID > $PID_FILE
  pass "WS $NAME PID=$PID"

  sleep 3
}

stop_listener() {
  NAME=$1
  PID_FILE="rt_${NAME}.pid"

  if [ -f $PID_FILE ]; then
    kill $(cat $PID_FILE) 2>/dev/null
    rm $PID_FILE
    pass "STOP WS $NAME"
  fi
}

assert_seen() {
  if grep -q "message_read" rt_A.log; then
    pass "AUTO SEEN OK"
  else
    fail "AUTO SEEN FAIL"
    echo "---- LOG A ----"
    cat rt_A.log
  fi
}

# ================= START =================
echo "========== AUTO SEEN TEST =========="

info "LOGIN A"
TOKEN_A=$(login $EMAIL_A $PASSWORD_A)
[ -z "$TOKEN_A" ] && fail "A LOGIN FAIL" && exit 1 || pass "A OK"

info "LOGIN B"
TOKEN_B=$(login $EMAIL_B $PASSWORD_B)
[ -z "$TOKEN_B" ] && fail "B LOGIN FAIL" && exit 1 || pass "B OK"

A_ID=$(get_profile_id $TOKEN_A)
B_ID=$(get_profile_id $TOKEN_B)

info "A_ID=$A_ID"
info "B_ID=$B_ID"

# เปิด WS
start_listener "$TOKEN_A" "A" "$B_ID"
start_listener "$TOKEN_B" "B" "$A_ID"

# ส่งข้อความ
info "A SEND MESSAGE"
send_message "$TOKEN_A" "$B_ID"

sleep 5

# ตรวจ Seen
assert_seen

# STOP
stop_listener "A"
stop_listener "B"

echo "========== END =========="
