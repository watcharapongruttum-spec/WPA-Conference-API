# #!/bin/bash

# BASE_URL="http://localhost:3000"
# WS_URL="ws://localhost:3000/cable"

# EMAIL_A="narisara.lasan@bestgloballogistics.com"
# PASSWORD_A="123456"

# EMAIL_B="shammi@1shammi1.com"
# PASSWORD_B="RNIrSPPICj"

# GREEN='\033[0;32m'
# RED='\033[0;31m'
# YELLOW='\033[1;33m'
# CYAN='\033[0;36m'
# NC='\033[0m'

# TOTAL_FAIL=0

# pass(){ echo -e "${GREEN}✅ $1${NC}"; }
# warn(){ echo -e "${YELLOW}⚠ $1${NC}"; }
# fail(){ echo -e "${RED}❌ $1${NC}"; TOTAL_FAIL=$((TOTAL_FAIL+1)); }
# step(){ echo -e "\n${CYAN}==== $1 ====${NC}"; }

# login(){
#   curl -s $BASE_URL/api/v1/login \
#     -H "Content-Type: application/json" \
#     -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
# }

# get_id(){
#   curl -s $BASE_URL/api/v1/profile \
#     -H "Authorization: Bearer $1" | jq -r '.id'
# }

# unread(){
#   curl -s "$BASE_URL/api/v1/messages/unread_count?sender_id=$1" \
#     -H "Authorization: Bearer $2" | jq -r '.unread_count'
# }

# send_msg(){
#   curl -s -X POST $BASE_URL/api/v1/messages \
#     -H "Authorization: Bearer $1" \
#     -H "Content-Type: application/json" \
#     -d "{\"recipient_id\":$2,\"content\":\"$3\"}" > /dev/null
# }

# # ─── WebSocket helpers ───────────────────────────────────────────────────────

# start_ws(){
#   local NAME=$1
#   local TOKEN=$2
#   local WITH_ID=${3:-""}

#   local IDENTIFIER
#   if [ -n "$WITH_ID" ]; then
#     IDENTIFIER="{\\\"channel\\\":\\\"ChatChannel\\\",\\\"with_id\\\":$WITH_ID}"
#   else
#     IDENTIFIER="{\\\"channel\\\":\\\"ChatChannel\\\"}"
#   fi

#   nohup bash -c "
#     {
#       sleep 1
#       echo '{\"command\":\"subscribe\",\"identifier\":\"${IDENTIFIER}\"}'
#       sleep 999
#     } | timeout 120 wscat -c '${WS_URL}?token=${TOKEN}'
#   " > "rt_${NAME}.log" 2>&1 &

#   sleep 2
# }

# enter_room(){
#   local NAME=$1
#   local TOKEN=$2
#   local TARGET_ID=$3
#   local IDENTIFIER="{\\\"channel\\\":\\\"ChatChannel\\\"}"

#   nohup bash -c "
#     {
#       sleep 0.3
#       echo '{\"command\":\"subscribe\",\"identifier\":\"${IDENTIFIER}\"}'
#       sleep 0.5
#       echo '{\"command\":\"message\",\"identifier\":\"${IDENTIFIER}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":${TARGET_ID}}\"}'
#       sleep 999
#     } | timeout 120 wscat -c '${WS_URL}?token=${TOKEN}'
#   " >> "rt_${NAME}_room.log" 2>&1 &

#   sleep 2
# }

# # leave_room TOKEN TARGET_ID
# #   ส่ง leave_room action → ล้าง active_room Redis key ก่อน disconnect
# leave_room(){
#   local TOKEN=$1
#   local TARGET_ID=$2
#   local IDENTIFIER="{\\\"channel\\\":\\\"ChatChannel\\\"}"

#   bash -c "
#     {
#       sleep 0.3
#       echo '{\"command\":\"subscribe\",\"identifier\":\"${IDENTIFIER}\"}'
#       sleep 0.5
#       echo '{\"command\":\"message\",\"identifier\":\"${IDENTIFIER}\",\"data\":\"{\\\"action\\\":\\\"leave_room\\\",\\\"user_id\\\":${TARGET_ID}}\"}'
#       sleep 1
#     } | timeout 10 wscat -c '${WS_URL}?token=${TOKEN}'
#   " >> "rt_leave.log" 2>&1
#   sleep 1
# }

# # cleanup_room A_TOKEN B_TOKEN A_ID B_ID
# #   ส่ง leave_room ก่อนเสมอ → ล้าง active_room Redis key → แล้วค่อย kill wscat
# cleanup_room(){
#   local TOKEN_A=$1
#   local TOKEN_B=$2
#   local A_ID=$3
#   local B_ID=$4

#   leave_room "$TOKEN_A" "$B_ID" 2>/dev/null
#   leave_room "$TOKEN_B" "$A_ID" 2>/dev/null
#   pkill -f "wscat" 2>/dev/null || true
#   sleep 1
#   rm -f rt_*.log 2>/dev/null || true
# }

# cleanup(){
#   pkill -f "wscat" 2>/dev/null || true
#   sleep 1
#   rm -f rt_*.log 2>/dev/null || true
# }
# trap cleanup EXIT

# wait_until_zero(){
#   local SENDER=$1
#   local TOKEN=$2

#   for i in {1..15}; do
#     COUNT=$(unread "$SENDER" "$TOKEN")
#     COUNT=${COUNT:-999}
#     echo "  Checking unread... $COUNT"
#     if [[ "$COUNT" =~ ^[0-9]+$ ]] && [ "$COUNT" -eq 0 ]; then
#       return 0
#     fi
#     sleep 1
#   done
#   return 1
# }

# ############################################################
# step "LOGIN"

# TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
# TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")
# A_ID=$(get_id "$TOKEN_A")
# B_ID=$(get_id "$TOKEN_B")

# [ -z "$TOKEN_A" ] && fail "Login A failed"
# [ -z "$TOKEN_B" ] && fail "Login B failed"
# pass "Login OK (A=$A_ID, B=$B_ID)"

# ############################################################
# step "RESET STATE"

# curl -s -X PATCH $BASE_URL/api/v1/messages/read_all \
#   -H "Authorization: Bearer $TOKEN_A" > /dev/null
# curl -s -X PATCH $BASE_URL/api/v1/messages/read_all \
#   -H "Authorization: Bearer $TOKEN_B" > /dev/null
# # ล้าง Redis active_room key ของทั้งคู่ก่อนเริ่ม
# leave_room "$TOKEN_A" "$B_ID"
# leave_room "$TOKEN_B" "$A_ID"
# cleanup
# pass "State clean"

# ############################################################
# step "CASE 1 — B ONLINE แต่ยังไม่ enter_room → ต้อง unread ยังอยู่"

# start_ws "A" "$TOKEN_A"
# start_ws "B" "$TOKEN_B"   # B online แต่ไม่ enter_room

# send_msg "$TOKEN_A" "$B_ID" "hello before enter"
# sleep 2

# U=$(unread "$A_ID" "$TOKEN_B")
# if [ "$U" -ge 1 ]; then
#   pass "Correct: unread=$U (B online แต่ยังไม่เปิดห้อง)"
# else
#   fail "Case 1 failed: unread=$U — ตรวจสอบว่า subscribed ใน chat_channel.rb ไม่มี mark_all_for_user"
# fi

# ############################################################
# step "CASE 2 — B enter_room → ต้อง unread = 0"

# enter_room "B" "$TOKEN_B" "$A_ID"
# sleep 2

# U=$(unread "$A_ID" "$TOKEN_B")
# if [ "$U" -eq 0 ]; then
#   pass "Correct: unread=0 หลัง B enter_room"
# else
#   fail "Case 2 failed: unread=$U แม้ B enter_room แล้ว"
# fi

# ############################################################
# step "CASE 3 — B อยู่ในห้อง → ข้อความใหม่ต้อง mark read ทันที"

# send_msg "$TOKEN_A" "$B_ID" "message while B is in room"
# sleep 2

# U=$(unread "$A_ID" "$TOKEN_B")
# if [ "$U" -eq 0 ]; then
#   pass "Correct: ข้อความใหม่ถูก mark read ทันทีเพราะ B อยู่ในห้อง"
# else
#   fail "Case 3 failed: unread=$U ทั้งที่ B อยู่ในห้องอยู่แล้ว"
# fi

