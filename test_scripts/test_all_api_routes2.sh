#!/bin/bash
set +e

BASE_URL="https://wpa-docker.onrender.com"
EMAIL="sales@triwayslogistics.com.au"
PASSWORD="NewPass123!"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

ok() { 
  echo -e "${GREEN}✅ $1${NC}"
  PASSED=$((PASSED+1))
}

fail() { 
  echo -e "${RED}❌ $1${NC}"
  FAILED=$((FAILED+1))
}

warn() { echo -e "${YELLOW}⚠️ $1${NC}"; }

# ---------- LOGIN ----------
login() {
  echo "🔐 Login..."
  RES=$(curl -s -X POST "$BASE_URL/api/v1/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

  TOKEN=$(echo "$RES" | jq -r '.token')

  if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
    fail "Login Failed"
  else
    ok "Login Success"
  fi
}

# ---------- CURL ----------
auth() {
  curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" "$@"
}

# ---------- TEST ----------
test_api() {
  METHOD=$1
  URL=$2
  DATA=$3

  echo -n "$METHOD $URL ... "

  case $METHOD in
    GET)
      CODE=$(auth "$URL")
      ;;
    POST)
      CODE=$(auth -X POST "$URL" \
        -H "Content-Type: application/json" -d "$DATA")
      ;;
    PATCH)
      CODE=$(auth -X PATCH "$URL" \
        -H "Content-Type: application/json" -d "$DATA")
      ;;
  esac

  if [[ "$CODE" =~ ^(200|201|204)$ ]]; then
    ok "$CODE"
  elif [[ "$CODE" =~ ^(404|422)$ ]]; then
    warn "$CODE"
    PASSED=$((PASSED+1))
  else
    fail "$CODE"
  fi
}

echo "=========================="
echo "🚀 FULL API TEST (NO STOP)"
echo "=========================="

login
echo ""

# PROFILE
test_api GET "$BASE_URL/api/v1/profile"

# DELEGATES
test_api GET "$BASE_URL/api/v1/delegates"
test_api GET "$BASE_URL/api/v1/delegates/search?q=test"
test_api GET "$BASE_URL/api/v1/delegates/1"
test_api GET "$BASE_URL/api/v1/delegates/1/qr_code"

# SCHEDULES
test_api GET "$BASE_URL/api/v1/schedules"
test_api GET "$BASE_URL/api/v1/schedules/my_schedule"
test_api POST "$BASE_URL/api/v1/schedules" '{}'

# TABLES
test_api GET "$BASE_URL/api/v1/tables/1"
test_api GET "$BASE_URL/api/v1/tables/grid_view"

# MESSAGES
test_api GET "$BASE_URL/api/v1/messages"
test_api GET "$BASE_URL/api/v1/messages/conversation/1"
test_api POST "$BASE_URL/api/v1/messages" '{"receiver_id":1,"content":"hi"}'
test_api PATCH "$BASE_URL/api/v1/messages/1/mark_as_read" '{}'

# NETWORKING
test_api GET "$BASE_URL/api/v1/networking/directory"
test_api GET "$BASE_URL/api/v1/networking/my_connections"
test_api GET "$BASE_URL/api/v1/networking/pending_requests"

# REQUESTS
test_api GET "$BASE_URL/api/v1/requests"
test_api POST "$BASE_URL/api/v1/requests" '{"receiver_id":1}'
test_api PATCH "$BASE_URL/api/v1/requests/1/accept" '{}'
test_api PATCH "$BASE_URL/api/v1/requests/1/reject" '{}'

# CHAT ROOMS
test_api GET "$BASE_URL/api/v1/chat_rooms"
test_api POST "$BASE_URL/api/v1/chat_rooms" '{"name":"test"}'

# NOTIFICATIONS
test_api GET "$BASE_URL/api/v1/notifications"
test_api GET "$BASE_URL/api/v1/notifications/unread_count"
test_api PATCH "$BASE_URL/api/v1/notifications/mark_all_as_read" '{}'
test_api PATCH "$BASE_URL/api/v1/notifications/1/mark_as_read" '{}'

echo ""
echo "=========================="
echo "📊 SUMMARY"
echo "=========================="
echo -e "PASSED: ${GREEN}$PASSED${NC}"
echo -e "FAILED: ${RED}$FAILED${NC}"
echo "=========================="
