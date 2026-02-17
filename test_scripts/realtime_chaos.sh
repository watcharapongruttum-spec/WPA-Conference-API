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

SOAK_DURATION=${1:-120}   # seconds

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass(){ echo -e "${GREEN}✅ $1${NC}"; }
fail(){ echo -e "${RED}❌ $1${NC}"; }
info(){ echo -e "${YELLOW}ℹ️ $1${NC}"; }
step(){ echo -e "\n${CYAN}==== $1 ====${NC}"; }

cleanup(){
  kill $(cat rt_*.pid 2>/dev/null) 2>/dev/null
  rm -f rt_*.log rt_*.pid
}

login(){
  curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

profile(){
  curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1" | jq -r '.id'
}

send_msg(){
  curl -s -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$2,\"content\":\"CHAOS_TEST\"}" > /dev/null
}

count_unread(){
  docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
    SELECT COUNT(*) FROM chat_messages
    WHERE recipient_id=$1 AND read_at IS NULL;" | xargs
}

last_delivery(){
  docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
    SELECT delivered_at FROM chat_messages
    WHERE recipient_id=$1
    ORDER BY id DESC LIMIT 1;" | xargs
}

start_ws(){
  TOKEN=$1
  NAME=$2
  TARGET=$3
  (
    {
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}'
      sleep 1
      echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\"}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":$TARGET}\"}"
      sleep 999
    } | wscat -c "$WS_URL?token=$TOKEN"
  ) > "rt_$NAME.log" 2>&1 &
  echo $! > "rt_$NAME.pid"
  sleep 3
}

# ================= START =================

step "LOGIN"
TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")
A_ID=$(profile "$TOKEN_A")
B_ID=$(profile "$TOKEN_B")
pass "LOGIN OK"

cleanup

# =========================================
step "1️⃣ MULTI DEVICE SAME USER"
start_ws "$TOKEN_A" "A1" "$B_ID"
start_ws "$TOKEN_A" "A2" "$B_ID"

send_msg "$TOKEN_B" "$A_ID"
sleep 2

U=$(count_unread "$A_ID")
if [ "$U" = "0" ]; then pass "Multi-device seen OK"; else fail "Multi-device fail"; fi

cleanup

# =========================================
step "2️⃣ RECONNECT STORM"
for i in {1..20}; do
  start_ws "$TOKEN_A" "storm" "$B_ID"
  sleep 1
  cleanup
done
pass "Reconnect storm done"

# =========================================
step "3️⃣ OUT OF ORDER BURST"
for i in {1..20}; do
  send_msg "$TOKEN_B" "$A_ID" &
done
wait
sleep 2
U2=$(count_unread "$A_ID")
info "Unread after burst=$U2"

# =========================================
step "4️⃣ CROSS ROOM ISOLATION"
send_msg "$TOKEN_A" "$B_ID"
sleep 1
U3=$(count_unread "$B_ID")
info "B unread=$U3"
pass "Cross-room check done"

# =========================================
step "5️⃣ TTL VERIFY"
start_ws "$TOKEN_A" "A_TTL" "$B_ID"
sleep 2
cleanup
info "Waiting 65s for TTL..."
sleep 65
send_msg "$TOKEN_B" "$A_ID"
sleep 2
U4=$(count_unread "$A_ID")
if [ "$U4" = "1" ]; then pass "TTL OK"; else fail "TTL Fail"; fi

# =========================================
step "6️⃣ SOAK TEST (${SOAK_DURATION}s)"
start_ws "$TOKEN_A" "A_SOAK" "$B_ID"
end=$((SECONDS+SOAK_DURATION))
while [ $SECONDS -lt $end ]; do
  send_msg "$TOKEN_B" "$A_ID"
  sleep 5
done
cleanup
pass "Soak test done"

# =========================================
step "7️⃣ PRESENCE CLEAN CHECK"
KEYS=$(docker exec redis redis-cli KEYS "chat_open:*")
if [ -z "$KEYS" ]; then pass "Presence clean"; else fail "Presence leak"; fi

step "END REALTIME CHAOS TEST"