# ############################################################
# step "CASE 4 — B OFFLINE → ต้อง unread สะสม"

# # ล้าง active_room key ก่อน disconnect เพื่อไม่ให้ค้าง
# cleanup_room "$TOKEN_A" "$TOKEN_B" "$A_ID" "$B_ID"
# start_ws "A" "$TOKEN_A"
# # B ไม่ connect เลย

# for i in {1..10}; do
#   send_msg "$TOKEN_A" "$B_ID" "offline msg $i"
# done
# sleep 2

# U=$(unread "$A_ID" "$TOKEN_B")
# if [ "$U" -eq 10 ]; then
#   pass "Offline unread correct (=$U)"
# else
#   fail "Case 4 failed: expected 10 got $U"
# fi

# ############################################################
# step "CASE 5 — B CONNECTS แต่ไม่ enter_room → unread ยังอยู่"

# start_ws "B" "$TOKEN_B"
# sleep 2

# U=$(unread "$A_ID" "$TOKEN_B")
# if [ "$U" -eq 10 ]; then
#   pass "Correct: connect เฉยๆ ไม่ mark read (=$U)"
# else
#   fail "Case 5 failed: expected 10 got $U — ตรวจสอบว่า subscribed ไม่มี mark_all_for_user"
# fi

# ############################################################
# step "CASE 6 — B enter_room ทีหลัง → unread = 0"

# enter_room "B" "$TOKEN_B" "$A_ID"
# sleep 2

# U=$(unread "$A_ID" "$TOKEN_B")
# if [ "$U" -eq 0 ]; then
#   pass "Late enter_room OK: unread=0"
# else
#   fail "Case 6 failed: unread=$U"
# fi

# ############################################################
# step "CASE 7 — RACE CHAT (ส่งข้อความพร้อมกัน แล้ว enter_room เพื่อ mark read)"

# cleanup_room "$TOKEN_A" "$TOKEN_B" "$A_ID" "$B_ID"
# start_ws "A" "$TOKEN_A"
# start_ws "B" "$TOKEN_B"

# PIDS=()
# for i in {1..10}; do
#   send_msg "$TOKEN_A" "$B_ID" "A says $i" &
#   PIDS+=($!)
#   send_msg "$TOKEN_B" "$A_ID" "B says $i" &
#   PIDS+=($!)
# done
# for pid in "${PIDS[@]}"; do wait $pid; done
# sleep 1

# UA=$(unread "$B_ID" "$TOKEN_A")
# UB=$(unread "$A_ID" "$TOKEN_B")
# echo "  Before enter_room: A unread=$UA, B unread=$UB"

# enter_room "A" "$TOKEN_A" "$B_ID"
# enter_room "B" "$TOKEN_B" "$A_ID"
# sleep 2

# UA_AFTER=$(unread "$B_ID" "$TOKEN_A")
# UB_AFTER=$(unread "$A_ID" "$TOKEN_B")

# if [ "$UA_AFTER" -eq 0 ]; then
#   pass "Race A OK: unread=0 หลัง enter_room"
# else
#   warn "Race A: unread=$UA_AFTER"
# fi

# if [ "$UB_AFTER" -eq 0 ]; then
#   pass "Race B OK: unread=0 หลัง enter_room"
# else
#   warn "Race B: unread=$UB_AFTER"
# fi

# ############################################################
# step "CASE 8 — BURST STRESS (B อยู่ในห้อง)"

# for i in {1..30}; do
#   send_msg "$TOKEN_A" "$B_ID" "burst $i"
# done
# sleep 3

# COUNT=$(grep -c "new_message" rt_B.log 2>/dev/null | tail -1 || echo 0)
# COUNT=$(echo "$COUNT" | tr -d '[:space:]')
# if [ "${COUNT:-0}" -ge 30 ]; then
#   pass "Burst realtime OK ($COUNT/30)"
# else
#   warn "Burst incomplete ($COUNT/30)"
# fi

# # ════════════════════════════════════════════════════════════════════════════
# # BUG FIX TESTS
# # ════════════════════════════════════════════════════════════════════════════

# ############################################################
# step "BUG 1 — MULTI-CONNECTION: ปิด 1 tab ไม่ควรลบ active_room ของ tab อื่น"

# cleanup_room "$TOKEN_A" "$TOKEN_B" "$A_ID" "$B_ID"
# enter_room "B_tab1" "$TOKEN_B" "$A_ID"
# start_ws   "B_tab2" "$TOKEN_B"
# sleep 1

# send_msg "$TOKEN_A" "$B_ID" "msg while B has 2 connections"
# sleep 2

# U=$(unread "$A_ID" "$TOKEN_B")
# if [ "$U" -eq 0 ]; then
#   pass "Multi-connection OK: active_room ยังอยู่ auto-mark ทำงาน (unread=$U)"
# else
#   fail "Multi-connection failed: unread=$U (active_room หายเพราะ connection อื่น)"
# fi

# ############################################################
# step "BUG 2 — LEAVE_ROOM: ออกจากห้องแล้วต้องไม่ auto-mark"

# cleanup_room "$TOKEN_A" "$TOKEN_B" "$A_ID" "$B_ID"
# enter_room "B" "$TOKEN_B" "$A_ID"
# sleep 1

# leave_room "$TOKEN_B" "$A_ID"
# sleep 1

# send_msg "$TOKEN_A" "$B_ID" "msg after B left room"
# sleep 2

# U=$(unread "$A_ID" "$TOKEN_B")
# if [ "$U" -ge 1 ]; then
#   pass "leave_room OK: ไม่ auto-mark หลัง leave_room (unread=$U)"
# else
#   fail "leave_room failed: ข้อความถูก auto-mark ทั้งที่ B ออกจากห้องแล้ว (unread=$U)"
# fi

# ############################################################
# step "BUG 3 — NO DEBUG LOG: ไม่ควรมี 🔍 auto_mark check ใน log"

# cleanup_room "$TOKEN_A" "$TOKEN_B" "$A_ID" "$B_ID"
# enter_room "B" "$TOKEN_B" "$A_ID"
# sleep 1
# send_msg "$TOKEN_A" "$B_ID" "debug log check"
# sleep 2

# # เช็กที่ source file โดยตรง — แม่นกว่าเช็ก log ที่มี entry เก่าค้างอยู่
# SVC_FILE=""
# for path in \
#   "../app/services/chat/send_message_service.rb" \
#   "../../app/services/chat/send_message_service.rb" \
#   "$HOME/mikkee_pro/WPA-Conference-API/app/services/chat/send_message_service.rb"; do
#   [ -f "$path" ] && SVC_FILE="$path" && break
# done

# if [ -n "$SVC_FILE" ]; then
#   if grep -q "auto_mark check" "$SVC_FILE"; then
#     fail "Debug log ยังอยู่ใน source — ลบออกจาก send_message_service.rb ด้วย"
#   else
#     pass "No debug log OK (ลบออกจาก source แล้ว)"
#   fi
# else
#   warn "ไม่พบ send_message_service.rb — ตรวจเองด้วย: grep '🔍' app/services/chat/send_message_service.rb"
# fi

# ############################################################

# cleanup

# echo ""
# echo "========================================="
# if [ "$TOTAL_FAIL" -eq 0 ]; then
#   echo -e "${GREEN}🔥 ALL TESTS COMPLETED (NO HARD FAIL) 🔥${NC}"
# else
#   echo -e "${RED}⚠ $TOTAL_FAIL TEST(S) FAILED${NC}"
# fi
# echo "========================================="











#!/bin/bash
# =============================================================
# WPA Conference API — Full System Test Suite
# เทสทุก endpoint จำลองการใช้งานจริงของ user
# =============================================================

BASE_URL="http://localhost:3000"

# ---------- Test Users ----------
EMAIL_A="narisara.lasan@bestgloballogistics.com";  PASSWORD_A="123456"
EMAIL_B="shammi@1shammi1.com";                     PASSWORD_B="RNIrSPPICj"

# ---------- Colors ----------
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

# ---------- Log Setup ----------
LOG_DIR="./test_logs_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

