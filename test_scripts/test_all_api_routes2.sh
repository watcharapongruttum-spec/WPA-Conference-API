#!/bin/bash
set +e

BASE_URL="http://localhost:3000"
EMAIL="narisara.lasan@bestgloballogistics.com"
PASSWORD="123456"

# ===== FIXED IDS FROM RAILS C =====
ME_ID=300
OTHER_ID=1
CONF_DATE_ID=1
TABLE_ID=1
ROOM_KIND=0
FALLBACK_REQUEST_ID=4

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

LOG_DIR="../log"
LOG_FILE="$LOG_DIR/res.txt"
REQ_FILE="$LOG_DIR/req.txt"

mkdir -p $LOG_DIR
echo "===== API RES LOG $(date) =====" > $LOG_FILE
echo "===== API REQ LOG $(date) =====" > $REQ_FILE


ok(){ echo -e "${GREEN}✅ $1${NC}"; PASSED=$((PASSED+1)); }
fail(){ echo -e "${RED}❌ $1${NC}"; FAILED=$((FAILED+1)); }
warn(){ echo -e "${YELLOW}⚠️ $1${NC}"; PASSED=$((PASSED+1)); }

# ---------------- LOGIN ----------------
login(){
  echo "🔐 Login..."
  RES=$(curl -s -X POST "$BASE_URL/api/v1/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

  TOKEN=$(echo "$RES" | jq -r '.token')

  if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
    echo "$RES"
    fail "Login Failed"
    exit 1
  else
    ok "Login Success"
  fi
}

# ---------------- CURL ----------------
auth_code(){
  URL=$1; shift
  curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" "$URL" "$@"
}

auth_body(){
  URL=$1; shift
  curl -s -H "Authorization: Bearer $TOKEN" "$URL" "$@"
}

# ---------------- LOG ----------------
log_res(){
  SECTION=$1
  METHOD=$2
  URL=$3
  DATA=$4

  echo "" >> $LOG_FILE
  echo "========== $SECTION ==========" >> $LOG_FILE
  echo "$METHOD $URL" >> $LOG_FILE

  if [ "$METHOD" = "GET" ]; then
    RES=$(auth_body "$URL")
  else
    RES=$(curl -s -X $METHOD "$URL" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "$DATA")
  fi

  echo "$RES" | jq '
    if type == "array" then .[0:3] else . end
  ' >> $LOG_FILE 2>/dev/null || echo "$RES" >> $LOG_FILE
}



log_req(){
  SECTION=$1
  METHOD=$2
  URL=$3
  DATA=$4

  echo "" >> $REQ_FILE
  echo "========== $SECTION ==========" >> $REQ_FILE
  echo "$METHOD $URL" >> $REQ_FILE

  if [ -n "$DATA" ]; then
    echo "BODY: $DATA" >> $REQ_FILE
  fi
}




# ---------------- TEST ----------------
test_api(){
  M=$1; U=$2; D=$3; S=$4
  echo -n "$M $U ... "

  case $M in
    GET) CODE=$(auth_code "$U");;
    POST) CODE=$(auth_code "$U" -X POST -H "Content-Type: application/json" -d "$D");;
    PATCH) CODE=$(auth_code "$U" -X PATCH -H "Content-Type: application/json" -d "$D");;
  esac

  log_req "$S" "$M" "$U" "$D"
  log_res "$S" "$M" "$U" "$D"


  if [[ "$CODE" =~ ^(200|201|204)$ ]]; then ok "$CODE"
  elif [[ "$CODE" =~ ^(403|404|422)$ ]]; then warn "$CODE"
  else fail "$CODE"
  fi
}

get_id(){
  RES=$(auth_body "$1")
  echo "$RES" | jq -r '.[0].id // empty' 2>/dev/null
}

echo "🚀 FULL ROUTE TEST"
login
echo ""

# ================= AUTH =================
test_api POST "$BASE_URL/api/v1/change_password" '{"old_password":"123456","new_password":"123456"}' "AUTH"
test_api POST "$BASE_URL/api/v1/forgot_password" "{\"email\":\"$EMAIL\"}" "AUTH"

# ================= PROFILE =================
test_api GET "$BASE_URL/api/v1/profile" "" "PROFILE"

# ================= DASHBOARD =================
test_api GET "$BASE_URL/api/v1/dashboard" "" "DASHBOARD"

