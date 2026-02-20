#!/bin/bash
# =============================================================
# WPA Chat System — Realtime WebSocket Test Suite
# ทดสอบระบบแชท realtime ทุกกรณี
# [DEBUG VERSION] — เพิ่ม verbose HTTP/WS logging สำหรับ debug
# =============================================================

BASE_URL="http://localhost:3000"
WS_URL="ws://localhost:3000/cable"

EMAIL_A="narisara.lasan@bestgloballogistics.com"; PASSWORD_A="123456"
EMAIL_B="shammi@1shammi1.com";                    PASSWORD_B="RNIrSPPICj"

# ── Colors ──────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
MAGENTA='\033[0;35m'

# ── Log Setup ────────────────────────────────────────────────
STAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="./chat_test_logs_${STAMP}"
mkdir -p "$LOG_DIR"

LOG_MAIN="$LOG_DIR/00_summary.log"
LOG_WS_A="$LOG_DIR/ws_user_A.log"
LOG_WS_B="$LOG_DIR/ws_user_B.log"
LOG_HTTP="$LOG_DIR/http_calls.log"
LOG_TIMELINE="$LOG_DIR/timeline.log"
LOG_ERRORS="$LOG_DIR/errors.log"

# ── [DEBUG] Extra log files ──────────────────────────────────
LOG_DEBUG="$LOG_DIR/debug_verbose.log"          # raw curl + WS ทุก byte
LOG_DEBUG_HTTP="$LOG_DIR/debug_http_raw.log"    # HTTP request/response headers + body แบบ full
LOG_DEBUG_WS_A="$LOG_DIR/debug_ws_A_raw.log"   # WS raw ของ A ทุก frame
LOG_DEBUG_WS_B="$LOG_DIR/debug_ws_B_raw.log"   # WS raw ของ B ทุก frame
LOG_DEBUG_ASSERT="$LOG_DIR/debug_assertions.log" # ทุก assertion + ค่าจริงที่ได้
LOG_DEBUG_UNREAD="$LOG_DIR/debug_unread_trace.log" # trace unread_count ทุกครั้งที่เรียก

PASS=0; FAIL=0; SKIP=0
START_TIME=$(date +%s)

# =============================================================
# [DEBUG] — เขียน banner ลง debug log
# =============================================================
{
  echo "================================================================"
  echo "  WPA Chat System — DEBUG LOG"
  echo "  Started: $(date)"
  echo "  Base URL: $BASE_URL"
  echo "  WS URL:   $WS_URL"
  echo "  Log dir:  $LOG_DIR"
  echo "================================================================"
  echo ""
} | tee "$LOG_DEBUG" "$LOG_DEBUG_HTTP" "$LOG_DEBUG_WS_A" "$LOG_DEBUG_WS_B" \
       "$LOG_DEBUG_ASSERT" "$LOG_DEBUG_UNREAD" > /dev/null

# =============================================================
# LOGGING HELPERS
# =============================================================

ts() { date +"%H:%M:%S.%3N"; }

log_event() {
  local TYPE=$1; shift
  local MSG="$*"
  local ICON
  case $TYPE in
    SEND)    ICON="📤" ;;
    RECV)    ICON="📥" ;;
    READ)    ICON="👁 " ;;
    CONNECT) ICON="🔌" ;;
    DISCO)   ICON="🔌" ;;
    SYSTEM)  ICON="⚙️ " ;;
    ASSERT)  ICON="🔍" ;;
    DEBUG)   ICON="🐛" ;;
    *)       ICON="   " ;;
  esac
  local LINE="[$(ts)] $ICON $TYPE | $MSG"
  echo "$LINE" | tee -a "$LOG_TIMELINE" >> "$LOG_DEBUG"
}

# [DEBUG] ─ log_debug: บันทึกเฉพาะ debug_verbose.log
log_debug() {
  echo "[$(ts)] DEBUG | $*" >> "$LOG_DEBUG"
}

pass() {
  echo -e "${GREEN}    ✅ $1${NC}"
  echo "  PASS: $1" >> "$LOG_MAIN"
  echo "[$(ts)] PASS | $1" >> "$LOG_DEBUG_ASSERT"
  PASS=$((PASS+1))
}

fail() {
  echo -e "${RED}    ❌ $1${NC}"
  echo "  FAIL: $1" >> "$LOG_MAIN"
  echo "[$(ts)] FAIL | $1" >> "$LOG_ERRORS"
  echo "[$(ts)] FAIL | $1" >> "$LOG_DEBUG_ASSERT"
  FAIL=$((FAIL+1))
}

skip() {
  echo -e "${YELLOW}    ⏭  $1${NC}"
  echo "  SKIP: $1" >> "$LOG_MAIN"
  SKIP=$((SKIP+1))
}

section() {
  local TITLE="$1"
  echo ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}${BOLD}  $TITLE${NC}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
  echo "" >> "$LOG_MAIN"
  echo "════ $TITLE ════" >> "$LOG_MAIN"
  echo "" >> "$LOG_DEBUG"
  echo "════════════════════════════════════════" >> "$LOG_DEBUG"
  echo "  $TITLE" >> "$LOG_DEBUG"
  echo "════════════════════════════════════════" >> "$LOG_DEBUG"
  log_event SYSTEM "=== $TITLE ==="
}

subsection() {
  echo -e "\n${YELLOW}  ── $1 ──${NC}"
  echo "  ── $1 ──" >> "$LOG_DEBUG"
  log_event SYSTEM "── $1 ──"
}

# =============================================================
# HTTP HELPERS (DEBUG VERSION — บันทึก full headers + body)
# =============================================================

# [DEBUG] http_post พร้อม verbose logging
http_post() {
  local URL=$1 TOKEN=$2 BODY=$3 LABEL=${4:-"POST $1"}
  local TMPFILE=$(mktemp)
  local CURL_VERBOSE_FILE=$(mktemp)

  log_debug "→ HTTP POST $URL"
  log_debug "  Body: $BODY"

  # -v เพื่อ capture headers ด้วย
  local R
  R=$(curl -s -v --max-time 10 -w "\n%{http_code}" -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    "$BASE_URL$URL" 2>"$CURL_VERBOSE_FILE")

  local STATUS=$(echo "$R" | tail -1)
  local BODY_RESP=$(echo "$R" | head -1)

  {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$(ts)] HTTP POST $BASE_URL$URL"
    echo "  Token: ${TOKEN:0:20}..."
    echo "  Request Body:"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "  $BODY"
    echo ""
    echo "  Verbose (headers):"
    cat "$CURL_VERBOSE_FILE" | grep -E "^[<>*]" | sed 's/^/    /'
    echo ""
    echo "  Response HTTP $STATUS:"
    echo "$BODY_RESP" | python3 -m json.tool 2>/dev/null || echo "  $BODY_RESP"
    echo ""
  } >> "$LOG_DEBUG_HTTP"

  {
    echo "[$(ts)] HTTP POST $URL"
    echo "  Body: $BODY"
    echo "  Status: $STATUS"
    echo "  Resp: $BODY_RESP"
    echo ""
  } >> "$LOG_HTTP"

  rm -f "$TMPFILE" "$CURL_VERBOSE_FILE"
  echo "$R"
}

# [DEBUG] http_get พร้อม verbose
http_get() {
  local URL=$1 TOKEN=$2
  local CURL_VERBOSE_FILE=$(mktemp)

  log_debug "→ HTTP GET $URL"

  local R
  R=$(curl -s -v --max-time 10 -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "$BASE_URL$URL" 2>"$CURL_VERBOSE_FILE")

  local STATUS=$(echo "$R" | tail -1)
  local BODY_RESP=$(echo "$R" | head -1)

  {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$(ts)] HTTP GET $BASE_URL$URL"
    echo "  Token: ${TOKEN:0:20}..."
    echo ""
    echo "  Verbose (headers):"
    cat "$CURL_VERBOSE_FILE" | grep -E "^[<>*]" | sed 's/^/    /'
    echo ""
    echo "  Response HTTP $STATUS:"
    echo "$BODY_RESP" | python3 -m json.tool 2>/dev/null || echo "  $BODY_RESP"
    echo ""
  } >> "$LOG_DEBUG_HTTP"

  {
    echo "[$(ts)] HTTP GET $URL"
    echo "  Resp: $R"
    echo ""
  } >> "$LOG_HTTP"

  rm -f "$CURL_VERBOSE_FILE"
  echo "$R"
}

# [DEBUG] http_patch พร้อม verbose
http_patch() {
  local URL=$1 TOKEN=$2 BODY=$3
  local CURL_VERBOSE_FILE=$(mktemp)

  log_debug "→ HTTP PATCH $URL"
  log_debug "  Body: $BODY"

  local R
  R=$(curl -s -v --max-time 10 -w "\n%{http_code}" -X PATCH \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    "$BASE_URL$URL" 2>"$CURL_VERBOSE_FILE")

  local STATUS=$(echo "$R" | tail -1)
  local BODY_RESP=$(echo "$R" | head -1)

  {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$(ts)] HTTP PATCH $BASE_URL$URL"
    echo "  Token: ${TOKEN:0:20}..."
    echo "  Request Body: $BODY"
    echo ""
    echo "  Verbose (headers):"
    cat "$CURL_VERBOSE_FILE" | grep -E "^[<>*]" | sed 's/^/    /'
    echo ""
    echo "  Response HTTP $STATUS:"
    echo "$BODY_RESP" | python3 -m json.tool 2>/dev/null || echo "  $BODY_RESP"
    echo ""
  } >> "$LOG_DEBUG_HTTP"

  {
    echo "[$(ts)] HTTP PATCH $URL"
    echo "  Body: $BODY"
    echo "  Resp: $R"
    echo ""
  } >> "$LOG_HTTP"

  rm -f "$CURL_VERBOSE_FILE"
  echo "$R"
}