LOG_MAIN="$LOG_DIR/00_summary.txt"
LOG_AUTH="$LOG_DIR/01_auth.txt"
LOG_PROFILE="$LOG_DIR/02_profile.txt"
LOG_DELEGATES="$LOG_DIR/03_delegates.txt"
LOG_SCHEDULES="$LOG_DIR/04_schedules.txt"
LOG_TABLES="$LOG_DIR/05_tables.txt"
LOG_NETWORKING="$LOG_DIR/06_networking.txt"
LOG_REQUESTS="$LOG_DIR/07_connection_requests.txt"
LOG_MESSAGES="$LOG_DIR/08_messages.txt"
LOG_CHATROOMS="$LOG_DIR/09_chat_rooms.txt"
LOG_NOTIFICATIONS="$LOG_DIR/10_notifications.txt"
LOG_DASHBOARD="$LOG_DIR/11_dashboard.txt"
LOG_LEAVE="$LOG_DIR/12_leave.txt"
LOG_DEVICE="$LOG_DIR/13_device.txt"
LOG_ERRORS="$LOG_DIR/99_errors.txt"

# ---------- Counters ----------
PASS=0; FAIL=0; SKIP=0
START_TIME=$(date +%s)

# =============================================================
# HELPERS
# =============================================================

log_to(){ echo "$1" >> "$2"; }

pass(){
  echo -e "${GREEN}  ✅ $1${NC}"
  echo "  PASS: $1" >> "$LOG_MAIN"
  PASS=$((PASS+1))
}

fail(){
  echo -e "${RED}  ❌ $1${NC}"
  echo "  FAIL: $1" >> "$LOG_MAIN"
  echo "FAIL: $1" >> "$LOG_ERRORS"
  FAIL=$((FAIL+1))
}

skip(){
  echo -e "${YELLOW}  ⏭  $1${NC}"
  echo "  SKIP: $1" >> "$LOG_MAIN"
  SKIP=$((SKIP+1))
}

section(){
  echo ""
  echo -e "${CYAN}${BOLD}════════════════════════════════════════${NC}"
  echo -e "${CYAN}${BOLD}  $1${NC}"
  echo -e "${CYAN}${BOLD}════════════════════════════════════════${NC}"
  echo "" >> "$LOG_MAIN"
  echo "════ $1 ════" >> "$LOG_MAIN"
}

subsection(){
  echo -e "\n${YELLOW}  ── $1 ──${NC}"
  echo "" >> "$LOG_MAIN"
  echo "  ── $1 ──" >> "$LOG_MAIN"
}

# HTTP helper: คืน "BODY\nSTATUS_CODE"
http_get(){
  local url=$1 token=$2
  curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $token" \
    "$BASE_URL$url"
}

http_post(){
  local url=$1 token=$2 body=$3
  curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$body" \
    "$BASE_URL$url"
}

http_patch(){
  local url=$1 token=$2 body=$3
  curl -s -w "\n%{http_code}" \
    -X PATCH \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$body" \
    "$BASE_URL$url"
}

http_delete(){
  local url=$1 token=$2
  curl -s -w "\n%{http_code}" \
    -X DELETE \
    -H "Authorization: Bearer $token" \
    "$BASE_URL$url"
}

extract_body(){ echo "$1" | head -1; }
extract_code(){ echo "$1" | tail -1; }

check(){
  # check "label" "$response" expected_code [log_file]
  local label=$1 resp=$2 expected=$3 logfile=${4:-$LOG_MAIN}
  local code=$(extract_code "$resp")
  local body=$(extract_body "$resp")

  echo "  [$(date +%H:%M:%S)] $label" >> "$logfile"
  echo "  HTTP: $code" >> "$logfile"
  echo "  Body: $body" >> "$logfile"
  echo "" >> "$logfile"

  if [ "$code" -eq "$expected" ]; then
    pass "$label (HTTP $code)"
  else
    fail "$label — Expected $expected, got $code"
    echo "  Detail: $body" >> "$LOG_ERRORS"
    echo "" >> "$LOG_ERRORS"
  fi
}

# =============================================================
# WRITE HEADER
# =============================================================
{
  echo "WPA Conference API — Full System Test"
  echo "Run at: $(date)"
  echo "Base URL: $BASE_URL"
  echo "============================================"
  echo ""
} > "$LOG_MAIN"

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║   WPA Conference API — Full System Test  ║"
echo "║   $(date +%Y-%m-%d\ %H:%M:%S)                       ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo "  Logs → $LOG_DIR"


# =============================================================
# SECTION 1: AUTHENTICATION
# =============================================================
section "1. AUTHENTICATION"

echo "[AUTH TESTS - $(date)]" > "$LOG_AUTH"

subsection "1.1 Login"

# Login A
R=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL_A\",\"password\":\"$PASSWORD_A\"}" \
  "$BASE_URL/api/v1/login")
check "Login User A" "$R" 200 "$LOG_AUTH"
TOKEN_A=$(extract_body "$R" | jq -r '.token // empty')
A_ID=$(extract_body "$R" | jq -r '.delegate.id // empty')

# Login B
R=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL_B\",\"password\":\"$PASSWORD_B\"}" \
  "$BASE_URL/api/v1/login")
check "Login User B" "$R" 200 "$LOG_AUTH"
TOKEN_B=$(extract_body "$R" | jq -r '.token // empty')
B_ID=$(extract_body "$R" | jq -r '.delegate.id // empty')

echo "  User A: id=$A_ID" | tee -a "$LOG_AUTH"
echo "  User B: id=$B_ID" | tee -a "$LOG_AUTH"

if [ -z "$TOKEN_A" ] || [ -z "$TOKEN_B" ]; then
  echo -e "${RED}  FATAL: Login failed — cannot continue${NC}"
  echo "FATAL: Login failed" >> "$LOG_ERRORS"
  exit 1
fi

subsection "1.2 Login — invalid credentials"
R=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d '{"email":"wrong@email.com","password":"wrongpass"}' \
  "$BASE_URL/api/v1/login")
check "Login with wrong password → 401" "$R" 401 "$LOG_AUTH"

subsection "1.3 Login — missing fields"
R=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d '{"email":""}' \
  "$BASE_URL/api/v1/login")
check "Login with empty fields → 422" "$R" 422 "$LOG_AUTH"

subsection "1.4 Change Password (A)"
ORIG_PASS="$PASSWORD_A"
R=$(http_patch "/api/v1/change_password" "$TOKEN_A" \
  "{\"current_password\":\"$ORIG_PASS\",\"new_password\":\"newpass123\",\"new_password_confirmation\":\"newpass123\"}")
check "Change password success → 200" "$R" 200 "$LOG_AUTH"

# Login again with new password
R=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL_A\",\"password\":\"newpass123\"}" \
  "$BASE_URL/api/v1/login")
check "Login with new password → 200" "$R" 200 "$LOG_AUTH"

# Revert password
R=$(http_patch "/api/v1/change_password" "$TOKEN_A" \
  "{\"current_password\":\"newpass123\",\"new_password\":\"$ORIG_PASS\",\"new_password_confirmation\":\"$ORIG_PASS\"}")
check "Revert password → 200" "$R" 200 "$LOG_AUTH"

subsection "1.5 Change Password — wrong current"
R=$(http_patch "/api/v1/change_password" "$TOKEN_A" \
  '{"current_password":"wrongcurrent","new_password":"abc12345","new_password_confirmation":"abc12345"}')
check "Change password wrong current → 401" "$R" 401 "$LOG_AUTH"

subsection "1.6 Change Password — mismatch confirmation"
R=$(http_patch "/api/v1/change_password" "$TOKEN_A" \
  "{\"current_password\":\"$PASSWORD_A\",\"new_password\":\"newpass123\",\"new_password_confirmation\":\"different\"}")
check "Change password mismatch → 422" "$R" 422 "$LOG_AUTH"

subsection "1.7 Forgot Password"
R=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL_A\"}" \
  "$BASE_URL/api/v1/forgot_password")
check "Forgot password (valid email) → 200" "$R" 200 "$LOG_AUTH"

R=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d '{"email":"nonexistent@nobody.com"}' \
  "$BASE_URL/api/v1/forgot_password")
check "Forgot password (nonexistent email) → 200" "$R" 200 "$LOG_AUTH"

subsection "1.8 Access without token → 401"
R=$(curl -s -w "\n%{http_code}" "$BASE_URL/api/v1/profile")
check "Access profile without token → 401" "$R" 401 "$LOG_AUTH"


