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

  sleep 2
}

# leave_room TOKEN TARGET_ID
#   ส่ง leave_room action → ล้าง active_room Redis key ก่อน disconnect
leave_room(){
  local TOKEN=$1
  local TARGET_ID=$2
  local IDENTIFIER="{\\\"channel\\\":\\\"ChatChannel\\\"}"

  bash -c "
    {
      sleep 0.3
      echo '{\"command\":\"subscribe\",\"identifier\":\"${IDENTIFIER}\"}'
      sleep 0.5
      echo '{\"command\":\"message\",\"identifier\":\"${IDENTIFIER}\",\"data\":\"{\\\"action\\\":\\\"leave_room\\\",\\\"user_id\\\":${TARGET_ID}}\"}'
      sleep 1
    } | timeout 10 wscat -c '${WS_URL}?token=${TOKEN}'
  " >> "rt_leave.log" 2>&1
  sleep 1
}

# cleanup_room A_TOKEN B_TOKEN A_ID B_ID
#   ส่ง leave_room ก่อนเสมอ → ล้าง active_room Redis key → แล้วค่อย kill wscat
cleanup_room(){
  local TOKEN_A=$1
  local TOKEN_B=$2
  local A_ID=$3
  local B_ID=$4

  leave_room "$TOKEN_A" "$B_ID" 2>/dev/null
  leave_room "$TOKEN_B" "$A_ID" 2>/dev/null
  pkill -f "wscat" 2>/dev/null || true
  sleep 1
  rm -f rt_*.log 2>/dev/null || true
}