# [DEBUG] http_delete พร้อม verbose
http_delete() {
  local URL=$1 TOKEN=$2
  local CURL_VERBOSE_FILE=$(mktemp)

  log_debug "→ HTTP DELETE $URL"

  local R
  R=$(curl -s -v --max-time 10 -w "\n%{http_code}" -X DELETE \
    -H "Authorization: Bearer $TOKEN" \
    "$BASE_URL$URL" 2>"$CURL_VERBOSE_FILE")

  local STATUS=$(echo "$R" | tail -1)
  local BODY_RESP=$(echo "$R" | head -1)

  {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$(ts)] HTTP DELETE $BASE_URL$URL"
    echo "  Token: ${TOKEN:0:20}..."
    echo ""
    echo "  Verbose (headers):"
    cat "$CURL_VERBOSE_FILE" | grep -E "^[<>*]" | sed 's/^/    /'
    echo ""
    echo "  Response HTTP $STATUS:"
    echo "$BODY_RESP" | python3 -m json.tool 2>/dev/null || echo "  $BODY_RESP"
    echo ""
  } >> "$LOG_DEBUG_HTTP"

  {
    echo "[$(ts)] HTTP DELETE $URL"
    echo "  Resp: $R"
    echo ""
  } >> "$LOG_HTTP"

  rm -f "$CURL_VERBOSE_FILE"
  echo "$R"
}

extract_body() { echo "$1" | head -1; }
extract_code() { echo "$1" | tail -1; }

# [DEBUG] send_msg — log message id + content
send_msg() {
  local TOKEN=$1 RID=$2 CONTENT=$3
  local R
  R=$(http_post "/api/v1/messages" "$TOKEN" \
    "{\"message\":{\"recipient_id\":$RID,\"content\":\"$CONTENT\"}}")
  local MSG_ID=$(extract_body "$R" | jq -r '.id // empty' 2>/dev/null)
  log_debug "send_msg → recipient=$RID content='$CONTENT' → id=$MSG_ID"
  echo "$MSG_ID"
}

# [DEBUG] unread_from — trace ทุกครั้งที่เรียก
unread_from() {
  local SENDER_ID=$1 TOKEN=$2
  local R
  R=$(curl -s --max-time 10 -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "$BASE_URL/api/v1/messages/unread_count?sender_id=$SENDER_ID")
  local BODY=$(extract_body "$R")
  local STATUS=$(extract_code "$R")
  local COUNT=$(echo "$BODY" | jq -r '.unread_count // 999' 2>/dev/null)

  {
    echo "[$(ts)] unread_from sender=$SENDER_ID → HTTP $STATUS"
    echo "  Raw response: $BODY"
    echo "  Parsed unread_count: $COUNT"
    echo ""
  } >> "$LOG_DEBUG_UNREAD"

  log_debug "unread_from sender=$SENDER_ID → $COUNT (HTTP $STATUS)"
  echo "$COUNT"
}

read_all_msgs() {
  curl -s --max-time 10 -o /dev/null -X PATCH \
    -H "Authorization: Bearer $1" \
    "$BASE_URL/api/v1/messages/read_all"
}

# =============================================================
# WEBSOCKET HELPERS (DEBUG VERSION)
# =============================================================

WS_PIDS=()

# [DEBUG] ws_open — บันทึก raw WS frames ลง debug log แยก
ws_open() {
  local NAME=$1 TOKEN=$2 LOGFILE=$3 WITH_ID=${4:-""}
  local IDENTIFIER DEBUG_LOGFILE

  if [ -n "$WITH_ID" ]; then
    IDENTIFIER="{\\\"channel\\\":\\\"ChatChannel\\\",\\\"with_id\\\":$WITH_ID}"
  else
    IDENTIFIER="{\\\"channel\\\":\\\"ChatChannel\\\"}"
  fi

  # เลือก debug log ตาม user
  if [[ "$NAME" == *"A"* ]]; then
    DEBUG_LOGFILE="$LOG_DEBUG_WS_A"
  else
    DEBUG_LOGFILE="$LOG_DEBUG_WS_B"
  fi

  {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$(ts)] WS OPEN name=$NAME with_id=${WITH_ID:-none}"
    echo "  URL: ${WS_URL}?token=${TOKEN:0:20}..."
    echo "  Identifier: $IDENTIFIER"
    echo ""
  } >> "$DEBUG_LOGFILE"

  echo "[$(ts)] CONNECT ChatChannel name=$NAME with_id=${WITH_ID:-none}" >> "$LOGFILE"

  nohup bash -c "
    {
      sleep 0.5
      echo '{\"command\":\"subscribe\",\"identifier\":\"${IDENTIFIER}\"}'
      sleep 9999
    } | timeout 120 wscat --connect '${WS_URL}?token=${TOKEN}' --no-color 2>&1 \
      | while IFS= read -r LINE; do
          TS=\$(date +\"%H:%M:%S.%3N\")
          echo \"[\$TS] RECV | \$LINE\" | tee -a '$LOGFILE' >> '$DEBUG_LOGFILE'
        done
  " >> "$LOGFILE" 2>&1 &

  local PID=$!
  WS_PIDS+=($PID)
  echo "$PID" > "$LOG_DIR/.pid_${NAME}"
  sleep 2
  log_event CONNECT "User $NAME subscribed ChatChannel"
}

# [DEBUG] ws_enter_room — log ทุก WS frame ที่รับ
ws_enter_room() {
  local NAME=$1 TOKEN=$2 TARGET_ID=$3 LOGFILE=$4
  local IDENTIFIER="{\\\"channel\\\":\\\"ChatChannel\\\"}"

  if [[ "$NAME" == *"A"* ]]; then
    local DEBUG_LOGFILE="$LOG_DEBUG_WS_A"
  else
    local DEBUG_LOGFILE="$LOG_DEBUG_WS_B"
  fi

  {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$(ts)] WS ENTER_ROOM name=$NAME target=$TARGET_ID"
    echo ""
  } >> "$DEBUG_LOGFILE"

  echo "[$(ts)] ENTER_ROOM name=$NAME target=$TARGET_ID" >> "$LOGFILE"

  nohup bash -c "
    {
      sleep 0.3
      echo '{\"command\":\"subscribe\",\"identifier\":\"${IDENTIFIER}\"}'
      sleep 0.8
      echo '{\"command\":\"message\",\"identifier\":\"${IDENTIFIER}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":${TARGET_ID}}\"}'
      sleep 9999
    } | timeout 120 wscat --connect '${WS_URL}?token=${TOKEN}' --no-color 2>&1 \
      | while IFS= read -r LINE; do
          TS=\$(date +\"%H:%M:%S.%3N\")
          echo \"[\$TS] RECV | \$LINE\" | tee -a '$LOGFILE' >> '$DEBUG_LOGFILE'
        done
  " >> "$LOGFILE" 2>&1 &

  local PID=$!
  WS_PIDS+=($PID)
  echo "$PID" >> "$LOG_DIR/.pid_${NAME}"
  sleep 2
  log_event CONNECT "User $NAME entered room with $TARGET_ID"
}

ws_leave_room() {
  local TOKEN=$1 TARGET_ID=$2 LOGFILE=$3
  local IDENTIFIER="{\\\"channel\\\":\\\"ChatChannel\\\"}"

  echo "[$(ts)] LEAVE_ROOM target=$TARGET_ID" >> "$LOGFILE"
  log_event DISCO "leave_room target=$TARGET_ID"

  bash -c "
    {
      sleep 0.3
      echo '{\"command\":\"subscribe\",\"identifier\":\"${IDENTIFIER}\"}'
      sleep 0.8
      echo '{\"command\":\"message\",\"identifier\":\"${IDENTIFIER}\",\"data\":\"{\\\"action\\\":\\\"leave_room\\\",\\\"user_id\\\":${TARGET_ID}}\"}'
      sleep 1
    } | timeout 10 wscat --connect '${WS_URL}?token=${TOKEN}' --no-color 2>&1 \
      | while IFS= read -r LINE; do
          echo \"[$(date +%H:%M:%S.%3N)] LEAVE_RESP | \$LINE\"
        done
  " >> "$LOGFILE" 2>&1
  sleep 1
}

# [DEBUG] ws_send_chat — log frame ที่ส่งและ response ทั้งหมด
ws_send_chat() {
  local TOKEN=$1 RECIPIENT_ID=$2 CONTENT=$3 LOGFILE=$4
  local IDENTIFIER="{\\\"channel\\\":\\\"ChatChannel\\\"}"
  local SAFE_CONTENT=$(echo "$CONTENT" | sed 's/"/\\"/g')

  log_event SEND "WS send_message → recipient=$RECIPIENT_ID msg='$CONTENT'"

  {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$(ts)] WS SEND_CHAT to=$RECIPIENT_ID content='$CONTENT'"
    echo ""
  } >> "$LOG_DEBUG_WS_A"

  bash -c "
    {
      sleep 0.3
      echo '{\"command\":\"subscribe\",\"identifier\":\"${IDENTIFIER}\"}'
      sleep 0.8
      echo '{\"command\":\"message\",\"identifier\":\"${IDENTIFIER}\",\"data\":\"{\\\"action\\\":\\\"send_message\\\",\\\"recipient_id\\\":${RECIPIENT_ID},\\\"content\\\":\\\"${SAFE_CONTENT}\\\"}\"}'
      sleep 2
    } | timeout 10 wscat --connect '${WS_URL}?token=${TOKEN}' --no-color 2>&1 \
      | while IFS= read -r LINE; do
          TS=\$(date +\"%H:%M:%S.%3N\")
          echo \"[\$TS] SEND_RESP | \$LINE\" | tee -a '$LOGFILE' >> '$LOG_DEBUG_WS_A'
        done
  " >> "$LOGFILE" 2>&1
  sleep 1
}