# =============================================================
# SECTION 2: PROFILE
# =============================================================
section "2. PROFILE"

echo "[PROFILE TESTS - $(date)]" > "$LOG_PROFILE"

subsection "2.1 Get own profile"
R=$(http_get "/api/v1/profile" "$TOKEN_A")
check "GET /profile (own) → 200" "$R" 200 "$LOG_PROFILE"
echo "  Profile A: $(extract_body "$R" | jq -c '{id,name,email}' 2>/dev/null)" | tee -a "$LOG_PROFILE"

subsection "2.2 Get profile by ID"
R=$(http_get "/api/v1/profile/$B_ID" "$TOKEN_A")
check "GET /profile/:id → 200" "$R" 200 "$LOG_PROFILE"

subsection "2.3 Get profile — nonexistent ID"
R=$(http_get "/api/v1/profile/99999999" "$TOKEN_A")
check "GET /profile/99999999 → 404" "$R" 404 "$LOG_PROFILE"

subsection "2.4 Update profile"
R=$(http_patch "/api/v1/profile" "$TOKEN_A" \
  '{"phone":"0812345678"}')
check "PATCH /profile → 200" "$R" 200 "$LOG_PROFILE"

subsection "2.5 /delegates profile endpoint"
R=$(http_get "/api/v1/delegates/profile" "$TOKEN_A")
check "GET /delegates/profile → 200" "$R" 200 "$LOG_PROFILE"


# =============================================================
# SECTION 3: DELEGATES
# =============================================================
section "3. DELEGATES"

echo "[DELEGATE TESTS - $(date)]" > "$LOG_DELEGATES"

subsection "3.1 List delegates"
R=$(http_get "/api/v1/delegates" "$TOKEN_A")
check "GET /delegates → 200" "$R" 200 "$LOG_DELEGATES"
DELEGATE_COUNT=$(extract_body "$R" | jq 'length' 2>/dev/null)
echo "  Total delegates (page 1): $DELEGATE_COUNT" | tee -a "$LOG_DELEGATES"

subsection "3.2 Get delegate by ID"
R=$(http_get "/api/v1/delegates/$B_ID" "$TOKEN_A")
check "GET /delegates/:id → 200" "$R" 200 "$LOG_DELEGATES"

subsection "3.3 Get own ID via delegates → 422"
R=$(http_get "/api/v1/delegates/$A_ID" "$TOKEN_A")
check "GET /delegates/:own_id → 422" "$R" 422 "$LOG_DELEGATES"

subsection "3.4 Delegates — nonexistent"
R=$(http_get "/api/v1/delegates/99999999" "$TOKEN_A")
check "GET /delegates/99999999 → 404" "$R" 404 "$LOG_DELEGATES"

subsection "3.5 Search delegates — keyword"
R=$(http_get "/api/v1/delegates/search?keyword=a" "$TOKEN_A")
check "GET /delegates/search?keyword=a → 200" "$R" 200 "$LOG_DELEGATES"
FIRST_DELEGATE_ID=$(extract_body "$R" | jq -r '.data[0].id // empty' 2>/dev/null)
echo "  First result ID: $FIRST_DELEGATE_ID" | tee -a "$LOG_DELEGATES"

subsection "3.6 Search delegates — empty keyword"
R=$(http_get "/api/v1/delegates/search?keyword=" "$TOKEN_A")
check "GET /delegates/search (empty) → 200" "$R" 200 "$LOG_DELEGATES"

subsection "3.7 Search delegates — pagination"
R=$(http_get "/api/v1/delegates/search?keyword=a&page=2&per_page=5" "$TOKEN_A")
check "GET /delegates/search (page 2) → 200" "$R" 200 "$LOG_DELEGATES"

subsection "3.8 QR Code"
R=$(http_get "/api/v1/delegates/$B_ID/qr_code" "$TOKEN_A")
check "GET /delegates/:id/qr_code → 200" "$R" 200 "$LOG_DELEGATES"
HAS_QR=$(extract_body "$R" | jq -r '.qr_code // empty' 2>/dev/null | head -c 20)
echo "  QR starts with: $HAS_QR..." | tee -a "$LOG_DELEGATES"


# =============================================================
# SECTION 4: DASHBOARD
# =============================================================
section "4. DASHBOARD"

echo "[DASHBOARD TESTS - $(date)]" > "$LOG_DASHBOARD"

subsection "4.1 Get dashboard"
R=$(http_get "/api/v1/dashboard" "$TOKEN_A")
check "GET /dashboard → 200" "$R" 200 "$LOG_DASHBOARD"
echo "  Dashboard: $(extract_body "$R" | jq -c '.' 2>/dev/null)" | tee -a "$LOG_DASHBOARD"

R=$(http_get "/api/v1/dashboard" "$TOKEN_B")
check "GET /dashboard (user B) → 200" "$R" 200 "$LOG_DASHBOARD"


# =============================================================
# SECTION 5: SCHEDULES
# =============================================================
section "5. SCHEDULES"

echo "[SCHEDULE TESTS - $(date)]" > "$LOG_SCHEDULES"

subsection "5.1 List schedules"
R=$(http_get "/api/v1/schedules" "$TOKEN_A")
check "GET /schedules → 200" "$R" 200 "$LOG_SCHEDULES"

subsection "5.2 My schedule"
R=$(http_get "/api/v1/schedules/my_schedule" "$TOKEN_A")
check "GET /schedules/my_schedule → 200" "$R" 200 "$LOG_SCHEDULES"
echo "  Years: $(extract_body "$R" | jq '.available_years' 2>/dev/null)" | tee -a "$LOG_SCHEDULES"
echo "  Dates: $(extract_body "$R" | jq '.available_dates | length' 2>/dev/null) dates" | tee -a "$LOG_SCHEDULES"

subsection "5.3 My schedule with date filter"
SCHED_YEAR=$(http_get "/api/v1/schedules/my_schedule" "$TOKEN_A" | head -1 | jq -r '.year // empty' 2>/dev/null)
if [ -n "$SCHED_YEAR" ]; then
  R=$(http_get "/api/v1/schedules/my_schedule?year=$SCHED_YEAR" "$TOKEN_A")
  check "GET /schedules/my_schedule?year=$SCHED_YEAR → 200" "$R" 200 "$LOG_SCHEDULES"
fi

subsection "5.4 Schedule others"
R=$(http_get "/api/v1/schedules/schedule_others?delegate_id=$B_ID" "$TOKEN_A")
SC=$(extract_code "$R")
if [ "$SC" -eq 200 ] || [ "$SC" -eq 404 ]; then
  pass "GET /schedules/schedule_others?delegate_id=$B_ID → $SC (200 or 404 ok)"
  echo "  schedule_others: HTTP $SC" >> "$LOG_SCHEDULES"
else
  fail "GET /schedules/schedule_others — Expected 200/404, got $SC"
fi

subsection "5.5 Schedule others — missing delegate_id"
R=$(http_get "/api/v1/schedules/schedule_others" "$TOKEN_A")
SC=$(extract_code "$R")
if [ "$SC" -eq 404 ] || [ "$SC" -eq 422 ] || [ "$SC" -eq 400 ]; then
  pass "schedule_others missing delegate_id → $SC (error response ok)"
else
  fail "schedule_others missing delegate_id — got $SC"
fi


# =============================================================
# SECTION 6: TABLES
# =============================================================
section "6. TABLES"

echo "[TABLE TESTS - $(date)]" > "$LOG_TABLES"

subsection "6.1 Grid view"
R=$(http_get "/api/v1/tables/grid_view" "$TOKEN_A")
check "GET /tables/grid_view → 200" "$R" 200 "$LOG_TABLES"
TABLE_COUNT=$(extract_body "$R" | jq 'length' 2>/dev/null)
echo "  Tables in grid: $TABLE_COUNT" | tee -a "$LOG_TABLES"

subsection "6.2 Time view"
R=$(http_get "/api/v1/tables/time_view" "$TOKEN_A")
check "GET /tables/time_view → 200" "$R" 200 "$LOG_TABLES"
echo "  Time view date: $(extract_body "$R" | jq -r '.date' 2>/dev/null)" | tee -a "$LOG_TABLES"