cleanup(){
  pkill -f "wscat" 2>/dev/null || true
  sleep 1
  rm -f rt_*.log 2>/dev/null || true
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
# ล้าง Redis active_room key ของทั้งคู่ก่อนเริ่ม
leave_room "$TOKEN_A" "$B_ID"
leave_room "$TOKEN_B" "$A_ID"
cleanup
pass "State clean"

############################################################
step "CASE 1 — B ONLINE แต่ยังไม่ enter_room → ต้อง unread ยังอยู่"

start_ws "A" "$TOKEN_A"
start_ws "B" "$TOKEN_B"   # B online แต่ไม่ enter_room

send_msg "$TOKEN_A" "$B_ID" "hello before enter"
sleep 2

U=$(unread "$A_ID" "$TOKEN_B")
if [ "$U" -ge 1 ]; then
  pass "Correct: unread=$U (B online แต่ยังไม่เปิดห้อง)"
else
  fail "Case 1 failed: unread=$U — ตรวจสอบว่า subscribed ใน chat_channel.rb ไม่มี mark_all_for_user"
fi

############################################################
step "CASE 2 — B enter_room → ต้อง unread = 0"

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

# ล้าง active_room key ก่อน disconnect เพื่อไม่ให้ค้าง
cleanup_room "$TOKEN_A" "$TOKEN_B" "$A_ID" "$B_ID"
start_ws "A" "$TOKEN_A"
# B ไม่ connect เลย

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

start_ws "B" "$TOKEN_B"
sleep 2

U=$(unread "$A_ID" "$TOKEN_B")
if [ "$U" -eq 10 ]; then
  pass "Correct: connect เฉยๆ ไม่ mark read (=$U)"
else
  fail "Case 5 failed: expected 10 got $U — ตรวจสอบว่า subscribed ไม่มี mark_all_for_user"
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

cleanup_room "$TOKEN_A" "$TOKEN_B" "$A_ID" "$B_ID"
start_ws "A" "$TOKEN_A"
start_ws "B" "$TOKEN_B"

PIDS=()
for i in {1..10}; do
  send_msg "$TOKEN_A" "$B_ID" "A says $i" &
  PIDS+=($!)
  send_msg "$TOKEN_B" "$A_ID" "B says $i" &
  PIDS+=($!)
done
for pid in "${PIDS[@]}"; do wait $pid; done
sleep 1

UA=$(unread "$B_ID" "$TOKEN_A")
UB=$(unread "$A_ID" "$TOKEN_B")
echo "  Before enter_room: A unread=$UA, B unread=$UB"

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

COUNT=$(grep -c "new_message" rt_B.log 2>/dev/null | tail -1 || echo 0)
COUNT=$(echo "$COUNT" | tr -d '[:space:]')
if [ "${COUNT:-0}" -ge 30 ]; then
  pass "Burst realtime OK ($COUNT/30)"
else
  warn "Burst incomplete ($COUNT/30)"
fi

# ════════════════════════════════════════════════════════════════════════════
# BUG FIX TESTS
# ════════════════════════════════════════════════════════════════════════════

############################################################
step "BUG 1 — MULTI-CONNECTION: ปิด 1 tab ไม่ควรลบ active_room ของ tab อื่น"

cleanup_room "$TOKEN_A" "$TOKEN_B" "$A_ID" "$B_ID"
enter_room "B_tab1" "$TOKEN_B" "$A_ID"
start_ws   "B_tab2" "$TOKEN_B"
sleep 1

send_msg "$TOKEN_A" "$B_ID" "msg while B has 2 connections"
sleep 2

U=$(unread "$A_ID" "$TOKEN_B")
if [ "$U" -eq 0 ]; then
  pass "Multi-connection OK: active_room ยังอยู่ auto-mark ทำงาน (unread=$U)"
else
  fail "Multi-connection failed: unread=$U (active_room หายเพราะ connection อื่น)"
fi

############################################################
step "BUG 2 — LEAVE_ROOM: ออกจากห้องแล้วต้องไม่ auto-mark"

cleanup_room "$TOKEN_A" "$TOKEN_B" "$A_ID" "$B_ID"
enter_room "B" "$TOKEN_B" "$A_ID"
sleep 1

leave_room "$TOKEN_B" "$A_ID"
sleep 1

send_msg "$TOKEN_A" "$B_ID" "msg after B left room"
sleep 2

U=$(unread "$A_ID" "$TOKEN_B")
if [ "$U" -ge 1 ]; then
  pass "leave_room OK: ไม่ auto-mark หลัง leave_room (unread=$U)"
else
  fail "leave_room failed: ข้อความถูก auto-mark ทั้งที่ B ออกจากห้องแล้ว (unread=$U)"
fi

############################################################
step "BUG 3 — NO DEBUG LOG: ไม่ควรมี 🔍 auto_mark check ใน log"

cleanup_room "$TOKEN_A" "$TOKEN_B" "$A_ID" "$B_ID"
enter_room "B" "$TOKEN_B" "$A_ID"
sleep 1
send_msg "$TOKEN_A" "$B_ID" "debug log check"
sleep 2

# เช็กที่ source file โดยตรง — แม่นกว่าเช็ก log ที่มี entry เก่าค้างอยู่
SVC_FILE=""
for path in \
  "../app/services/chat/send_message_service.rb" \
  "../../app/services/chat/send_message_service.rb" \
  "$HOME/mikkee_pro/WPA-Conference-API/app/services/chat/send_message_service.rb"; do
  [ -f "$path" ] && SVC_FILE="$path" && break
done

if [ -n "$SVC_FILE" ]; then
  if grep -q "auto_mark check" "$SVC_FILE"; then
    fail "Debug log ยังอยู่ใน source — ลบออกจาก send_message_service.rb ด้วย"
  else
    pass "No debug log OK (ลบออกจาก source แล้ว)"
  fi
else
  warn "ไม่พบ send_message_service.rb — ตรวจเองด้วย: grep '🔍' app/services/chat/send_message_service.rb"
fi

############################################################

cleanup

echo ""
echo "========================================="
if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo -e "${GREEN}🔥 ALL TESTS COMPLETED (NO HARD FAIL) 🔥${NC}"
else
  echo -e "${RED}⚠ $TOTAL_FAIL TEST(S) FAILED${NC}"
fi
echo "========================================="