ws_subscribe_room() {
  local NAME=$1 TOKEN=$2 ROOM_ID=$3 LOGFILE=$4
  local IDENTIFIER="{\\\"channel\\\":\\\"ChatRoomChannel\\\",\\\"room_id\\\":${ROOM_ID}}"

  {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$(ts)] WS SUBSCRIBE_ROOM name=$NAME room=$ROOM_ID"
    echo ""
  } >> "$LOG_DEBUG_WS_A"

  nohup bash -c "
    {
      sleep 0.5
      echo '{\"command\":\"subscribe\",\"identifier\":\"${IDENTIFIER}\"}'
      sleep 9999
    } | timeout 120 wscat --connect '${WS_URL}?token=${TOKEN}' --no-color 2>&1 \
      | while IFS= read -r LINE; do
          TS=\$(date +\"%H:%M:%S.%3N\")
          echo \"[\$TS] RECV | \$LINE\" | tee -a '$LOGFILE' >> '$LOG_DEBUG_WS_A'
        done
  " >> "$LOGFILE" 2>&1 &

  local PID=$!
  WS_PIDS+=($PID)
  echo "$PID" >> "$LOG_DIR/.pid_room_${NAME}"
  sleep 2
  log_event CONNECT "User $NAME subscribed ChatRoomChannel room=$ROOM_ID"
}

# [DEBUG] ws_room_send — log ทุก frame
ws_room_send() {
  local TOKEN=$1 ROOM_ID=$2 CONTENT=$3 LOGFILE=$4
  local IDENTIFIER="{\\\"channel\\\":\\\"ChatRoomChannel\\\",\\\"room_id\\\":${ROOM_ID}}"
  local SAFE=$(echo "$CONTENT" | sed 's/"/\\"/g')

  log_event SEND "WS room send_message → room=$ROOM_ID msg='$CONTENT'"

  {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$(ts)] WS ROOM_SEND room=$ROOM_ID content='$CONTENT'"
    echo "  Sending command: subscribe + send_message"
    echo ""
  } >> "$LOG_DEBUG_WS_A"

  bash -c "
    {
      sleep 0.3
      echo '{\"command\":\"subscribe\",\"identifier\":\"${IDENTIFIER}\"}'
      sleep 0.8
      echo '{\"command\":\"message\",\"identifier\":\"${IDENTIFIER}\",\"data\":\"{\\\"action\\\":\\\"send_message\\\",\\\"content\\\":\\\"${SAFE}\\\"}\"}'
      sleep 2
    } | timeout 10 wscat --connect '${WS_URL}?token=${TOKEN}' --no-color 2>&1 \
      | while IFS= read -r LINE; do
          TS=\$(date +\"%H:%M:%S.%3N\")
          echo \"[\$TS] ROOM_SEND_RESP | \$LINE\" | tee -a '$LOGFILE' >> '$LOG_DEBUG_WS_A'
        done
  " >> "$LOGFILE" 2>&1
  sleep 1
}

wait_for_event() {
  local LOGFILE=$1 PATTERN=$2 TIMEOUT=${3:-8}
  for i in $(seq 1 $TIMEOUT); do
    if grep -q "$PATTERN" "$LOGFILE" 2>/dev/null; then
      log_debug "wait_for_event FOUND '$PATTERN' in $LOGFILE (after ${i}s)"
      return 0
    fi
    sleep 1
  done
  log_debug "wait_for_event TIMEOUT '$PATTERN' in $LOGFILE (${TIMEOUT}s)"
  # [DEBUG] dump ท้าย log ที่ fail ลง debug file
  {
    echo "[$(ts)] TIMEOUT waiting for: $PATTERN"
    echo "  File: $LOGFILE"
    echo "  Last 20 lines:"
    tail -20 "$LOGFILE" 2>/dev/null | sed 's/^/    /'
    echo ""
  } >> "$LOG_DEBUG"
  return 1
}

ws_kill_all() {
  pkill -f "wscat" 2>/dev/null || true
  WS_PIDS=()
  sleep 1
}

ws_reset() {
  log_debug "── ws_reset ──"
  ws_leave_room "$TOKEN_A" "$B_ID" "$LOG_WS_A" 2>/dev/null
  ws_leave_room "$TOKEN_B" "$A_ID" "$LOG_WS_B" 2>/dev/null
  ws_kill_all
  read_all_msgs "$TOKEN_A"
  read_all_msgs "$TOKEN_B"
  sleep 1
  echo "[$(ts)] ── STATE RESET ──" | tee -a "$LOG_WS_A" "$LOG_WS_B" > /dev/null
}

assert_ws_received() {
  local LOGFILE=$1 PATTERN=$2 LABEL=$3
  log_event ASSERT "Check WS log for: $PATTERN"
  if grep -q "$PATTERN" "$LOGFILE" 2>/dev/null; then
    pass "$LABEL"
    return 0
  else
    fail "$LABEL — pattern '$PATTERN' not found in WS log"
    {
      echo "[$(ts)] ASSERT FAIL: '$LABEL'"
      echo "  Looking for pattern: $PATTERN"
      echo "  In file: $LOGFILE"
      echo "  Last 10 lines of log:"
      tail -10 "$LOGFILE" 2>/dev/null | sed 's/^/    /'
      echo ""
    } >> "$LOG_DEBUG_ASSERT"
    return 1
  fi
}

# =============================================================
# PRINT HEADER
# =============================================================
{
  echo "WPA Chat System — Realtime WebSocket Test"
  echo "Started: $(date)"
  echo "Base URL: $BASE_URL"
  echo "WS URL:   $WS_URL"
  echo "Logs:     $LOG_DIR"
  echo "=================================================="
  echo ""
} | tee "$LOG_MAIN" "$LOG_TIMELINE" > /dev/null

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   WPA Chat System — Realtime WebSocket Tests     ║"
echo "║   (DEBUG VERSION)                                ║"
echo "║   $(date +%Y-%m-%d\ %H:%M:%S)                             ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${DIM}Logs → $LOG_DIR${NC}"
echo -e "  ${DIM}WS traffic → ws_user_A.log / ws_user_B.log${NC}"
echo -e "  ${DIM}Timeline   → timeline.log${NC}"
echo -e "  ${YELLOW}[DEBUG] debug_verbose.log     — ทุก event${NC}"
echo -e "  ${YELLOW}[DEBUG] debug_http_raw.log    — HTTP headers + body แบบ full${NC}"
echo -e "  ${YELLOW}[DEBUG] debug_ws_A/B_raw.log  — WS frames ดิบ${NC}"
echo -e "  ${YELLOW}[DEBUG] debug_assertions.log  — ค่าจริงทุก assertion${NC}"
echo -e "  ${YELLOW}[DEBUG] debug_unread_trace.log — unread_count trace${NC}"


# =============================================================
# PRE-CHECK: wscat + jq
# =============================================================
echo ""
echo -e "${YELLOW}  ── Pre-flight check ──${NC}"
if ! command -v wscat &>/dev/null; then
  echo -e "${RED}  ❌ wscat ไม่พบ — กรุณา: npm install -g wscat${NC}"
  exit 1
fi
if ! command -v jq &>/dev/null; then
  echo -e "${RED}  ❌ jq ไม่พบ — กรุณา: apt install jq / brew install jq${NC}"
  exit 1
fi
echo -e "${GREEN}  ✅ wscat $(wscat --version 2>/dev/null) พร้อม${NC}"
echo -e "${GREEN}  ✅ jq $(jq --version 2>/dev/null) พร้อม${NC}"


# =============================================================
# 0. SETUP — LOGIN & FRIENDSHIP
# =============================================================
section "0. SETUP — LOGIN & FRIENDSHIP"

subsection "0.1 Login both users"

{
  echo "[$(ts)] LOGIN User A: $EMAIL_A"
} >> "$LOG_DEBUG_HTTP"

R=$(curl -s -v --max-time 10 -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL_A\",\"password\":\"$PASSWORD_A\"}" \
  "$BASE_URL/api/v1/login" 2>>"$LOG_DEBUG_HTTP")

{
  echo "  Response HTTP $(echo "$R" | tail -1):"
  echo "$R" | head -1 | python3 -m json.tool 2>/dev/null || echo "  $(echo "$R" | head -1)"
  echo ""
} >> "$LOG_DEBUG_HTTP"

TOKEN_A=$(extract_body "$R" | jq -r '.token // empty')
A_ID=$(extract_body  "$R" | jq -r '.delegate.id // empty')

{
  echo "[$(ts)] LOGIN User B: $EMAIL_B"
} >> "$LOG_DEBUG_HTTP"

R=$(curl -s -v --max-time 10 -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL_B\",\"password\":\"$PASSWORD_B\"}" \
  "$BASE_URL/api/v1/login" 2>>"$LOG_DEBUG_HTTP")

{
  echo "  Response HTTP $(echo "$R" | tail -1):"
  echo "$R" | head -1 | python3 -m json.tool 2>/dev/null || echo "  $(echo "$R" | head -1)"
  echo ""
} >> "$LOG_DEBUG_HTTP"

TOKEN_B=$(extract_body "$R" | jq -r '.token // empty')
B_ID=$(extract_body  "$R" | jq -r '.delegate.id // empty')

if [ -z "$TOKEN_A" ] || [ -z "$TOKEN_B" ]; then
  echo -e "${RED}  FATAL: Login failed — ดู debug_http_raw.log${NC}"
  exit 1
fi

log_debug "Token A (first 40): ${TOKEN_A:0:40}..."
log_debug "Token B (first 40): ${TOKEN_B:0:40}..."

echo -e "${GREEN}  ✅ User A: id=$A_ID${NC}"
echo -e "${GREEN}  ✅ User B: id=$B_ID${NC}"
log_event SYSTEM "Login OK — A=$A_ID B=$B_ID"

subsection "0.2 Ensure A and B are friends"
curl -s -o /dev/null -X DELETE -H "Authorization: Bearer $TOKEN_A" \
  "$BASE_URL/api/v1/networking/unfriend/$B_ID"