subsection "6.3 Time view with filters"
R=$(http_get "/api/v1/tables/time_view?date=$(date +%Y-%m-%d)" "$TOKEN_A")
check "GET /tables/time_view?date=today → 200" "$R" 200 "$LOG_TABLES"

subsection "6.4 Table show"
FIRST_TABLE_NUM=$(http_get "/api/v1/tables/grid_view" "$TOKEN_A" | head -1 | jq -r '.[0].table_number // empty' 2>/dev/null)
if [ -n "$FIRST_TABLE_NUM" ]; then
  R=$(http_get "/api/v1/tables/$FIRST_TABLE_NUM" "$TOKEN_A")
  check "GET /tables/$FIRST_TABLE_NUM → 200" "$R" 200 "$LOG_TABLES"
else
  skip "Table show — no tables found"
fi


# =============================================================
# SECTION 7: NETWORKING — DIRECTORY & CONNECTIONS
# =============================================================
section "7. NETWORKING"

echo "[NETWORKING TESTS - $(date)]" > "$LOG_NETWORKING"

subsection "7.1 Directory"
R=$(http_get "/api/v1/networking/directory" "$TOKEN_A")
check "GET /networking/directory → 200" "$R" 200 "$LOG_NETWORKING"
DIR_COUNT=$(extract_body "$R" | jq 'length' 2>/dev/null)
echo "  Directory count: $DIR_COUNT" | tee -a "$LOG_NETWORKING"

subsection "7.2 Directory — pagination"
R=$(http_get "/api/v1/networking/directory?page=2" "$TOKEN_A")
check "GET /networking/directory?page=2 → 200" "$R" 200 "$LOG_NETWORKING"

subsection "7.3 My connections"
R=$(http_get "/api/v1/networking/my_connections" "$TOKEN_A")
check "GET /networking/my_connections → 200" "$R" 200 "$LOG_NETWORKING"
CONN_COUNT=$(extract_body "$R" | jq 'length' 2>/dev/null)
echo "  A connections: $CONN_COUNT" | tee -a "$LOG_NETWORKING"

subsection "7.4 Pending requests"
R=$(http_get "/api/v1/networking/pending_requests" "$TOKEN_A")
check "GET /networking/pending_requests → 200" "$R" 200 "$LOG_NETWORKING"


# =============================================================
# SECTION 8: CONNECTION REQUESTS (FRIEND SYSTEM)
# =============================================================
section "8. CONNECTION REQUESTS"

echo "[CONNECTION REQUEST TESTS - $(date)]" > "$LOG_REQUESTS"

# --- Helper: cleanup existing connection between A and B ---
cleanup_connection(){
  echo "  [cleanup] Removing existing connection/request between A($A_ID) and B($B_ID)..." | tee -a "$LOG_REQUESTS"
  # ลบ connection request (ทั้ง A→B และ B→A)
  curl -s -o /dev/null -X DELETE \
    -H "Authorization: Bearer $TOKEN_A" \
    "$BASE_URL/api/v1/requests/$B_ID/cancel"
  curl -s -o /dev/null -X DELETE \
    -H "Authorization: Bearer $TOKEN_B" \
    "$BASE_URL/api/v1/requests/$A_ID/cancel"
  # unfriend
  curl -s -o /dev/null -X DELETE \
    -H "Authorization: Bearer $TOKEN_A" \
    "$BASE_URL/api/v1/networking/unfriend/$B_ID"
}

subsection "8.1 Cleanup state"
cleanup_connection

subsection "8.2 List all requests"
R=$(http_get "/api/v1/requests" "$TOKEN_A")
check "GET /requests → 200" "$R" 200 "$LOG_REQUESTS"

subsection "8.3 My received requests"
R=$(http_get "/api/v1/requests/my_received" "$TOKEN_B")
check "GET /requests/my_received (B) → 200" "$R" 200 "$LOG_REQUESTS"

subsection "8.4 Send friend request A→B"
R=$(http_post "/api/v1/requests" "$TOKEN_A" "{\"target_id\":$B_ID}")
SC=$(extract_code "$R")
if [ "$SC" -eq 201 ]; then
  check "POST /requests (A→B) → 201" "$R" 201 "$LOG_REQUESTS"
  REQ_ID=$(extract_body "$R" | jq -r '.id // empty')
  echo "  Request ID: $REQ_ID" | tee -a "$LOG_REQUESTS"
elif [ "$SC" -eq 422 ]; then
  # Already exists — find it
  echo "  Request already exists, finding pending..." | tee -a "$LOG_REQUESTS"
  REQ_ID=$(http_get "/api/v1/requests/my_received" "$TOKEN_B" | head -1 \
    | jq -r --argjson aid "$A_ID" '[.[] | select(.requester.id == $aid)] | .[0].id // empty' 2>/dev/null)
  if [ -n "$REQ_ID" ] && [ "$REQ_ID" != "null" ]; then
    pass "POST /requests — found existing pending id=$REQ_ID"
  else
    fail "POST /requests → 422 and no pending found"
  fi
else
  fail "POST /requests (A→B) — Expected 201, got $SC"
fi

subsection "8.5 Send request to self → 422"
R=$(http_post "/api/v1/requests" "$TOKEN_A" "{\"target_id\":$A_ID}")
check "POST /requests to self → 422" "$R" 422 "$LOG_REQUESTS"

subsection "8.6 Duplicate request → 422"
R=$(http_post "/api/v1/requests" "$TOKEN_A" "{\"target_id\":$B_ID}")
check "POST /requests duplicate → 422" "$R" 422 "$LOG_REQUESTS"

subsection "8.7 Accept request (B accepts)"
if [ -n "$REQ_ID" ] && [ "$REQ_ID" != "null" ]; then
  R=$(http_patch "/api/v1/requests/$REQ_ID/accept" "$TOKEN_B" '{}')
  check "PATCH /requests/:id/accept → 200" "$R" 200 "$LOG_REQUESTS"
else
  skip "Accept — no request ID available"
fi

subsection "8.8 Verify connection created"
R=$(http_get "/api/v1/networking/my_connections" "$TOKEN_A")
IS_FRIEND=$(extract_body "$R" | jq --argjson bid "$B_ID" \
  '[.[] | select((.requester.id == $bid) or (.target.id == $bid))] | length' 2>/dev/null)
if [ "${IS_FRIEND:-0}" -gt 0 ]; then
  pass "Connection confirmed: A and B are friends"
else
  fail "Connection NOT found after accept"
fi
echo "  Connections after accept: $(extract_body "$R" | jq 'length' 2>/dev/null)" | tee -a "$LOG_REQUESTS"

subsection "8.9 Unfriend A→B"
R=$(http_delete "/api/v1/networking/unfriend/$B_ID" "$TOKEN_A")
check "DELETE /networking/unfriend/:id → 200" "$R" 200 "$LOG_REQUESTS"

subsection "8.10 Unfriend again → 404"
R=$(http_delete "/api/v1/networking/unfriend/$B_ID" "$TOKEN_A")
check "DELETE /networking/unfriend (duplicate) → 404" "$R" 404 "$LOG_REQUESTS"

subsection "8.11 Reject flow: A→B request, B rejects"
# cleanup
cleanup_connection
R=$(http_post "/api/v1/requests" "$TOKEN_A" "{\"target_id\":$B_ID}")
REJ_REQ_ID=$(extract_body "$R" | jq -r '.id // empty')
if [ -n "$REJ_REQ_ID" ] && [ "$REJ_REQ_ID" != "null" ]; then
  R=$(http_patch "/api/v1/requests/$REJ_REQ_ID/reject" "$TOKEN_B" '{}')
  check "PATCH /requests/:id/reject → 200" "$R" 200 "$LOG_REQUESTS"
else
  skip "Reject flow — could not create request"
fi

subsection "8.12 Request nonexistent target → 404"
R=$(http_post "/api/v1/requests" "$TOKEN_A" '{"target_id":99999999}')
check "POST /requests nonexistent target → 404" "$R" 404 "$LOG_REQUESTS"