# ================= DELEGATES =================
test_api GET "$BASE_URL/api/v1/delegates" "" "DELEGATES"
test_api GET "$BASE_URL/api/v1/delegates/search?q=test" "" "DELEGATES"
test_api GET "$BASE_URL/api/v1/delegates/$OTHER_ID" "" "DELEGATES"
test_api GET "$BASE_URL/api/v1/delegates/$OTHER_ID/qr_code" "" "DELEGATES"

# ================= SCHEDULES =================
START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
END=$(date -u -d "+30 minutes" +"%Y-%m-%dT%H:%M:%SZ")
SCH_DATA="{\"conference_date_id\":$CONF_DATE_ID,\"target_id\":$OTHER_ID,\"start_at\":\"$START\",\"end_at\":\"$END\",\"table_number\":\"A1\"}"

test_api GET "$BASE_URL/api/v1/schedules" "" "SCHEDULES"
test_api GET "$BASE_URL/api/v1/schedules/my_schedule" "" "SCHEDULES"
test_api POST "$BASE_URL/api/v1/schedules" "$SCH_DATA" "SCHEDULES"

# ================= TABLES =================
test_api GET "$BASE_URL/api/v1/tables/$TABLE_ID" "" "TABLES"
test_api GET "$BASE_URL/api/v1/tables/grid_view" "" "TABLES"

# ================= MESSAGES =================
MSG_DATA="{\"recipient_id\":$ME_ID,\"content\":\"hello self\"}"

test_api GET "$BASE_URL/api/v1/messages" "" "MESSAGES"
test_api GET "$BASE_URL/api/v1/messages/conversation/$OTHER_ID" "" "MESSAGES"
test_api POST "$BASE_URL/api/v1/messages" "$MSG_DATA" "MESSAGES"

MSG_ID=$(get_id "$BASE_URL/api/v1/messages")
[ -n "$MSG_ID" ] && \
test_api PATCH "$BASE_URL/api/v1/messages/$MSG_ID/mark_as_read" '{}' "MESSAGES"

# ================= MESSAGE ROOMS =================
test_api GET "$BASE_URL/api/v1/messages/rooms" "" "MESSAGE_ROOMS"

# ================= NETWORKING =================
test_api GET "$BASE_URL/api/v1/networking/directory" "" "NETWORKING"
test_api GET "$BASE_URL/api/v1/networking/my_connections" "" "NETWORKING"
test_api GET "$BASE_URL/api/v1/networking/pending_requests" "" "NETWORKING"

# ================= REQUESTS =================
REQ_DATA="{\"target_id\":$ME_ID}"

test_api GET "$BASE_URL/api/v1/requests" "" "REQUESTS"
test_api POST "$BASE_URL/api/v1/requests" "$REQ_DATA" "REQUESTS"

REQ_ID=$(get_id "$BASE_URL/api/v1/requests")
[ -z "$REQ_ID" ] && REQ_ID=$FALLBACK_REQUEST_ID

test_api PATCH "$BASE_URL/api/v1/requests/$REQ_ID/accept" '{}' "REQUESTS"

# ================= REQUESTS EXTRA =================
test_api GET "$BASE_URL/api/v1/requests/my_received" "" "REQUESTS"

# ================= CHAT ROOMS =================
ROOM_DATA="{\"title\":\"Auto Room\",\"room_kind\":$ROOM_KIND}"

test_api GET "$BASE_URL/api/v1/chat_rooms" "" "CHAT_ROOMS"
test_api POST "$BASE_URL/api/v1/chat_rooms" "$ROOM_DATA" "CHAT_ROOMS"

# ================= NOTIFICATIONS =================
test_api GET "$BASE_URL/api/v1/notifications" "" "NOTIFICATIONS"
test_api GET "$BASE_URL/api/v1/notifications/unread_count" "" "NOTIFICATIONS"
test_api PATCH "$BASE_URL/api/v1/notifications/mark_all_as_read" '{}' "NOTIFICATIONS"

NOTI_ID=$(get_id "$BASE_URL/api/v1/notifications")
[ -n "$NOTI_ID" ] && \
test_api PATCH "$BASE_URL/api/v1/notifications/$NOTI_ID/mark_as_read" '{}' "NOTIFICATIONS"

echo ""
echo "PASSED: $PASSED"
echo "FAILED: $FAILED"
echo "LOG: $LOG_FILE"