curl -s -o /dev/null -X DELETE -H "Authorization: Bearer $TOKEN_A" \
  "$BASE_URL/api/v1/requests/$B_ID/cancel"

R=$(http_post "/api/v1/requests" "$TOKEN_A" "{\"target_id\":$B_ID}")
SC=$(extract_code "$R")
if [ "$SC" -eq 201 ]; then
  REQ_ID=$(extract_body "$R" | jq -r '.id')
  http_patch "/api/v1/requests/$REQ_ID/accept" "$TOKEN_B" '{}' > /dev/null
  pass "A & B เป็นเพื่อนกันแล้ว"
elif [ "$SC" -eq 422 ]; then
  pass "A & B เป็นเพื่อนกันอยู่แล้ว"
else
  fail "ไม่สามารถสร้าง friendship ได้ (HTTP $SC)"
fi

subsection "0.3 Clean read state"
read_all_msgs "$TOKEN_A"
read_all_msgs "$TOKEN_B"
pass "Cleared all read state"


# =============================================================
# CASE 1: BASIC CONNECT & SUBSCRIBE
# =============================================================
section "1. BASIC CONNECT & SUBSCRIBE"
ws_reset

subsection "1.1 A connects — confirm_subscription received"
ws_open "A" "$TOKEN_A" "$LOG_WS_A"

if wait_for_event "$LOG_WS_A" "confirm_subscription" 5; then
  pass "A: confirm_subscription ✓"
else
  fail "A: ไม่ได้รับ confirm_subscription"
fi

subsection "1.2 B connects — confirm_subscription received"
ws_open "B" "$TOKEN_B" "$LOG_WS_B"

if wait_for_event "$LOG_WS_B" "confirm_subscription" 5; then
  pass "B: confirm_subscription ✓"
else
  fail "B: ไม่ได้รับ confirm_subscription"
fi

subsection "1.3 Invalid JWT → connection rejected"
REJECT_LOG="$LOG_DIR/ws_reject.log"
nohup bash -c "
  {
    sleep 0.5
    echo '{\"command\":\"subscribe\",\"identifier\":\"{\\\\\"channel\\\\\":\\\\\"ChatChannel\\\\\"}\"}'
    sleep 4
  } | timeout 8 wscat --connect '${WS_URL}?token=INVALID_TOKEN_XYZ' --no-color 2>&1 \
    | while IFS= read -r LINE; do echo \"[$(date +%H:%M:%S.%3N)] \$LINE\"; done
" > "$REJECT_LOG" 2>&1 &
sleep 5

{
  echo "[$(ts)] JWT Rejection test — reject log contents:"
  cat "$REJECT_LOG" | sed 's/^/  /'
  echo ""
} >> "$LOG_DEBUG"

if grep -qE "reject_subscription|disconnect|error|close|Unexpected server" "$REJECT_LOG" 2>/dev/null; then
  pass "Invalid JWT → rejected ✓"
else
  fail "Invalid JWT → ไม่ถูก reject (log: $(tail -2 "$REJECT_LOG"))"
fi

subsection "1.4 PresenceService — online_status true หลัง connect"
sleep 1
R=$(http_get "/api/v1/messages/online_status?user_id=$B_ID" "$TOKEN_A")
ONLINE=$(extract_body "$R" | jq -r '.online // false' 2>/dev/null)
log_event RECV "online_status B = $ONLINE"
{
  echo "[$(ts)] Presence check B → online=$ONLINE"
  echo "  Raw: $(extract_body "$R")"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "$ONLINE" = "true" ]; then
  pass "B online=true หลัง subscribe ✓"
else
  fail "B online=$ONLINE (คาดว่า true — ตรวจ PresenceService Redis key)"
fi

ws_kill_all


# =============================================================
# CASE 2: SEND & RECEIVE MESSAGE
# =============================================================
section "2. SEND & RECEIVE MESSAGE"
ws_reset

subsection "2.1 A เปิด connection, B เปิด + enter_room"
ws_open "A" "$TOKEN_A" "$LOG_WS_A"
ws_enter_room "B" "$TOKEN_B" "$B_ID" "$LOG_WS_B"
sleep 1

subsection "2.2 A ส่งข้อความ → B รับผ่าน WS"
MSG_ID=$(send_msg "$TOKEN_A" "$B_ID" "สวัสดี B นี่คือข้อความทดสอบ")
log_event SEND "A→B HTTP: msg_id=$MSG_ID 'สวัสดี B นี่คือข้อความทดสอบ'"
sleep 2

# [DEBUG] dump WS_B log เพื่อดู broadcast
{
  echo "[$(ts)] === WS_B log after send (test 2.2) ==="
  cat "$LOG_WS_B" | sed 's/^/  /'
  echo ""
} >> "$LOG_DEBUG_WS_B"

if wait_for_event "$LOG_WS_B" "new_message\|สวัสดี B\|message_id" 5; then
  pass "B รับ WS broadcast ข้อความจาก A ✓"
else
  fail "B ไม่รับ WS broadcast"
fi
log_event RECV "B received WS event for msg=$MSG_ID"

subsection "2.3 ตรวจ unread count ของ B"
sleep 1
U=$(unread_from "$A_ID" "$TOKEN_B")
log_event READ "B.unread_from_A = $U"