# Re-establish friendship for later tests
subsection "8.13 Re-establish friendship for downstream tests"
cleanup_connection
R=$(http_post "/api/v1/requests" "$TOKEN_A" "{\"target_id\":$B_ID}")
REQ_ID2=$(extract_body "$R" | jq -r '.id // empty')
if [ -n "$REQ_ID2" ] && [ "$REQ_ID2" != "null" ]; then
  R=$(http_patch "/api/v1/requests/$REQ_ID2/accept" "$TOKEN_B" '{}')
  check "Re-establish friendship → 200" "$R" 200 "$LOG_REQUESTS"
else
  skip "Re-establish — could not get request ID"
fi


# =============================================================
# SECTION 9: MESSAGES (CHAT)
# =============================================================
section "9. MESSAGES"

echo "[MESSAGE TESTS - $(date)]" > "$LOG_MESSAGES"

subsection "9.1 Send message A→B"
R=$(http_post "/api/v1/messages" "$TOKEN_A" \
  "{\"message\":{\"recipient_id\":$B_ID,\"content\":\"Hello from A! This is a test message.\"}}")
check "POST /messages (A→B) → 201" "$R" 201 "$LOG_MESSAGES"
MSG_ID=$(extract_body "$R" | jq -r '.id // empty')
echo "  Message ID: $MSG_ID" | tee -a "$LOG_MESSAGES"

subsection "9.2 Send message B→A"
R=$(http_post "/api/v1/messages" "$TOKEN_B" \
  "{\"message\":{\"recipient_id\":$A_ID,\"content\":\"Hi A, replying from B!\"}}")
check "POST /messages (B→A) → 201" "$R" 201 "$LOG_MESSAGES"
MSG_ID_B=$(extract_body "$R" | jq -r '.id // empty')

subsection "9.3 Send message — blank content → 422"
R=$(http_post "/api/v1/messages" "$TOKEN_A" \
  "{\"message\":{\"recipient_id\":$B_ID,\"content\":\"\"}}")
check "POST /messages blank content → 422" "$R" 422 "$LOG_MESSAGES"

subsection "9.4 Send message — missing recipient → 422"
R=$(http_post "/api/v1/messages" "$TOKEN_A" \
  '{"message":{"content":"no recipient"}}')
check "POST /messages no recipient → 422" "$R" 422 "$LOG_MESSAGES"

subsection "9.5 Send message — over 2000 chars → 422"
LONG_MSG=$(python3 -c "print('x'*2001)" 2>/dev/null || printf '%2001s' | tr ' ' 'x')
R=$(http_post "/api/v1/messages" "$TOKEN_A" \
  "{\"message\":{\"recipient_id\":$B_ID,\"content\":\"$LONG_MSG\"}}")
check "POST /messages over 2000 chars → 422" "$R" 422 "$LOG_MESSAGES"

subsection "9.6 List messages"
R=$(http_get "/api/v1/messages" "$TOKEN_A")
check "GET /messages → 200" "$R" 200 "$LOG_MESSAGES"
echo "  Message count: $(extract_body "$R" | jq 'length' 2>/dev/null)" | tee -a "$LOG_MESSAGES"

subsection "9.7 Conversation A↔B"
R=$(http_get "/api/v1/messages/conversation/$B_ID" "$TOKEN_A")
check "GET /messages/conversation/:id → 200" "$R" 200 "$LOG_MESSAGES"
echo "  Conversation messages: $(extract_body "$R" | jq '.meta.total_count' 2>/dev/null)" | tee -a "$LOG_MESSAGES"

subsection "9.8 Conversation — pagination"
R=$(http_get "/api/v1/messages/conversation/$B_ID?page=1&per=5" "$TOKEN_A")
check "GET /messages/conversation (paged) → 200" "$R" 200 "$LOG_MESSAGES"

subsection "9.9 Rooms list"
R=$(http_get "/api/v1/messages/rooms" "$TOKEN_A")
check "GET /messages/rooms → 200" "$R" 200 "$LOG_MESSAGES"
echo "  Rooms: $(extract_body "$R" | jq 'length' 2>/dev/null)" | tee -a "$LOG_MESSAGES"

subsection "9.10 Unread count"
R=$(http_get "/api/v1/messages/unread_count?sender_id=$B_ID" "$TOKEN_A")
check "GET /messages/unread_count → 200" "$R" 200 "$LOG_MESSAGES"
echo "  Unread from B: $(extract_body "$R" | jq '.unread_count' 2>/dev/null)" | tee -a "$LOG_MESSAGES"

subsection "9.11 Unread count — invalid sender_id"
R=$(http_get "/api/v1/messages/unread_count?sender_id=abc" "$TOKEN_A")
check "GET /messages/unread_count invalid id → 200 (returns 0)" "$R" 200 "$LOG_MESSAGES"

subsection "9.12 Online status"
R=$(http_get "/api/v1/messages/online_status?user_id=$B_ID" "$TOKEN_A")
check "GET /messages/online_status → 200" "$R" 200 "$LOG_MESSAGES"

subsection "9.13 Update message (edit)"
if [ -n "$MSG_ID" ] && [ "$MSG_ID" != "null" ]; then
  R=$(http_patch "/api/v1/messages/$MSG_ID" "$TOKEN_A" \
    '{"message":{"content":"Edited message content"}}')
  check "PATCH /messages/:id (own) → 200" "$R" 200 "$LOG_MESSAGES"
else
  skip "Edit message — no message ID"
fi

subsection "9.14 Update message — not owner → 403"
if [ -n "$MSG_ID_B" ] && [ "$MSG_ID_B" != "null" ]; then
  R=$(http_patch "/api/v1/messages/$MSG_ID_B" "$TOKEN_A" \
    '{"message":{"content":"Trying to edit B message"}}')
  check "PATCH /messages/:id (not owner) → 403" "$R" 403 "$LOG_MESSAGES"
else
  skip "Edit not-owner — no message ID from B"
fi

subsection "9.15 Read all messages"
R=$(http_patch "/api/v1/messages/read_all" "$TOKEN_A" '{}')
check "PATCH /messages/read_all → 200" "$R" 200 "$LOG_MESSAGES"

subsection "9.16 Delete message"
if [ -n "$MSG_ID" ] && [ "$MSG_ID" != "null" ]; then
  R=$(http_delete "/api/v1/messages/$MSG_ID" "$TOKEN_A")
  check "DELETE /messages/:id → 200" "$R" 200 "$LOG_MESSAGES"
else
  skip "Delete message — no message ID"
fi

subsection "9.17 Delete already-deleted → 422"
if [ -n "$MSG_ID" ] && [ "$MSG_ID" != "null" ]; then
  R=$(http_delete "/api/v1/messages/$MSG_ID" "$TOKEN_A")
  check "DELETE /messages (already deleted) → 422" "$R" 422 "$LOG_MESSAGES"
else
  skip "Delete again — no message ID"
fi


# =============================================================
# SECTION 10: CHAT ROOMS
# =============================================================
section "10. CHAT ROOMS"

echo "[CHAT ROOM TESTS - $(date)]" > "$LOG_CHATROOMS"

subsection "10.1 List chat rooms"
R=$(http_get "/api/v1/chat_rooms" "$TOKEN_A")
check "GET /chat_rooms → 200" "$R" 200 "$LOG_CHATROOMS"
echo "  Rooms: $(extract_body "$R" | jq 'length' 2>/dev/null)" | tee -a "$LOG_CHATROOMS"

subsection "10.2 Create group room"
R=$(http_post "/api/v1/chat_rooms" "$TOKEN_A" \
  '{"chat_room":{"title":"Test Group Room","room_kind":"group"}}')
check "POST /chat_rooms (group) → 201" "$R" 201 "$LOG_CHATROOMS"
ROOM_ID=$(extract_body "$R" | jq -r '.id // empty')
echo "  Room ID: $ROOM_ID" | tee -a "$LOG_CHATROOMS"

subsection "10.3 Create room — missing params → 400"
R=$(http_post "/api/v1/chat_rooms" "$TOKEN_A" '{}')
check "POST /chat_rooms missing params → 400" "$R" 400 "$LOG_CHATROOMS"

subsection "10.4 Join room (B joins)"
if [ -n "$ROOM_ID" ] && [ "$ROOM_ID" != "null" ]; then
  R=$(http_post "/api/v1/chat_rooms/$ROOM_ID/join" "$TOKEN_B" '{}')
  check "POST /chat_rooms/:id/join (B) → 200" "$R" 200 "$LOG_CHATROOMS"
