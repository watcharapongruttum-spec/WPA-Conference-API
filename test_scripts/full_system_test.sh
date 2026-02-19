#!/bin/bash

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

TOTAL_FAIL=0

pass(){ echo -e "${GREEN}✅ $1${NC}"; }
warn(){ echo -e "${YELLOW}⚠ $1${NC}"; }
fail(){ echo -e "${RED}❌ $1${NC}"; TOTAL_FAIL=$((TOTAL_FAIL+1)); }
step(){ echo -e "\n${CYAN}==== $1 ====${NC}"; }

login(){
  curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

get_id(){
  curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1" | jq -r '.id'
}

unread(){
  curl -s "$BASE_URL/api/v1/messages/unread_count?sender_id=$1" \
    -H "Authorization: Bearer $2" | jq -r '.unread_count'
}

send_msg(){
  curl -s -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$2,\"content\":\"$3\"}" > /dev/null
}

# ─── WebSocket helpers ───────────────────────────────────────────────────────

# start_ws NAME TOKEN [with_id]
#   เปิด WS connection เก็บ log ไว้ที่ rt_NAME.log
#   ถ้าส่ง with_id → subscribe พร้อม params (ใช้ใน enter_room ด้วย)
start_ws(){
  local NAME=$1
  local TOKEN=$2
  local WITH_ID=${3:-""}

  local IDENTIFIER
  if [ -n "$WITH_ID" ]; then
    IDENTIFIER="{\\\"channel\\\":\\\"ChatChannel\\\",\\\"with_id\\\":$WITH_ID}"
  else
    IDENTIFIER="{\\\"channel\\\":\\\"ChatChannel\\\"}"
  fi

  nohup bash -c "
    {
      sleep 1
      echo '{\"command\":\"subscribe\",\"identifier\":\"${IDENTIFIER}\"}'
      sleep 999
    } | timeout 120 wscat -c '${WS_URL}?token=${TOKEN}'
  " > "rt_${NAME}.log" 2>&1 &

  sleep 2
}

# enter_room NAME TOKEN TARGET_ID
#   เปิด WS connection แบบ background (persistent) แล้วส่ง enter_room action
#   connection จะอยู่จนกว่าจะ cleanup — Redis key จึงไม่หายก่อนเวลา
enter_room(){
  local NAME=$1
  local TOKEN=$2
  local TARGET_ID=$3
  local IDENTIFIER="{\\\"channel\\\":\\\"ChatChannel\\\"}"

  nohup bash -c "
    {
      sleep 0.3
      echo '{\"command\":\"subscribe\",\"identifier\":\"${IDENTIFIER}\"}'
      sleep 0.5
      echo '{\"command\":\"message\",\"identifier\":\"${IDENTIFIER}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":${TARGET_ID}}\"}'
      sleep 999
    } | timeout 120 wscat -c '${WS_URL}?token=${TOKEN}'
  " >> "rt_${NAME}_room.log" 2>&1 &

  sleep 2   # รอให้ enter_room action ถูกประมวลผลก่อน
}
cleanup(){
  pkill -f "wscat" 2>/dev/null || true
  sleep 1
  rm -f rt_A.log rt_B.log rt_A_room.log rt_B_room.log || true
}
trap cleanup EXIT

wait_until_zero(){
  local SENDER=$1
  local TOKEN=$2

  for i in {1..15}; do
    COUNT=$(unread "$SENDER" "$TOKEN")
    COUNT=${COUNT:-999}
    echo "  Checking unread... $COUNT"
    if [[ "$COUNT" =~ ^[0-9]+$ ]] && [ "$COUNT" -eq 0 ]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

############################################################
step "LOGIN"

TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")
A_ID=$(get_id "$TOKEN_A")
B_ID=$(get_id "$TOKEN_B")

[ -z "$TOKEN_A" ] && fail "Login A failed"
[ -z "$TOKEN_B" ] && fail "Login B failed"
pass "Login OK (A=$A_ID, B=$B_ID)"

############################################################
step "RESET STATE"

curl -s -X PATCH $BASE_URL/api/v1/messages/read_all \
  -H "Authorization: Bearer $TOKEN_A" > /dev/null
curl -s -X PATCH $BASE_URL/api/v1/messages/read_all \
  -H "Authorization: Bearer $TOKEN_B" > /dev/null
sleep 1
pass "State clean"

############################################################
step "CASE 1 — B ONLINE แต่ยังไม่ enter_room → ต้อง unread ยังอยู่"

cleanup
start_ws "A" "$TOKEN_A"
start_ws "B" "$TOKEN_B"   # B online แต่ไม่ได้เปิดห้องแชทกับ A

send_msg "$TOKEN_A" "$B_ID" "hello before enter"
sleep 2

U=$(unread "$A_ID" "$TOKEN_B")
if [ "$U" -ge 1 ]; then
  pass "Correct: unread=$U (B online แต่ยังไม่เปิดห้อง)"
else
  fail "Case 1 failed: ข้อความถูก mark read ทั้งที่ B ยังไม่เปิดห้องแชท (unread=$U)"
fi

############################################################
step "CASE 2 — B enter_room → ต้อง unread = 0"

# B กดเข้าห้องแชทกับ A
enter_room "B" "$TOKEN_B" "$A_ID"
sleep 2

U=$(unread "$A_ID" "$TOKEN_B")
if [ "$U" -eq 0 ]; then
  pass "Correct: unread=0 หลัง B enter_room"
else
  fail "Case 2 failed: unread=$U แม้ B enter_room แล้ว"
fi

############################################################
step "CASE 3 — B อยู่ในห้อง → ข้อความใหม่ต้อง mark read ทันที"

send_msg "$TOKEN_A" "$B_ID" "message while B is in room"
sleep 2

U=$(unread "$A_ID" "$TOKEN_B")
if [ "$U" -eq 0 ]; then
  pass "Correct: ข้อความใหม่ถูก mark read ทันทีเพราะ B อยู่ในห้อง"
else
  fail "Case 3 failed: unread=$U ทั้งที่ B อยู่ในห้องอยู่แล้ว"
fi

############################################################
step "CASE 4 — B OFFLINE → ต้อง unread สะสม"

cleanup   # disconnect ทุก WS
start_ws "A" "$TOKEN_A"
# B ไม่ได้ connect เลย

for i in {1..10}; do
  send_msg "$TOKEN_A" "$B_ID" "offline msg $i"
done
sleep 2

U=$(unread "$A_ID" "$TOKEN_B")
if [ "$U" -eq 10 ]; then
  pass "Offline unread correct (=$U)"
else
  fail "Case 4 failed: expected 10 got $U"
fi

############################################################
step "CASE 5 — B CONNECTS แต่ไม่ enter_room → unread ยังอยู่"

start_ws "B" "$TOKEN_B"   # B online แต่ไม่ enter_room
sleep 2

U=$(unread "$A_ID" "$TOKEN_B")
if [ "$U" -eq 10 ]; then
  pass "Correct: connect เฉยๆ ไม่ mark read (=$U)"
else
  fail "Case 5 failed: expected 10 got $U (ถูก mark read ทั้งที่ไม่ได้ enter_room)"
fi

############################################################
step "CASE 6 — B enter_room ทีหลัง → unread = 0"

enter_room "B" "$TOKEN_B" "$A_ID"
sleep 2

U=$(unread "$A_ID" "$TOKEN_B")
if [ "$U" -eq 0 ]; then
  pass "Late enter_room OK: unread=0"
else
  fail "Case 6 failed: unread=$U"
fi

############################################################
step "CASE 7 — RACE CHAT (ส่งข้อความพร้อมกัน แล้ว enter_room เพื่อ mark read)"

cleanup
start_ws "A" "$TOKEN_A"
start_ws "B" "$TOKEN_B"

# ส่งข้อความจากทั้งสองฝั่งพร้อมกัน
PIDS=()
for i in {1..10}; do
  send_msg "$TOKEN_A" "$B_ID" "A says $i" &
  PIDS+=($!)
  send_msg "$TOKEN_B" "$A_ID" "B says $i" &
  PIDS+=($!)
done
for pid in "${PIDS[@]}"; do wait $pid; done
sleep 1

# ตรวจว่ามี unread ก่อน enter_room
UA=$(unread "$B_ID" "$TOKEN_A")
UB=$(unread "$A_ID" "$TOKEN_B")
echo "  Before enter_room: A unread=$UA, B unread=$UB"

# ทั้งคู่ enter_room
enter_room "A" "$TOKEN_A" "$B_ID"
enter_room "B" "$TOKEN_B" "$A_ID"
sleep 2

UA_AFTER=$(unread "$B_ID" "$TOKEN_A")
UB_AFTER=$(unread "$A_ID" "$TOKEN_B")

if [ "$UA_AFTER" -eq 0 ]; then
  pass "Race A OK: unread=0 หลัง enter_room"
else
  warn "Race A: unread=$UA_AFTER"
fi

if [ "$UB_AFTER" -eq 0 ]; then
  pass "Race B OK: unread=0 หลัง enter_room"
else
  warn "Race B: unread=$UB_AFTER"
fi

############################################################
step "CASE 8 — BURST STRESS (B อยู่ในห้อง)"

for i in {1..30}; do
  send_msg "$TOKEN_A" "$B_ID" "burst $i"
done
sleep 3

COUNT=$(grep -c "new_message" rt_B.log 2>/dev/null || echo 0)
if [ "$COUNT" -ge 30 ]; then
  pass "Burst realtime OK ($COUNT/30)"
else
  warn "Burst incomplete ($COUNT/30)"
fi

############################################################

echo -e "\n========================================="
if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo -e "${GREEN}🔥 ALL TESTS COMPLETED (NO HARD FAIL) 🔥${NC}"
else
  echo -e "${RED}⚠ $TOTAL_FAIL TEST(S) FAILED${NC}"
fi
echo -e "========================================="