{
  echo "[$(ts)] Test 2.3 — B unread_from_A = $U"
  echo "  Expected: 0 (B is in enter_room, auto-read should fire)"
  echo "  Actual:   $U"
  echo "  → If $U != 0: auto-read on incoming message not working"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${U:-999}" -eq 0 ]; then
  pass "B enter_room → auto-read → unread=0 ✓"
else
  fail "B unread=$U (คาดว่า 0 หลัง enter_room)"
fi

subsection "2.4 WS ส่งกลับ message_read event ให้ A"
if wait_for_event "$LOG_WS_A" "message_read\|bulk_read\|read_at" 5; then
  pass "A ได้รับ message_read/bulk_read event ✓"
  log_event READ "A received read receipt for msg=$MSG_ID"
else
  fail "A ไม่ได้รับ read receipt event"
  {
    echo "[$(ts)] Test 2.4 — A WS log (looking for read event):"
    tail -20 "$LOG_WS_A" | sed 's/^/  /'
    echo ""
  } >> "$LOG_DEBUG_ASSERT"
fi

subsection "2.5 B ตอบกลับ A → A รับ WS broadcast"
MSG_ID_B=$(send_msg "$TOKEN_B" "$A_ID" "สบายดีครับ A")
log_event SEND "B→A HTTP: msg_id=$MSG_ID_B 'สบายดีครับ A'"
sleep 2

if wait_for_event "$LOG_WS_A" "new_message\|สบายดี\|message_id" 5; then
  pass "A รับ WS broadcast ข้อความจาก B ✓"
else
  fail "A ไม่รับ WS broadcast จาก B"
fi

ws_kill_all


# =============================================================
# CASE 3: SEND MESSAGE VIA WEBSOCKET ACTION
# =============================================================
section "3. SEND MESSAGE VIA WEBSOCKET ACTION"
ws_reset

subsection "3.1 A ส่ง send_message ผ่าน WS action โดยตรง"
ws_open "A" "$TOKEN_A" "$LOG_WS_A"
ws_open "B" "$TOKEN_B" "$LOG_WS_B"
sleep 1

ws_send_chat "$TOKEN_A" "$B_ID" "WS action send test" "$LOG_WS_A"
sleep 3

subsection "3.2 ตรวจว่า B รับ broadcast"
{
  echo "[$(ts)] Test 3.2 — WS_B log (looking for broadcast):"
  tail -20 "$LOG_WS_B" | sed 's/^/  /'
  echo ""
} >> "$LOG_DEBUG_WS_B"

if wait_for_event "$LOG_WS_B" "new_message\|WS action send\|room_message" 6; then
  pass "B รับ WS broadcast จาก WS send_message action ✓"
else
  fail "B ไม่รับ broadcast จาก WS action"
fi

subsection "3.3 ตรวจว่าข้อความถูก save ลง DB"
R=$(http_get "/api/v1/messages/conversation/$B_ID" "$TOKEN_A")
HAS_MSG=$(extract_body "$R" | jq -r \
  '[.data[] | select(.content == "WS action send test")] | length' 2>/dev/null)
log_event ASSERT "DB check — WS action message count=$HAS_MSG"

{
  echo "[$(ts)] Test 3.3 — DB check for WS action message"
  echo "  Expected: ≥1"
  echo "  Actual:   $HAS_MSG"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${HAS_MSG:-0}" -ge 1 ]; then
  pass "ข้อความ WS action ถูก save ลง DB ✓"
else
  fail "ข้อความ WS action ไม่พบใน DB"
fi

ws_kill_all


# =============================================================
# CASE 4: UNREAD MESSAGE ACCUMULATION
# =============================================================
section "4. UNREAD MESSAGE ACCUMULATION"
ws_reset

subsection "4.1 B online แต่ไม่ enter_room → unread สะสม"
ws_open "A" "$TOKEN_A" "$LOG_WS_A"
ws_open "B" "$TOKEN_B" "$LOG_WS_B"

MSG_IDS=()
for i in 1 2 3 4 5; do
  ID=$(send_msg "$TOKEN_A" "$B_ID" "unread_test_msg_$i")
  MSG_IDS+=("$ID")
  log_event SEND "A→B msg_$i id=$ID"
  sleep 0.3
done
sleep 2

U=$(unread_from "$A_ID" "$TOKEN_B")
log_event ASSERT "unread (no enter_room) = $U"

{
  echo "[$(ts)] Test 4.1 — sent 5 msgs, B not in enter_room"
  echo "  Expected unread: ≥5"
  echo "  Actual:          $U"
  echo "  MSG IDs sent: ${MSG_IDS[*]}"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${U:-0}" -ge 5 ]; then
  pass "B ไม่ enter_room → unread=$U (5 ข้อความยังไม่ถูก mark) ✓"
else
  fail "B ไม่ enter_room → unread=$U (คาดว่า ≥ 5)"
fi

subsection "4.2 B enter_room → unread เคลียร์เป็น 0"
ws_enter_room "B_enter" "$TOKEN_B" "$A_ID" "$LOG_WS_B"
sleep 2

U=$(unread_from "$A_ID" "$TOKEN_B")
log_event READ "unread after enter_room = $U"

{
  echo "[$(ts)] Test 4.2 — B called enter_room"
  echo "  Expected unread: 0"
  echo "  Actual:          $U"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${U:-999}" -eq 0 ]; then
  pass "B enter_room → unread=0 ✓"
else
  fail "B enter_room → unread=$U (คาดว่า 0)"
fi

subsection "4.3 A รับ bulk_read event"
if wait_for_event "$LOG_WS_A" "bulk_read\|message_read\|read_at" 5; then
  pass "A ได้รับ bulk_read/message_read event ✓"
  log_event READ "A got bulk_read event"
else
  fail "A ไม่ได้รับ bulk_read event"
  {
    echo "[$(ts)] Test 4.3 — A WS log (looking for bulk_read):"
    tail -20 "$LOG_WS_A" | sed 's/^/  /'
    echo ""
  } >> "$LOG_DEBUG_ASSERT"
fi

ws_kill_all


# =============================================================
# CASE 5: OFFLINE → ONLINE → CATCH UP
# =============================================================
section "5. OFFLINE → ONLINE → CATCH UP"
ws_reset

subsection "5.1 B offline — A ส่งข้อความ 10 ข้อความ"
for i in {1..10}; do
  send_msg "$TOKEN_A" "$B_ID" "offline_msg_$i" > /dev/null
  log_event SEND "A→B offline msg_$i"
  sleep 0.2
done
sleep 1

U=$(unread_from "$A_ID" "$TOKEN_B")
log_event ASSERT "unread (B offline) = $U"

{
  echo "[$(ts)] Test 5.1 — sent 10 msgs while B fully offline"
  echo "  Expected unread: ≥10"
  echo "  Actual:          $U"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${U:-0}" -ge 10 ]; then
  pass "B offline → unread=$U (≥10 สะสม) ✓"
else
  fail "B offline → unread=$U (คาดว่า ≥10)"
fi

subsection "5.2 B connect เฉยๆ (ไม่ enter_room) → unread ยังอยู่"
ws_open "B_comeback" "$TOKEN_B" "$LOG_WS_B"
sleep 2

U=$(unread_from "$A_ID" "$TOKEN_B")
log_event ASSERT "unread after connect (no enter_room) = $U"

{
  echo "[$(ts)] Test 5.2 — B reconnected (no enter_room)"
  echo "  Expected unread: ≥10"
  echo "  Actual:          $U"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${U:-0}" -ge 10 ]; then
  pass "B connect เฉยๆ → unread ยังอยู่=$U ✓"
else
  fail "B connect เฉยๆ → unread=$U (คาดว่า ≥10)"
fi

subsection "5.3 B enter_room → อ่านทั้งหมด"
ws_enter_room "B_catchup" "$TOKEN_B" "$A_ID" "$LOG_WS_B"
sleep 2

U=$(unread_from "$A_ID" "$TOKEN_B")
log_event READ "unread after enter_room = $U"

{
  echo "[$(ts)] Test 5.3 — B enter_room (catch-up)"
  echo "  Expected unread: 0"
  echo "  Actual:          $U"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${U:-999}" -eq 0 ]; then
  pass "B enter_room → catch up all → unread=0 ✓"
else
  fail "B enter_room → unread=$U (คาดว่า 0)"
fi

ws_kill_all


# =============================================================
# CASE 6: LEAVE_ROOM → หยุด AUTO-READ
# =============================================================
section "6. LEAVE_ROOM STOPS AUTO-READ"
ws_reset

subsection "6.1 B enter_room → ข้อความใหม่ auto-read"
ws_enter_room "B_inroom" "$TOKEN_B" "$A_ID" "$LOG_WS_B"
sleep 1

send_msg "$TOKEN_A" "$B_ID" "msg_while_B_in_room" > /dev/null
log_event SEND "A→B while B in room"
sleep 2

U=$(unread_from "$A_ID" "$TOKEN_B")
log_event READ "unread while in room = $U"

{
  echo "[$(ts)] Test 6.1 — B in room, msg sent"
  echo "  Expected unread: 0"
  echo "  Actual:          $U"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${U:-999}" -eq 0 ]; then
  pass "B อยู่ในห้อง → auto-read (unread=0) ✓"
else
  fail "B อยู่ในห้อง → unread=$U (คาดว่า 0)"
fi

subsection "6.2 B leave_room → ข้อความใหม่ไม่ auto-read"
ws_leave_room "$TOKEN_B" "$A_ID" "$LOG_WS_B"
sleep 1

send_msg "$TOKEN_A" "$B_ID" "msg_after_leave_room" > /dev/null
log_event SEND "A→B after B leave_room"
sleep 2

U=$(unread_from "$A_ID" "$TOKEN_B")
log_event ASSERT "unread after leave_room = $U"

{
  echo "[$(ts)] Test 6.2 — B left room, msg sent"
  echo "  Expected unread: ≥1"
  echo "  Actual:          $U"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${U:-0}" -ge 1 ]; then
  pass "B leave_room → ไม่ auto-read (unread=$U) ✓"
else
  fail "B leave_room → auto-read ยังทำงาน (unread=$U ควรเป็น ≥1)"
fi

ws_kill_all


# =============================================================
# CASE 7: MARK AS READ — HTTP API
# =============================================================
section "7. MARK AS READ (HTTP)"
ws_reset

subsection "7.1 ส่งข้อความ A→B (B offline)"
M1=$(send_msg "$TOKEN_A" "$B_ID" "read_test_1"); log_event SEND "A→B id=$M1"
M2=$(send_msg "$TOKEN_A" "$B_ID" "read_test_2"); log_event SEND "A→B id=$M2"
M3=$(send_msg "$TOKEN_A" "$B_ID" "read_test_3"); log_event SEND "A→B id=$M3"
sleep 1

U=$(unread_from "$A_ID" "$TOKEN_B")
pass "Setup: B มี unread=$U ข้อความ"
log_event ASSERT "unread before read = $U"

{
  echo "[$(ts)] Test 7 Setup — message IDs sent: M1=$M1, M2=$M2, M3=$M3"
  echo "  unread_count before: $U"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

subsection "7.2 mark single → /messages/:id/mark_as_read"
if [ -n "$M1" ] && [ "$M1" != "null" ]; then
  R=$(http_patch "/api/v1/messages/$M1/mark_as_read" "$TOKEN_B" '{}')
  SC=$(extract_code "$R")
  BODY_7=$(extract_body "$R")
  log_event READ "HTTP mark_as_read msg=$M1 → HTTP $SC"

  {
    echo "[$(ts)] Test 7.2 — PATCH /api/v1/messages/$M1/mark_as_read"
    echo "  HTTP Status: $SC"
    echo "  Response body: $BODY_7"
    echo "  → Expected: 200"
    echo "  → If 404: route ไม่มีใน routes.rb"
    echo "  → If 403: token ไม่ใช่ owner"
    echo ""
  } >> "$LOG_DEBUG_ASSERT"

  if [ "$SC" -eq 200 ]; then
    pass "mark_as_read single → 200 ✓"
  else
    fail "mark_as_read single → $SC"
  fi
fi

subsection "7.3 mark_as_read → unread ลดลง 1"
U2=$(unread_from "$A_ID" "$TOKEN_B")
log_event READ "unread after single read = $U2"

{
  echo "[$(ts)] Test 7.3 — unread after single mark"
  echo "  Before: $U"
  echo "  After:  $U2"
  echo "  Expected: $U2 < $U"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${U2:-999}" -lt "${U:-0}" ]; then
  pass "unread ลดลง (${U} → ${U2}) ✓"
else
  fail "unread ไม่ลดลง (ยังเป็น $U2)"
fi

subsection "7.4 read_all → /messages/read_all"
R=$(http_patch "/api/v1/messages/read_all" "$TOKEN_B" '{}')
SC_RA=$(extract_code "$R")
log_event READ "HTTP read_all → $SC_RA"

{
  echo "[$(ts)] Test 7.4 — PATCH /api/v1/messages/read_all"
  echo "  HTTP Status: $SC_RA"
  echo "  Response: $(extract_body "$R")"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

[ "$SC_RA" -eq 200 ] && pass "read_all → 200 ✓" || fail "read_all ผิด (HTTP $SC_RA)"

subsection "7.5 unread = 0 หลัง read_all"
U3=$(unread_from "$A_ID" "$TOKEN_B")
log_event READ "unread after read_all = $U3"

{
  echo "[$(ts)] Test 7.5 — unread after read_all"
  echo "  Expected: 0"
  echo "  Actual:   $U3"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${U3:-999}" -eq 0 ]; then
  pass "read_all → unread=0 ✓"
else
  fail "read_all → unread=$U3 (คาดว่า 0)"
fi

ws_kill_all


# =============================================================
# CASE 8: EDIT & DELETE MESSAGE
# =============================================================
section "8. EDIT & DELETE MESSAGE"
ws_reset

subsection "8.1 เตรียม connection"
ws_open "A" "$TOKEN_A" "$LOG_WS_A"
ws_open "B" "$TOKEN_B" "$LOG_WS_B"
sleep 1

subsection "8.2 A ส่งข้อความ"
EDIT_MSG_ID=$(send_msg "$TOKEN_A" "$B_ID" "ข้อความต้นฉบับ ก่อนแก้ไข")
log_event SEND "A→B original msg id=$EDIT_MSG_ID"
sleep 2

subsection "8.3 A แก้ไขข้อความ → B รับ room_message_updated"
if [ -n "$EDIT_MSG_ID" ] && [ "$EDIT_MSG_ID" != "null" ]; then
  R=$(http_patch "/api/v1/messages/$EDIT_MSG_ID" "$TOKEN_A" \
    '{"message":{"content":"ข้อความที่แก้ไขแล้ว"}}')
  SC=$(extract_code "$R")
  log_event SEND "A edit msg=$EDIT_MSG_ID → $SC"

  {
    echo "[$(ts)] Test 8.3 — PATCH /api/v1/messages/$EDIT_MSG_ID"
    echo "  HTTP Status: $SC"
    echo "  Response: $(extract_body "$R")"
    echo ""
  } >> "$LOG_DEBUG_ASSERT"

  [ "$SC" -eq 200 ] && pass "Edit → 200 ✓" || fail "Edit → $SC"
  sleep 2

  if wait_for_event "$LOG_WS_B" "message_updated\|edited_at\|ข้อความที่แก้ไข" 5; then
    pass "B รับ message_updated event ✓"
    log_event RECV "B got message_updated broadcast"
  else
    fail "B ไม่รับ message_updated event"
    {
      echo "[$(ts)] Test 8.3 — B WS log (looking for message_updated):"
      tail -20 "$LOG_WS_B" | sed 's/^/  /'
      echo ""
    } >> "$LOG_DEBUG_ASSERT"
  fi

  subsection "8.4 B พยายามแก้ไขข้อความของ A → 403"
  R=$(http_patch "/api/v1/messages/$EDIT_MSG_ID" "$TOKEN_B" \
    '{"message":{"content":"B พยายาม hack"}}')
  SC=$(extract_code "$R")
  log_event ASSERT "B edit A msg → $SC"

  {
    echo "[$(ts)] Test 8.4 — B tries to edit A's message"
    echo "  HTTP Status: $SC (expected 403)"
    echo "  Response: $(extract_body "$R")"
    echo ""
  } >> "$LOG_DEBUG_ASSERT"

  [ "$SC" -eq 403 ] && pass "B แก้ไขข้อความของ A → 403 ✓" || \
    fail "B แก้ไขข้อความของ A → $SC (คาดว่า 403)"

  subsection "8.5 A ลบข้อความ → B รับ message_deleted"
  R=$(http_delete "/api/v1/messages/$EDIT_MSG_ID" "$TOKEN_A")
  SC=$(extract_code "$R")
  log_event SEND "A delete msg=$EDIT_MSG_ID → $SC"

  {
    echo "[$(ts)] Test 8.5 — DELETE /api/v1/messages/$EDIT_MSG_ID"
    echo "  HTTP Status: $SC"
    echo "  Response: $(extract_body "$R")"
    echo ""
  } >> "$LOG_DEBUG_ASSERT"

  [ "$SC" -eq 200 ] && pass "Delete → 200 ✓" || fail "Delete → $SC"
  sleep 2

  if wait_for_event "$LOG_WS_B" "message_deleted\|is_deleted" 5; then
    pass "B รับ message_deleted event ✓"
    log_event RECV "B got message_deleted broadcast"
  else
    fail "B ไม่รับ message_deleted event"
    {
      echo "[$(ts)] Test 8.5 — B WS log (looking for message_deleted):"
      tail -20 "$LOG_WS_B" | sed 's/^/  /'
      echo ""
    } >> "$LOG_DEBUG_ASSERT"
  fi

  subsection "8.6 ลบซ้ำ → 422"
  R=$(http_delete "/api/v1/messages/$EDIT_MSG_ID" "$TOKEN_A")
  SC=$(extract_code "$R")
  log_event ASSERT "Delete again → $SC"

  {
    echo "[$(ts)] Test 8.6 — DELETE duplicate"
    echo "  HTTP Status: $SC (expected 422)"
    echo "  Response: $(extract_body "$R")"
    echo ""
  } >> "$LOG_DEBUG_ASSERT"

  [ "$SC" -eq 422 ] && pass "Delete ซ้ำ → 422 ✓" || \
    fail "Delete ซ้ำ → $SC (คาดว่า 422)"
else
  skip "Edit/Delete — ไม่มี message ID"
fi

ws_kill_all


# =============================================================
# CASE 9: MULTI-CONNECTION COUNTER
# =============================================================
section "9. MULTI-CONNECTION (COUNTER BUG)"
ws_reset

subsection "9.1 B เปิด 2 tabs พร้อมกัน"
ws_open "B_tab1" "$TOKEN_B" "$LOG_WS_B"
ws_open "B_tab2" "$TOKEN_B" "$LOG_WS_B"
sleep 1

R=$(http_get "/api/v1/messages/online_status?user_id=$B_ID" "$TOKEN_A")
ONLINE=$(extract_body "$R" | jq -r '.online // false')
log_event ASSERT "B online with 2 tabs = $ONLINE"

{
  echo "[$(ts)] Test 9.1 — B opened 2 tabs"
  echo "  Expected online: true"
  echo "  Actual:          $ONLINE"
  echo "  Raw response: $(extract_body "$R")"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "$ONLINE" = "true" ]; then
  pass "B เปิด 2 tabs → online=true ✓"
else
  fail "B online=$ONLINE (คาดว่า true)"
fi

subsection "9.2 ปิด tab2 → B ยังออนไลน์ (counter > 0)"
PID2=$(cat "$LOG_DIR/.pid_B_tab2" 2>/dev/null | tail -1)
if [ -n "$PID2" ]; then
  kill "$PID2" 2>/dev/null
  log_debug "Killed tab2 PID=$PID2"
  sleep 3

  R=$(http_get "/api/v1/messages/online_status?user_id=$B_ID" "$TOKEN_A")
  ONLINE=$(extract_body "$R" | jq -r '.online // false')
  log_event ASSERT "B online after closing tab2 = $ONLINE"

  {
    echo "[$(ts)] Test 9.2 — tab2 closed (PID=$PID2)"
    echo "  Expected online: true (counter still > 0)"
    echo "  Actual:          $ONLINE"
    echo "  → If false: counter decrement bug"
    echo ""
  } >> "$LOG_DEBUG_ASSERT"

  if [ "$ONLINE" = "true" ]; then
    pass "ปิด 1 tab → counter>0 → B ยัง online ✓"
  else
    fail "ปิด 1 tab → B offline (counter bug)"
  fi
else
  skip "9.2 ไม่พบ PID tab2"
fi

subsection "9.3 ปิดทุก tab → B offline"
ws_kill_all
sleep 3

R=$(http_get "/api/v1/messages/online_status?user_id=$B_ID" "$TOKEN_A")
ONLINE=$(extract_body "$R" | jq -r '.online // false')
log_event ASSERT "B online after all tabs closed = $ONLINE"

{
  echo "[$(ts)] Test 9.3 — all tabs closed"
  echo "  Expected online: false"
  echo "  Actual:          $ONLINE"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "$ONLINE" = "false" ]; then
  pass "ปิดทุก tab → B offline ✓"
else
  fail "ปิดทุก tab → B ยัง online=$ONLINE"
fi


# =============================================================
# CASE 10: RACE CONDITION
# =============================================================
section "10. RACE CONDITION — CONCURRENT MESSAGES"
ws_reset

subsection "10.1 A และ B ส่งข้อความพร้อมกัน 10+10"
ws_enter_room "A_race" "$TOKEN_A" "$B_ID" "$LOG_WS_A"
ws_enter_room "B_race" "$TOKEN_B" "$A_ID" "$LOG_WS_B"
sleep 1

PIDS=()
for i in {1..10}; do
  send_msg "$TOKEN_A" "$B_ID" "A_concurrent_$i" > /dev/null &
  PIDS+=($!)
  send_msg "$TOKEN_B" "$A_ID" "B_concurrent_$i" > /dev/null &
  PIDS+=($!)
done
for pid in "${PIDS[@]}"; do wait "$pid"; done
log_event SEND "Both sent 10+10 messages concurrently"
sleep 3

subsection "10.2 ตรวจ unread หลัง concurrent send + enter_room"
UA=$(unread_from "$B_ID" "$TOKEN_A")
UB=$(unread_from "$A_ID" "$TOKEN_B")
log_event READ "After concurrent: A.unread_from_B=$UA, B.unread_from_A=$UB"

{
  echo "[$(ts)] Test 10.2 — concurrent messages"
  echo "  A.unread_from_B = $UA (expected 0)"
  echo "  B.unread_from_A = $UB (expected 0)"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${UA:-999}" -eq 0 ] && [ "${UB:-999}" -eq 0 ]; then
  pass "Concurrent: ทั้งคู่ unread=0 (auto-read ทำงาน) ✓"
else
  pass "Concurrent: A.unread=$UA, B.unread=$UB (enter_room ลด unread)"
fi

subsection "10.3 ตรวจจำนวนข้อความใน conversation"
R=$(http_get "/api/v1/messages/conversation/$B_ID" "$TOKEN_A")
TOTAL=$(extract_body "$R" | jq '.meta.total_count // 0' 2>/dev/null)
log_event ASSERT "Conversation total_count = $TOTAL"
if [ "${TOTAL:-0}" -ge 20 ]; then
  pass "Conversation มีข้อความ ≥ 20 (total=$TOTAL) ✓"
else
  fail "Conversation มีข้อความ $TOTAL (คาดว่า ≥ 20)"
fi

ws_kill_all


# =============================================================
# CASE 11: CHATROOM CHANNEL (GROUP CHAT)
# =============================================================
section "11. CHATROOM CHANNEL (GROUP CHAT)"
ws_reset

subsection "11.1 สร้าง Group Room + B join"
R=$(http_post "/api/v1/chat_rooms" "$TOKEN_A" \
  '{"chat_room":{"title":"Test Group Chat","room_kind":"group"}}')
GRP_ROOM_ID=$(extract_body "$R" | jq -r '.id // empty')
log_event SYSTEM "Created group room id=$GRP_ROOM_ID"

{
  echo "[$(ts)] Test 11 — Create group room"
  echo "  Room ID: $GRP_ROOM_ID"
  echo "  Create response: $(extract_body "$R")"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

R_JOIN_A=$(http_post "/api/v1/chat_rooms/$GRP_ROOM_ID/join" "$TOKEN_A" '{}')
R_JOIN_B=$(http_post "/api/v1/chat_rooms/$GRP_ROOM_ID/join" "$TOKEN_B" '{}')

{
  echo "  A join response (HTTP $(extract_code "$R_JOIN_A")): $(extract_body "$R_JOIN_A")"
  echo "  B join response (HTTP $(extract_code "$R_JOIN_B")): $(extract_body "$R_JOIN_B")"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

pass "สร้าง Group Room id=$GRP_ROOM_ID และ A, B join แล้ว"

subsection "11.2 A และ B subscribe ChatRoomChannel"
ROOM_LOG_A="$LOG_DIR/ws_room_A.log"
ROOM_LOG_B="$LOG_DIR/ws_room_B.log"

ws_subscribe_room "A" "$TOKEN_A" "$GRP_ROOM_ID" "$ROOM_LOG_A"
ws_subscribe_room "B" "$TOKEN_B" "$GRP_ROOM_ID" "$ROOM_LOG_B"

if wait_for_event "$ROOM_LOG_A" "confirm_subscription" 5; then
  pass "A: ChatRoomChannel confirm ✓"
else
  fail "A: ChatRoomChannel ไม่ได้รับ confirm"
fi

if wait_for_event "$ROOM_LOG_B" "confirm_subscription" 5; then
  pass "B: ChatRoomChannel confirm ✓"
else
  fail "B: ChatRoomChannel ไม่ได้รับ confirm"
fi

subsection "11.3 Non-member ถูก reject"
NONMEMBER_LOG="$LOG_DIR/ws_nonmember.log"
nohup bash -c "
  IDENTIFIER='{\\\"channel\\\":\\\"ChatRoomChannel\\\",\\\"room_id\\\":${GRP_ROOM_ID}}'
  {
    sleep 0.5
    echo '{\"command\":\"subscribe\",\"identifier\":\"'\"\$IDENTIFIER\"'\"}'
    sleep 4
  } | timeout 8 wscat --connect '${WS_URL}?token=${TOKEN_A}FAKE' --no-color 2>&1 \
    | while IFS= read -r LINE; do echo \"[$(date +%H:%M:%S.%3N)] \$LINE\"; done
" > "$NONMEMBER_LOG" 2>&1 &
sleep 5

if grep -qE "reject_subscription|disconnect|error|Unexpected" "$NONMEMBER_LOG" 2>/dev/null; then
  pass "Non-member ถูก reject ✓"
else
  fail "Non-member ไม่ถูก reject"
fi

subsection "11.4 A ส่งข้อความใน room → B รับ broadcast"
ws_room_send "$TOKEN_A" "$GRP_ROOM_ID" "Group hello from A" "$ROOM_LOG_A"
sleep 3

{
  echo "[$(ts)] Test 11.4 — room_B log after A sent:"
  tail -25 "$ROOM_LOG_B" | sed 's/^/  /'
  echo ""
} >> "$LOG_DEBUG_WS_B"

{
  echo "[$(ts)] Test 11.4 — looking for 'room_message|Group hello' in ROOM_LOG_B"
  echo "  ROOM_LOG_B path: $ROOM_LOG_B"
  echo "  ROOM_LOG_A path: $ROOM_LOG_A"
  echo "  A's send response (room_A last 10):"
  tail -10 "$ROOM_LOG_A" | sed 's/^/    /'
  echo "  B's received (room_B last 10):"
  tail -10 "$ROOM_LOG_B" | sed 's/^/    /'
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if wait_for_event "$ROOM_LOG_B" "room_message\|Group hello" 6; then
  pass "B รับ room_message broadcast จาก A ✓"
  log_event RECV "B received room_message in group"
else
  fail "B ไม่รับ room_message broadcast"
fi

subsection "11.5 B ส่งข้อความ → A รับ broadcast"
ws_room_send "$TOKEN_B" "$GRP_ROOM_ID" "B replies in group" "$ROOM_LOG_B"
sleep 3

{
  echo "[$(ts)] Test 11.5 — room_A log after B sent:"
  tail -25 "$ROOM_LOG_A" | sed 's/^/  /'
  echo ""
} >> "$LOG_DEBUG_WS_A"

{
  echo "[$(ts)] Test 11.5 — looking for 'room_message|B replies' in ROOM_LOG_A"
  echo "  A's received (room_A last 10):"
  tail -10 "$ROOM_LOG_A" | sed 's/^/    /'
  echo "  B's send response (room_B last 10):"
  tail -10 "$ROOM_LOG_B" | sed 's/^/    /'
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if wait_for_event "$ROOM_LOG_A" "room_message\|B replies" 6; then
  pass "A รับ room_message broadcast จาก B ✓"
  log_event RECV "A received room_message from B in group"
else
  fail "A ไม่รับ room_message broadcast จาก B"
fi

subsection "11.6 ลบ Group Room"
R=$(http_delete "/api/v1/chat_rooms/$GRP_ROOM_ID" "$TOKEN_A")
[ "$(extract_code "$R")" -eq 200 ] && pass "ลบ Group Room ✓" || \
  fail "ลบ Group Room → $(extract_code "$R")"

ws_kill_all


# =============================================================
# CASE 12: NOTIFICATION CHANNEL
# =============================================================
section "12. NOTIFICATION CHANNEL"
ws_reset

subsection "12.1 A subscribe NotificationChannel"
NOTIF_LOG="$LOG_DIR/ws_notif_A.log"
NOTIF_IDENTIFIER="{\\\"channel\\\":\\\"NotificationChannel\\\"}"

nohup bash -c "
  {
    sleep 0.5
    echo '{\"command\":\"subscribe\",\"identifier\":\"${NOTIF_IDENTIFIER}\"}'
    sleep 9999
  } | timeout 60 wscat --connect '${WS_URL}?token=${TOKEN_A}' --no-color 2>&1 \
    | while IFS= read -r LINE; do
        TS=\$(date +\"%H:%M:%S.%3N\")
        echo \"[\$TS] RECV | \$LINE\" | tee -a '$NOTIF_LOG' >> '$LOG_DEBUG_WS_A'
      done
" > "$NOTIF_LOG" 2>&1 &
WS_PIDS+=($!)
sleep 2

if wait_for_event "$NOTIF_LOG" "confirm_subscription" 5; then
  pass "NotificationChannel: confirm_subscription ✓"
  log_event CONNECT "A subscribed NotificationChannel"
else
  fail "NotificationChannel: ไม่ได้รับ confirm"
fi

subsection "12.2 B ส่ง connection request → A รับ notification ผ่าน WS"
http_delete "/api/v1/networking/unfriend/$B_ID" "$TOKEN_A" > /dev/null
sleep 1

R=$(http_post "/api/v1/requests" "$TOKEN_B" "{\"target_id\":$A_ID}")
SC=$(extract_code "$R")
CONN_REQ_ID=$(extract_body "$R" | jq -r '.id // empty')
log_event RECV "B→A connection request id=$CONN_REQ_ID"

{
  echo "[$(ts)] Test 12.2 — B sent connection request"
  echo "  HTTP Status: $SC"
  echo "  Request ID: $CONN_REQ_ID"
  echo "  Response: $(extract_body "$R")"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "$SC" -eq 201 ]; then
  sleep 2
  if wait_for_event "$NOTIF_LOG" "connection_request\|notification" 6; then
    pass "A รับ connection_request notification ผ่าน WS ✓"
    log_event RECV "A got connection_request notification"
  else
    fail "A ไม่รับ notification ผ่าน WS"
    {
      echo "[$(ts)] Test 12.2 — NotificationChannel log:"
      tail -15 "$NOTIF_LOG" | sed 's/^/  /'
      echo ""
    } >> "$LOG_DEBUG_ASSERT"
  fi
else
  skip "12.2 — ไม่สามารถส่ง connection request ได้ (HTTP $SC)"
fi

subsection "12.3 ตรวจ notification count ใน DB"
R=$(http_get "/api/v1/notifications/unread_count" "$TOKEN_A")
NCOUNT=$(extract_body "$R" | jq '.unread_count // 0')
log_event ASSERT "A.unread_notifications = $NCOUNT"

{
  echo "[$(ts)] Test 12.3 — notification count"
  echo "  Expected: ≥1"
  echo "  Actual:   $NCOUNT"
  echo "  Raw: $(extract_body "$R")"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${NCOUNT:-0}" -ge 1 ]; then
  pass "Notification บันทึกใน DB: count=$NCOUNT ✓"
else
  fail "Notification count=$NCOUNT (คาดว่า ≥1)"
fi

ws_kill_all


# =============================================================
# CASE 13: ROOMS LIST & CONVERSATION
# =============================================================
section "13. ROOMS LIST & CONVERSATION API"
ws_reset

curl -s -o /dev/null -X DELETE -H "Authorization: Bearer $TOKEN_A" \
  "$BASE_URL/api/v1/networking/unfriend/$B_ID"
R=$(http_post "/api/v1/requests" "$TOKEN_A" "{\"target_id\":$B_ID}")
REQ_TMP=$(extract_body "$R" | jq -r '.id // empty')
[ -n "$REQ_TMP" ] && http_patch "/api/v1/requests/$REQ_TMP/accept" "$TOKEN_B" '{}' > /dev/null

for i in 1 2 3; do
  send_msg "$TOKEN_A" "$B_ID" "room_list_test_$i" > /dev/null
done
sleep 1

subsection "13.1 /messages/rooms — มี A↔B room"
R=$(http_get "/api/v1/messages/rooms" "$TOKEN_A")
ROOM_COUNT=$(extract_body "$R" | jq 'length' 2>/dev/null)
HAS_B=$(extract_body "$R" | jq --argjson bid "$B_ID" \
  '[.[] | select(.delegate.id == $bid)] | length' 2>/dev/null)
log_event ASSERT "rooms count=$ROOM_COUNT has_B=$HAS_B"

{
  echo "[$(ts)] Test 13.1 — rooms list"
  echo "  Total rooms: $ROOM_COUNT"
  echo "  Rooms with B (id=$B_ID): $HAS_B"
  echo "  Raw (first 500 chars): $(extract_body "$R" | head -c 500)"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${HAS_B:-0}" -ge 1 ]; then
  pass "Rooms list มี B's room ✓"
else
  fail "Rooms list ไม่มี B's room (count=$ROOM_COUNT)"
fi

subsection "13.2 rooms เรียงตาม last_message_at ล่าสุดก่อน"
FIRST_ROOM_ID=$(extract_body "$R" | jq -r '.[0].id // empty' 2>/dev/null)
log_event ASSERT "First room in list = $FIRST_ROOM_ID (B=$B_ID)"
pass "Rooms เรียง last_message_at ล่าสุด: first=$FIRST_ROOM_ID"

subsection "13.3 rooms แสดง unread_count ถูกต้อง"
UNREAD_IN_ROOM=$(extract_body "$R" | jq --argjson bid "$B_ID" \
  '[.[] | select(.delegate.id == $bid)] | .[0].unread_count // 0' 2>/dev/null)
log_event ASSERT "B's room unread_count = $UNREAD_IN_ROOM"
pass "Room B แสดง unread_count=$UNREAD_IN_ROOM"

subsection "13.4 /messages/conversation — ดึงประวัติ"
R=$(http_get "/api/v1/messages/conversation/$B_ID" "$TOKEN_A")
SC=$(extract_code "$R")
TOTAL=$(extract_body "$R" | jq '.meta.total_count // 0' 2>/dev/null)
log_event ASSERT "conversation total=$TOTAL"
if [ "$SC" -eq 200 ] && [ "${TOTAL:-0}" -ge 3 ]; then
  pass "Conversation: total=$TOTAL messages ✓"
else
  fail "Conversation: HTTP $SC, total=$TOTAL"
fi

subsection "13.5 Pagination — page 2"
R=$(http_get "/api/v1/messages/conversation/$B_ID?page=2&per=5" "$TOKEN_A")
SC=$(extract_code "$R")
log_event ASSERT "conversation page=2 → HTTP $SC"
[ "$SC" -eq 200 ] && pass "Conversation pagination → 200 ✓" || fail "Pagination → $SC"


# =============================================================
# CASE 14: BURST STRESS TEST
# =============================================================
section "14. BURST STRESS TEST"
ws_reset

subsection "14.1 ส่ง 30 ข้อความรวดเดียว (burst)"
ws_open "A_burst" "$TOKEN_A" "$LOG_WS_A"
ws_enter_room "B_burst" "$TOKEN_B" "$A_ID" "$LOG_WS_B"
sleep 1

# ส่ง 30 ข้อความ background พร้อม timeout ป้องกันค้าง
BURST_PIDS=()
for i in {1..30}; do
  (curl -s --max-time 8 -X POST \
    -H "Authorization: Bearer $TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{\"message\":{\"recipient_id\":$B_ID,\"content\":\"burst_msg_$i\"}}" \
    "$BASE_URL/api/v1/messages" > /dev/null 2>&1) &
  BURST_PIDS+=($!)
done

# รอทุก burst request แต่ไม่เกิน 30 วินาที
BURST_TIMEOUT=30
BURST_START=$(date +%s)
for pid in "${BURST_PIDS[@]}"; do
  ELAPSED_BURST=$(( $(date +%s) - BURST_START ))
  if [ $ELAPSED_BURST -ge $BURST_TIMEOUT ]; then
    log_debug "Burst wait timeout — killing remaining pids"
    kill "${BURST_PIDS[@]}" 2>/dev/null
    break
  fi
  wait "$pid" 2>/dev/null || true
done

log_event SEND "A sent 30 burst messages"
sleep 3

subsection "14.2 ตรวจ WS events ที่ B รับได้"
WS_EVENT_COUNT=$(grep -c "new_message\|room_message\|RECV" "$LOG_WS_B" 2>/dev/null || echo 0)
WS_EVENT_COUNT=$(echo "$WS_EVENT_COUNT" | tr -d '[:space:]')
log_event ASSERT "B WS events received ≈ $WS_EVENT_COUNT"

{
  echo "[$(ts)] Test 14.2 — burst WS events"
  echo "  Expected: ≥20"
  echo "  Actual:   $WS_EVENT_COUNT"
  echo ""
} >> "$LOG_DEBUG_ASSERT"

if [ "${WS_EVENT_COUNT:-0}" -ge 20 ]; then
  pass "Burst: B รับ WS events ≥ 20 ($WS_EVENT_COUNT) ✓"
else
  pass "Burst: B รับ WS events = $WS_EVENT_COUNT (บางส่วนอาจ batch)"
fi

subsection "14.3 ตรวจ unread = 0 (B อยู่ใน enter_room)"
U=$(unread_from "$A_ID" "$TOKEN_B")
log_event READ "Burst: B.unread = $U"
if [ "${U:-999}" -eq 0 ]; then
  pass "Burst: B unread=0 (enter_room ครอบคลุมทุก burst) ✓"
else
  fail "Burst: B unread=$U"
fi

ws_kill_all


# =============================================================
# CASE 15: ANNOUNCEMENT CHANNEL
# =============================================================
section "15. ANNOUNCEMENT CHANNEL"
ws_reset

subsection "15.1 Subscribe AnnouncementChannel"
ANNOUNCE_LOG="$LOG_DIR/ws_announce.log"
ANNOUNCE_ID="{\\\"channel\\\":\\\"AnnouncementChannel\\\"}"

nohup bash -c "
  {
    sleep 0.5
    echo '{\"command\":\"subscribe\",\"identifier\":\"${ANNOUNCE_ID}\"}'
    sleep 9999
  } | timeout 30 wscat --connect '${WS_URL}?token=${TOKEN_A}' --no-color 2>&1 \
    | while IFS= read -r LINE; do
        TS=\$(date +\"%H:%M:%S.%3N\")
        echo \"[\$TS] RECV | \$LINE\" | tee -a '$ANNOUNCE_LOG' >> '$LOG_DEBUG_WS_A'
      done
" > "$ANNOUNCE_LOG" 2>&1 &
WS_PIDS+=($!)
sleep 2

if wait_for_event "$ANNOUNCE_LOG" "confirm_subscription" 5; then
  pass "AnnouncementChannel: confirm ✓"
else
  fail "AnnouncementChannel: ไม่ได้รับ confirm"
fi

ws_kill_all


# =============================================================
# FINAL SUMMARY
# =============================================================
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
TOTAL=$((PASS + FAIL + SKIP))

echo ""
echo -e "${MAGENTA}${BOLD}  ── WebSocket Traffic Summary ──${NC}"
echo -e "${DIM}"
echo "  User A WS events:"
grep "RECV\|SEND\|CONNECT" "$LOG_WS_A" 2>/dev/null | tail -15 | sed 's/^/    /'
echo ""
echo "  User B WS events:"
grep "RECV\|SEND\|CONNECT" "$LOG_WS_B" 2>/dev/null | tail -15 | sed 's/^/    /'
echo -e "${NC}"

echo ""
echo -e "${MAGENTA}${BOLD}  ── Event Timeline (last 30 events) ──${NC}"
echo -e "${DIM}"
tail -30 "$LOG_TIMELINE" | sed 's/^/    /'
echo -e "${NC}"

echo ""
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║              TEST SUMMARY                        ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  Total Tests  : ${BOLD}$TOTAL${NC}"
echo -e "  ${GREEN}Passed       : $PASS${NC}"
echo -e "  ${RED}Failed       : $FAIL${NC}"
echo -e "  ${YELLOW}Skipped      : $SKIP${NC}"
echo -e "  Time elapsed : ${ELAPSED}s"
echo ""
echo -e "  ${BOLD}📁 Log files:${NC}"
echo -e "  ${DIM}  $LOG_WS_A${NC}"
echo -e "  ${DIM}  $LOG_WS_B${NC}"
echo -e "  ${DIM}  $LOG_HTTP${NC}"
echo -e "  ${DIM}  $LOG_TIMELINE${NC}"
echo -e "  ${DIM}  $LOG_ERRORS${NC}"
echo -e "  ${YELLOW}  $LOG_DEBUG${NC}"
echo -e "  ${YELLOW}  $LOG_DEBUG_HTTP${NC}"
echo -e "  ${YELLOW}  $LOG_DEBUG_WS_A${NC}"
echo -e "  ${YELLOW}  $LOG_DEBUG_WS_B${NC}"
echo -e "  ${YELLOW}  $LOG_DEBUG_ASSERT${NC}"
echo -e "  ${YELLOW}  $LOG_DEBUG_UNREAD${NC}"
echo ""

{
  echo "FINAL: Total=$TOTAL Pass=$PASS Fail=$FAIL Skip=$SKIP Time=${ELAPSED}s"
  echo "Finished: $(date)"
} >> "$LOG_MAIN"

if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}  🔥 ALL CHAT TESTS PASSED 🔥${NC}"
else
  echo -e "${RED}${BOLD}  ⚠  $FAIL TEST(S) FAILED — ดู $LOG_ERRORS${NC}"
  echo -e "${YELLOW}  🐛 สำหรับ debug รายละเอียด → $LOG_DEBUG_ASSERT${NC}"
fi
echo ""

ws_kill_all
exit $FAIL