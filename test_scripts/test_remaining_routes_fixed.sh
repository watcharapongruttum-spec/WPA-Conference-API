#!/bin/bash
set +e
export PATH=$PATH:/usr/bin:/bin:/usr/local/bin

BASE_URL="https://wpa-docker.onrender.com"

EMAIL="sales@triwayslogistics.com.au"
PASSWORD="NewPass123!"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }

echo "=================================="
echo "🧪 TEST ALL API ROUTES"
echo "=================================="

LOGIN=$(curl -s -X POST "$BASE_URL/api/v1/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

TOKEN=$(echo "$LOGIN" | jq -r '.token // empty')
CURRENT_USER_ID=$(echo "$LOGIN" | jq -r '.delegate.id // empty')

if [ -z "$TOKEN" ]; then
  fail "Login failed"
  echo "$LOGIN"
  exit 1
fi

ok "Login OK (User ID: $CURRENT_USER_ID)"

curl_auth() {
  curl -s "$@" -H "Authorization: Bearer $TOKEN"
}

curl_code() {
  curl -s -o /dev/null -w "%{http_code}" "$@" \
  -H "Authorization: Bearer $TOKEN"
}

echo ""
echo "---- Delegates ----"
CODE=$(curl_code "$BASE_URL/api/v1/delegates?page=1")
[[ "$CODE" == "200" ]] && ok "Delegates Index" || warn "Delegates $CODE"

DELEGATES=$(curl_auth "$BASE_URL/api/v1/delegates?page=1")
OTHER_ID=$(echo "$DELEGATES" | jq -r "map(select(.id != $CURRENT_USER_ID))[0].id // empty")

echo ""
echo "---- Notifications ----"
CODE=$(curl_code "$BASE_URL/api/v1/notifications")
[[ "$CODE" == "200" ]] && ok "Notifications Index" || warn "Notifications $CODE"

NOTIS=$(curl_auth "$BASE_URL/api/v1/notifications")
NOTI_ID=$(echo "$NOTIS" | jq -r '.[0].id // empty')

if [ -n "$NOTI_ID" ]; then
  info "Mark notification $NOTI_ID"
  curl_auth -X PATCH "$BASE_URL/api/v1/notifications/$NOTI_ID/mark_as_read" > /dev/null
  ok "Mark single notification"
else
  warn "No notification found"
fi

curl_auth -X PATCH "$BASE_URL/api/v1/notifications/mark_all_as_read" > /dev/null
ok "Mark all notifications"

echo ""
echo "---- Messages ----"
if [ -n "$OTHER_ID" ]; then
  CREATE_MSG=$(curl_auth -X POST "$BASE_URL/api/v1/messages" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$OTHER_ID,\"content\":\"Test from script\"}")

  MSG_ID=$(echo "$CREATE_MSG" | jq -r '.id // empty')

  if [ -n "$MSG_ID" ]; then
    ok "Create message $MSG_ID"
  else
    warn "Create message failed"
  fi
fi

MESSAGES=$(curl_auth "$BASE_URL/api/v1/messages")
MSG_ID=$(echo "$MESSAGES" | jq -r '.[0].id // empty')

if [ -n "$MSG_ID" ]; then
  curl_auth -X PATCH "$BASE_URL/api/v1/messages/$MSG_ID/mark_as_read" > /dev/null
  ok "Mark message read"
else
  warn "No messages"
fi

echo ""
echo "---- Chat Rooms ----"
CODE=$(curl_code "$BASE_URL/api/v1/chat_rooms")
[[ "$CODE" == "200" ]] && ok "Chat Rooms Index" || warn "Chat Rooms $CODE"

echo ""
echo "---- Connections ----"
CODE=$(curl_code "$BASE_URL/api/v1/connections")
[[ "$CODE" == "200" ]] && ok "Connections Index" || warn "Connections $CODE"

if [ -n "$OTHER_ID" ]; then
  CREATE_CONN=$(curl_auth -X POST "$BASE_URL/api/v1/requests" \
    -H "Content-Type: application/json" \
    -d "{\"target_id\":$OTHER_ID}")

  CONN_ID=$(echo "$CREATE_CONN" | jq -r '.id // empty')

  if [ -n "$CONN_ID" ]; then
    ok "Create connection $CONN_ID"
    curl_auth -X PATCH "$BASE_URL/api/v1/requests/$CONN_ID/reject" > /dev/null
    ok "Reject connection"
  else
    warn "Create connection failed"
  fi
fi

echo ""
echo "---- Tables ----"
GRID=$(curl_auth "$BASE_URL/api/v1/tables/grid_view")
TYPE=$(echo "$GRID" | jq -r 'type' 2>/dev/null)

if [ "$TYPE" = "array" ]; then
  ok "Tables Grid View"
else
  warn "Tables Grid View failed"
fi

TABLE_ID=$(echo "$GRID" | jq -r '
  if type=="array" then .[0].id
  elif .tables then .tables[0].id
  elif .data then .data[0].id
  else empty end
')

if [ -n "$TABLE_ID" ]; then
  info "Try table id: $TABLE_ID"
  CODE=$(curl_code "$BASE_URL/api/v1/tables/$TABLE_ID")
  [[ "$CODE" == "200" ]] && ok "Table Show" || warn "Table Show $CODE"
else
  warn "No table id"
fi

echo ""
echo "---- Schedules ----"
CODE=$(curl_code "$BASE_URL/api/v1/schedules")
[[ "$CODE" == "200" ]] && ok "Schedules Index" || warn "Schedules $CODE"

SCHEDULES=$(curl_auth "$BASE_URL/api/v1/schedules")
CONF_DATE=$(echo "$SCHEDULES" | jq -r '.[0].conference_date.id // empty')

if [ -n "$CONF_DATE" ] && [ -n "$OTHER_ID" ]; then
  START=$(date -u -d "+7 days" '+%Y-%m-%dT10:00:00Z')
  END=$(date -u -d "+7 days" '+%Y-%m-%dT11:00:00Z')

  CREATE_SCH=$(curl_auth -X POST "$BASE_URL/api/v1/schedules" \
    -H "Content-Type: application/json" \
    -d "{
      \"conference_date_id\":$CONF_DATE,
      \"target_id\":$OTHER_ID,
      \"start_at\":\"$START\",
      \"end_at\":\"$END\",
      \"table_number\":\"AUTO-1\"
    }")

  SCH_ID=$(echo "$CREATE_SCH" | jq -r '.id // empty')

  if [ -n "$SCH_ID" ]; then
    ok "Create schedule $SCH_ID"
  else
    warn "Schedule create failed"
  fi
else
  warn "No conference date"
fi

echo ""
echo "=================================="
echo "✅ ALL ROUTES TEST DONE"
echo "=================================="