else
  skip "Join room — no room created"
fi

subsection "10.5 Join room again (idempotent)"
if [ -n "$ROOM_ID" ] && [ "$ROOM_ID" != "null" ]; then
  R=$(http_post "/api/v1/chat_rooms/$ROOM_ID/join" "$TOKEN_B" '{}')
  check "POST /chat_rooms/:id/join (again) → 200" "$R" 200 "$LOG_CHATROOMS"
fi

subsection "10.6 Leave room (B leaves)"
if [ -n "$ROOM_ID" ] && [ "$ROOM_ID" != "null" ]; then
  R=$(http_delete "/api/v1/chat_rooms/$ROOM_ID/leave" "$TOKEN_B")
  check "DELETE /chat_rooms/:id/leave (B) → 200" "$R" 200 "$LOG_CHATROOMS"
else
  skip "Leave room — no room ID"
fi

subsection "10.7 Leave room (not member) → 404"
if [ -n "$ROOM_ID" ] && [ "$ROOM_ID" != "null" ]; then
  R=$(http_delete "/api/v1/chat_rooms/$ROOM_ID/leave" "$TOKEN_B")
  check "DELETE /chat_rooms/:id/leave (not member) → 404" "$R" 404 "$LOG_CHATROOMS"
fi

subsection "10.8 Delete room (A = admin)"
if [ -n "$ROOM_ID" ] && [ "$ROOM_ID" != "null" ]; then
  R=$(http_delete "/api/v1/chat_rooms/$ROOM_ID" "$TOKEN_A")
  check "DELETE /chat_rooms/:id (admin) → 200" "$R" 200 "$LOG_CHATROOMS"
else
  skip "Delete room — no room ID"
fi

subsection "10.9 Delete room — nonexistent → 404"
R=$(http_delete "/api/v1/chat_rooms/99999999" "$TOKEN_A")
check "DELETE /chat_rooms/99999999 → 404" "$R" 404 "$LOG_CHATROOMS"


# =============================================================
# SECTION 11: NOTIFICATIONS
# =============================================================
section "11. NOTIFICATIONS"

echo "[NOTIFICATION TESTS - $(date)]" > "$LOG_NOTIFICATIONS"

subsection "11.1 List all notifications"
R=$(http_get "/api/v1/notifications" "$TOKEN_A")
check "GET /notifications → 200" "$R" 200 "$LOG_NOTIFICATIONS"
NOTIF_COUNT=$(extract_body "$R" | jq 'length' 2>/dev/null)
echo "  Notifications: $NOTIF_COUNT" | tee -a "$LOG_NOTIFICATIONS"
FIRST_NOTIF_ID=$(extract_body "$R" | jq -r '.[0].id // empty' 2>/dev/null)

subsection "11.2 Filter — system notifications"
R=$(http_get "/api/v1/notifications?type=system" "$TOKEN_A")
check "GET /notifications?type=system → 200" "$R" 200 "$LOG_NOTIFICATIONS"

subsection "11.3 Filter — message notifications"
R=$(http_get "/api/v1/notifications?type=message" "$TOKEN_A")
check "GET /notifications?type=message → 200" "$R" 200 "$LOG_NOTIFICATIONS"

subsection "11.4 Unread count"
R=$(http_get "/api/v1/notifications/unread_count" "$TOKEN_A")
check "GET /notifications/unread_count → 200" "$R" 200 "$LOG_NOTIFICATIONS"
echo "  Unread: $(extract_body "$R" | jq '.unread_count' 2>/dev/null)" | tee -a "$LOG_NOTIFICATIONS"

subsection "11.5 Unread count — by type"
R=$(http_get "/api/v1/notifications/unread_count?type=system" "$TOKEN_A")
check "GET /notifications/unread_count?type=system → 200" "$R" 200 "$LOG_NOTIFICATIONS"

subsection "11.6 Mark single notification as read"
if [ -n "$FIRST_NOTIF_ID" ] && [ "$FIRST_NOTIF_ID" != "null" ]; then
  R=$(http_patch "/api/v1/notifications/$FIRST_NOTIF_ID/mark_as_read" "$TOKEN_A" '{}')
  check "PATCH /notifications/:id/mark_as_read → 200" "$R" 200 "$LOG_NOTIFICATIONS"
else
  skip "Mark as read — no notification found"
fi

subsection "11.7 Mark single (already read) → 200"
if [ -n "$FIRST_NOTIF_ID" ] && [ "$FIRST_NOTIF_ID" != "null" ]; then
  R=$(http_patch "/api/v1/notifications/$FIRST_NOTIF_ID/mark_as_read" "$TOKEN_A" '{}')
  check "PATCH /notifications/:id/mark_as_read (already read) → 200" "$R" 200 "$LOG_NOTIFICATIONS"
fi

subsection "11.8 Mark single — not found → 404"
R=$(http_patch "/api/v1/notifications/99999999/mark_as_read" "$TOKEN_A" '{}')
check "PATCH /notifications/99999999/mark_as_read → 404" "$R" 404 "$LOG_NOTIFICATIONS"

subsection "11.9 Mark all as read"
R=$(http_patch "/api/v1/notifications/mark_all_as_read" "$TOKEN_A" '{}')
check "PATCH /notifications/mark_all_as_read → 200" "$R" 200 "$LOG_NOTIFICATIONS"
echo "  Marked: $(extract_body "$R" | jq '.count' 2>/dev/null)" | tee -a "$LOG_NOTIFICATIONS"

subsection "11.10 Mark all as read — by type"
R=$(http_patch "/api/v1/notifications/mark_all_as_read?type=message" "$TOKEN_A" '{}')
check "PATCH /notifications/mark_all_as_read?type=message → 200" "$R" 200 "$LOG_NOTIFICATIONS"


# =============================================================
# SECTION 12: LEAVE FORMS & TYPES
# =============================================================
section "12. LEAVE FORMS & TYPES"

echo "[LEAVE TESTS - $(date)]" > "$LOG_LEAVE"

subsection "12.1 List leave types"
R=$(http_get "/api/v1/leave_types" "$TOKEN_A")
check "GET /leave_types → 200" "$R" 200 "$LOG_LEAVE"
LEAVE_TYPES=$(extract_body "$R" | jq 'length' 2>/dev/null)
echo "  Leave types: $LEAVE_TYPES" | tee -a "$LOG_LEAVE"
LEAVE_TYPE_ID=$(extract_body "$R" | jq -r '.[0].id // empty' 2>/dev/null)

subsection "12.2 Get single leave type"
if [ -n "$LEAVE_TYPE_ID" ] && [ "$LEAVE_TYPE_ID" != "null" ]; then
  R=$(http_get "/api/v1/leave_types/$LEAVE_TYPE_ID" "$TOKEN_A")
  check "GET /leave_types/:id → 200" "$R" 200 "$LOG_LEAVE"
else
  skip "Get leave type — none found"
fi

subsection "12.3 Create leave form"
# Need a schedule ID first
SCHED_ID=$(http_get "/api/v1/schedules/my_schedule" "$TOKEN_A" | head -1 \
  | jq -r '[.schedules[] | select(.type == "meeting")] | .[0].id // empty' 2>/dev/null)

if [ -n "$SCHED_ID" ] && [ "$SCHED_ID" != "null" ] && \
   [ -n "$LEAVE_TYPE_ID" ] && [ "$LEAVE_TYPE_ID" != "null" ]; then
  R=$(http_post "/api/v1/leave_forms" "$TOKEN_A" \
    "{\"leave_form\":{\"leaves\":[{\"schedule_id\":$SCHED_ID,\"leave_type_id\":$LEAVE_TYPE_ID,\"explanation\":\"Test leave\"}]}}")
  SC=$(extract_code "$R")
  if [ "$SC" -eq 200 ] || [ "$SC" -eq 201 ]; then
    pass "POST /leave_forms → $SC"
    echo "  Leave form created" >> "$LOG_LEAVE"
  else
    fail "POST /leave_forms → Expected 200/201, got $SC"
    echo "  Body: $(extract_body "$R")" >> "$LOG_LEAVE"
  fi
else
  skip "Create leave form — no schedule or leave_type found"
fi


# =============================================================
# SECTION 13: DEVICE TOKEN
# =============================================================
section "13. DEVICE TOKEN"

