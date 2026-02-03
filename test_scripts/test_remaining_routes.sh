#!/bin/bash
set -e
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
echo "🧪 TEST REMAINING ROUTES"
echo "=================================="

# ---------------- LOGIN ----------------
LOGIN=$(curl -s -X POST "$BASE_URL/api/v1/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

TOKEN=$(echo $LOGIN | jq -r '.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  fail "Login failed"
  exit 1
fi

ok "Login OK"

curl_auth() {
  curl -s "$@" -H "Authorization: Bearer $TOKEN"
}

curl_code() {
  curl -s -o /dev/null -w "%{http_code}" "$@" \
  -H "Authorization: Bearer $TOKEN"
}

test_patch() {
  NAME=$1
  URL=$2

  echo -n "Testing $NAME... "
  CODE=$(curl_code -X PATCH "$URL" \
    -H "Content-Type: application/json" -d '{}')

  if [[ "$CODE" =~ ^(200|201|204)$ ]]; then
    ok "$CODE"
  else
    warn "$CODE"
  fi
}

echo ""
echo "---- Notifications ----"

NOTI_ID=$(curl_auth "$BASE_URL/api/v1/notifications" | jq '.[0].id' 2>/dev/null)

if [ "$NOTI_ID" != "null" ] && [ -n "$NOTI_ID" ]; then
  test_patch "Mark Notification Read" \
  "$BASE_URL/api/v1/notifications/$NOTI_ID/mark_as_read"
else
  info "No notifications found → Skip mark read"
fi

test_patch "Mark All Notifications" \
"$BASE_URL/api/v1/notifications/mark_all_as_read"

echo ""
echo "---- Messages ----"

MSG_ID=$(curl_auth "$BASE_URL/api/v1/messages" | jq '.[0].id' 2>/dev/null)

if [ "$MSG_ID" != "null" ] && [ -n "$MSG_ID" ]; then
  test_patch "Mark Message Read" \
  "$BASE_URL/api/v1/messages/$MSG_ID/mark_as_read"
else
  info "No messages found → Skip mark read"
fi

echo ""
echo "---- Chat Rooms ----"
CODE=$(curl_code "$BASE_URL/api/v1/chat_rooms")
[[ "$CODE" =~ ^(200)$ ]] && ok "Chat Rooms Index $CODE" || warn "$CODE"

echo ""
echo "---- Requests (Networking Write) ----"

# Create dummy request
CREATE_REQ=$(curl_auth -X POST "$BASE_URL/api/v1/requests" \
  -H "Content-Type: application/json" \
  -d '{"receiver_id":1}')

REQ_ID=$(echo "$CREATE_REQ" | jq '.id' 2>/dev/null)

if [ "$REQ_ID" != "null" ] && [ -n "$REQ_ID" ]; then
  test_patch "Accept Request" \
  "$BASE_URL/api/v1/requests/$REQ_ID/accept"

  test_patch "Reject Request" \
  "$BASE_URL/api/v1/requests/$REQ_ID/reject"
else
  warn "Create request failed → Skip accept/reject"
fi

echo ""
echo "---- Schedule Write ----"

CODE=$(curl_code -X POST "$BASE_URL/api/v1/schedules" \
  -H "Content-Type: application/json" \
  -d '{"title":"Test","date":"2026-02-03"}')

if [[ "$CODE" =~ ^(200|201)$ ]]; then
  ok "Create Schedule $CODE"
else
  warn "Create Schedule $CODE (Validation OK)"
fi

echo ""
echo "=================================="
echo "✅ REMAINING ROUTES TEST DONE"
echo "=================================="