echo "[DEVICE TOKEN TESTS - $(date)]" > "$LOG_DEVICE"

subsection "13.1 Update device token"
FAKE_TOKEN="ExponentPushToken:test-device-token-abc123"
R=$(http_patch "/api/v1/device_token" "$TOKEN_A" \
  "{\"device\":{\"device_token\":\"$FAKE_TOKEN\"}}")
check "PATCH /device_token → 200" "$R" 200 "$LOG_DEVICE"

subsection "13.2 Update device token — same value (idempotent)"
R=$(http_patch "/api/v1/device_token" "$TOKEN_A" \
  "{\"device\":{\"device_token\":\"$FAKE_TOKEN\"}}")
check "PATCH /device_token (same) → 200" "$R" 200 "$LOG_DEVICE"

subsection "13.3 Update device token — missing → 422"
R=$(http_patch "/api/v1/device_token" "$TOKEN_A" '{"device":{}}')
check "PATCH /device_token (missing) → 422" "$R" 422 "$LOG_DEVICE"


# =============================================================
# SECTION 14: SECURITY / EDGE CASES
# =============================================================
section "14. SECURITY & EDGE CASES"

subsection "14.1 Invalid JWT token"
R=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: Bearer invalidtokenxxx" \
  "$BASE_URL/api/v1/profile")
check "Invalid token → 401" "$R" 401 "$LOG_AUTH"

subsection "14.2 Malformed Authorization header"
R=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: NotBearer something" \
  "$BASE_URL/api/v1/profile")
check "Malformed auth header → 401" "$R" 401 "$LOG_AUTH"

subsection "14.3 Access other user's notification → 404"
NOTIF_B_ID=$(http_get "/api/v1/notifications" "$TOKEN_B" | head -1 | jq -r '.[0].id // empty' 2>/dev/null)
if [ -n "$NOTIF_B_ID" ] && [ "$NOTIF_B_ID" != "null" ]; then
  R=$(http_patch "/api/v1/notifications/$NOTIF_B_ID/mark_as_read" "$TOKEN_A" '{}')
  check "Mark other user's notification → 404" "$R" 404 "$LOG_NOTIFICATIONS"
else
  skip "Cross-user notification test — B has no notifications"
fi

subsection "14.4 Unfriend nonexistent user → 404"
R=$(http_delete "/api/v1/networking/unfriend/99999999" "$TOKEN_A")
check "Unfriend nonexistent user → 404" "$R" 404 "$LOG_NETWORKING"

subsection "14.5 QR code nonexistent → 404"
R=$(http_get "/api/v1/delegates/99999999/qr_code" "$TOKEN_A")
check "QR code nonexistent → 404" "$R" 404 "$LOG_DELEGATES"


# =============================================================
# SECTION 15: USER JOURNEY — E2E FLOW
# =============================================================
section "15. END-TO-END USER JOURNEY"

echo "" >> "$LOG_MAIN"
echo "════ 15. E2E USER JOURNEY ════" >> "$LOG_MAIN"

subsection "15.1 Full connection flow: A→B→unfriend→reconnect"

echo "  Step 1: Cleanup" | tee -a "$LOG_REQUESTS"
cleanup_connection

echo "  Step 2: A sends request" | tee -a "$LOG_REQUESTS"
R=$(http_post "/api/v1/requests" "$TOKEN_A" "{\"target_id\":$B_ID}")
E2E_REQ_ID=$(extract_body "$R" | jq -r '.id // empty')
[ -n "$E2E_REQ_ID" ] && [ "$E2E_REQ_ID" != "null" ] && \
  pass "E2E: A sends friend request (id=$E2E_REQ_ID)" || \
  fail "E2E: A send request failed"

echo "  Step 3: B accepts" | tee -a "$LOG_REQUESTS"
if [ -n "$E2E_REQ_ID" ] && [ "$E2E_REQ_ID" != "null" ]; then
  R=$(http_patch "/api/v1/requests/$E2E_REQ_ID/accept" "$TOKEN_B" '{}')
  [ "$(extract_code "$R")" -eq 200 ] && pass "E2E: B accepts" || fail "E2E: B accept failed"
fi

echo "  Step 4: A sends message" | tee -a "$LOG_MESSAGES"
R=$(http_post "/api/v1/messages" "$TOKEN_A" \
  "{\"message\":{\"recipient_id\":$B_ID,\"content\":\"E2E test message\"}}")
E2E_MSG_ID=$(extract_body "$R" | jq -r '.id // empty')
[ "$(extract_code "$R")" -eq 201 ] && pass "E2E: A sends message" || fail "E2E: A message send failed"

echo "  Step 5: B replies" | tee -a "$LOG_MESSAGES"
R=$(http_post "/api/v1/messages" "$TOKEN_B" \
  "{\"message\":{\"recipient_id\":$A_ID,\"content\":\"E2E reply from B\"}}")
[ "$(extract_code "$R")" -eq 201 ] && pass "E2E: B replies" || fail "E2E: B reply failed"

echo "  Step 6: A reads conversation" | tee -a "$LOG_MESSAGES"
R=$(http_get "/api/v1/messages/conversation/$B_ID" "$TOKEN_A")
[ "$(extract_code "$R")" -eq 200 ] && pass "E2E: A reads conversation" || fail "E2E: conversation read failed"

echo "  Step 7: A checks dashboard" | tee -a "$LOG_DASHBOARD"
R=$(http_get "/api/v1/dashboard" "$TOKEN_A")
[ "$(extract_code "$R")" -eq 200 ] && pass "E2E: A checks dashboard" || fail "E2E: dashboard failed"

echo "  Step 8: A checks notifications" | tee -a "$LOG_NOTIFICATIONS"
R=$(http_get "/api/v1/notifications" "$TOKEN_A")
[ "$(extract_code "$R")" -eq 200 ] && pass "E2E: A checks notifications" || fail "E2E: notifications failed"

echo "  Step 9: A unfriends B" | tee -a "$LOG_REQUESTS"
R=$(http_delete "/api/v1/networking/unfriend/$B_ID" "$TOKEN_A")
[ "$(extract_code "$R")" -eq 200 ] && pass "E2E: A unfriends B" || fail "E2E: unfriend failed"

echo "  Step 10: Verify no longer friends" | tee -a "$LOG_REQUESTS"
R=$(http_get "/api/v1/networking/my_connections" "$TOKEN_A")
IS_STILL=$(extract_body "$R" | jq --argjson bid "$B_ID" \
  '[.[] | select((.requester.id == $bid) or (.target.id == $bid))] | length' 2>/dev/null)
[ "${IS_STILL:-1}" -eq 0 ] && pass "E2E: Confirmed unfriended" || fail "E2E: Still showing as friends"


# =============================================================
# FINAL SUMMARY
# =============================================================
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
TOTAL=$((PASS + FAIL + SKIP))

echo ""
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║              TEST SUMMARY                ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  Total Tests : ${BOLD}$TOTAL${NC}"
echo -e "  ${GREEN}Passed      : $PASS${NC}"
echo -e "  ${RED}Failed      : $FAIL${NC}"
echo -e "  ${YELLOW}Skipped     : $SKIP${NC}"
echo -e "  Time elapsed: ${ELAPSED}s"
echo ""
echo -e "  Logs saved to: ${BOLD}$LOG_DIR/${NC}"
echo ""

# Write summary to file
{
  echo ""
  echo "============================================"
  echo "FINAL RESULTS"
  echo "============================================"
  echo "Total   : $TOTAL"
  echo "Passed  : $PASS"
  echo "Failed  : $FAIL"
  echo "Skipped : $SKIP"
  echo "Time    : ${ELAPSED}s"
  echo "Finished: $(date)"
  echo ""
  if [ "$FAIL" -gt 0 ]; then
    echo "FAILURES:"
    grep "^  FAIL:" "$LOG_MAIN"
  fi
} >> "$LOG_MAIN"

if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}  🔥 ALL TESTS PASSED 🔥${NC}"
  echo "ALL TESTS PASSED" >> "$LOG_MAIN"
else
  echo -e "${RED}${BOLD}  ⚠  $FAIL TEST(S) FAILED — check $LOG_DIR/99_errors.txt${NC}"
fi
echo ""

exit $FAIL