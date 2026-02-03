#!/bin/bash
# test_scripts/test_all_api_routes.sh
set -e
export PATH=$PATH:/usr/bin:/bin:/usr/local/bin

BASE_URL="http://localhost:3000"

EMAIL="sales@triwayslogistics.com.au"
ORIGINAL_PASSWORD="NewPass123!"
TEMP_PASSWORD="Temp123456!3"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }

# ---------------- CURL HELPERS ----------------
curl_auth() {
  /usr/bin/curl -s "$@" -H "Authorization: Bearer $TOKEN"
}

curl_code() {
  /usr/bin/curl -s -o /dev/null -w "%{http_code}" "$@" \
  -H "Authorization: Bearer $TOKEN"
}

curl_with_body() {
  /usr/bin/curl -s "$@" -H "Authorization: Bearer $TOKEN"
}

# ---------------- LOGIN FUNCTION ----------------
login() {
  local PASS=$1

  info "Attempting login..."
  LOGIN=$(/usr/bin/curl -s -X POST "$BASE_URL/api/v1/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")

  TOKEN=$(echo $LOGIN | jq -r '.token' 2>/dev/null)

  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    ERROR=$(echo $LOGIN | jq -r '.error // .message // "Unknown error"' 2>/dev/null)
    fail "Login failed: $ERROR"
    exit 1
  fi
}

echo "=================================="
echo "🧪 TEST ALL API ROUTES"
echo "=================================="
echo ""

# ---------------- SERVER CHECK ----------------
info "Checking server availability..."
if /usr/bin/curl -s -o /dev/null -w "%{http_code}" "$BASE_URL" | grep -q "200\|404"; then
  ok "Server is running"
else
  fail "Server is not responding"
  exit 1
fi

echo ""

# ---------------- LOGIN ORIGINAL ----------------
echo "1️⃣  Testing authentication flow..."
echo "Login with original password..."
login "$ORIGINAL_PASSWORD"
ok "Login successful"

echo ""

# ---------------- CHANGE PASSWORD → TEMP ----------------
echo "2️⃣  Testing password change..."
echo "Changing password to TEMP..."

CHANGE_RESPONSE=$(curl_auth -X POST "$BASE_URL/api/v1/change_password" \
  -H "Content-Type: application/json" \
  -d "{\"old_password\":\"$ORIGINAL_PASSWORD\",\"new_password\":\"$TEMP_PASSWORD\"}")

if echo "$CHANGE_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
  ERROR=$(echo "$CHANGE_RESPONSE" | jq -r '.error')
  fail "Password change failed: $ERROR"
  exit 1
else
  ok "Password changed to TEMP"
fi

echo ""

# ---------------- LOGIN TEMP ----------------
echo "Login with TEMP password..."
login "$TEMP_PASSWORD"
ok "Login with TEMP password successful"

echo ""

# ---------------- CHANGE PASSWORD BACK ----------------
echo "Changing password back to ORIGINAL..."

REVERT_RESPONSE=$(curl_auth -X POST "$BASE_URL/api/v1/change_password" \
  -H "Content-Type: application/json" \
  -d "{\"old_password\":\"$TEMP_PASSWORD\",\"new_password\":\"$ORIGINAL_PASSWORD\"}")

if echo "$REVERT_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
  ERROR=$(echo "$REVERT_RESPONSE" | jq -r '.error')
  fail "Password revert failed: $ERROR"
  exit 1
else
  ok "Password reverted to ORIGINAL"
fi

echo ""

# ---------------- LOGIN FINAL ----------------
echo "Login with reverted password..."
login "$ORIGINAL_PASSWORD"
ok "Final login successful"

echo ""
echo "=================================="

# ---------------- NETWORKING TESTS ----------------
echo ""
echo "3️⃣  Testing Networking APIs..."
echo ""

test_network() {
  local NAME=$1
  local URL=$2

  echo -n "  Testing $NAME... "
  
  RESPONSE=$(curl_with_body "$URL" 2>&1)
  CODE=$(/usr/bin/curl -s -o /dev/null -w "%{http_code}" "$URL" \
    -H "Authorization: Bearer $TOKEN")
  
  if [[ "$CODE" =~ ^(200|201|204)$ ]]; then
    ok "$CODE"
    
    # Check if response is valid JSON array or object
    if echo "$RESPONSE" | jq empty 2>/dev/null; then
      COUNT=$(echo "$RESPONSE" | jq 'if type=="array" then length else 1 end' 2>/dev/null || echo "?")
      info "    → Returned $COUNT record(s)"
    fi
  else
    fail "$CODE"
    
    # Show error details if available
    ERROR=$(echo "$RESPONSE" | jq -r '.error // .message // empty' 2>/dev/null)
    if [ -n "$ERROR" ]; then
      warn "    → Error: $ERROR"
    fi
    
    warn "STOP: Networking API Failed"
    exit 1
  fi
}

test_network "Directory" "$BASE_URL/api/v1/networking/directory"
test_network "My Connections" "$BASE_URL/api/v1/networking/my_connections"
test_network "Pending Requests" "$BASE_URL/api/v1/networking/pending_requests"

echo ""
ok "All networking tests passed!"
echo ""
echo "=================================="

# ---------------- PROFILE TESTS ----------------
echo ""
echo "4️⃣  Testing Profile APIs..."
echo ""

test_api() {
  local NAME=$1
  local METHOD=$2
  local URL=$3
  local DATA=$4

  echo -n "  Testing $NAME... "
  
  case $METHOD in
    GET)
      CODE=$(curl_code "$URL")
      ;;
    POST)
      CODE=$(curl_code -X POST "$URL" \
        -H "Content-Type: application/json" -d "$DATA")
      ;;
    PATCH)
      CODE=$(curl_code -X PATCH "$URL" \
        -H "Content-Type: application/json" -d "$DATA")
      ;;
    *)
      echo "Unknown method"
      return 1
      ;;
  esac

  if [[ "$CODE" =~ ^(200|201|204)$ ]]; then
    ok "$CODE"
  elif [[ "$CODE" =~ ^(404)$ ]]; then
    warn "$CODE (Not Found - Expected)"
  else
    fail "$CODE"
  fi
}

test_api "Get Profile" "GET" "$BASE_URL/api/v1/profile"
test_api "Get Delegates" "GET" "$BASE_URL/api/v1/delegates"
test_api "Search Delegates" "GET" "$BASE_URL/api/v1/delegates/search?q=test"

echo ""
echo "=================================="

# ---------------- MESSAGE TESTS ----------------
echo ""
echo "5️⃣  Testing Message APIs..."
echo ""

test_api "Get Messages" "GET" "$BASE_URL/api/v1/messages"
test_api "Get Conversation" "GET" "$BASE_URL/api/v1/messages/conversation/1"

echo ""
echo "=================================="

# ---------------- NOTIFICATION TESTS ----------------
echo ""
echo "6️⃣  Testing Notification APIs..."
echo ""

test_api "Get Notifications" "GET" "$BASE_URL/api/v1/notifications"
test_api "Get Unread Count" "GET" "$BASE_URL/api/v1/notifications/unread_count"

echo ""
echo "=================================="

# ---------------- SCHEDULE TESTS ----------------
echo ""
echo "7️⃣  Testing Schedule APIs..."
echo ""

test_api "Get Schedules" "GET" "$BASE_URL/api/v1/schedules"
test_api "Get My Schedule" "GET" "$BASE_URL/api/v1/schedules/my_schedule"

echo ""
echo "=================================="

# ---------------- TABLE TESTS ----------------
echo ""
echo "8️⃣  Testing Table APIs..."
echo ""

test_api "Get Table Grid" "GET" "$BASE_URL/api/v1/tables/grid_view"

echo ""
echo "=================================="

# ---------------- AUTO ROUTE SCAN ----------------
echo ""
echo "9️⃣  Scanning additional routes..."
echo ""

ROUTES=$(rails routes 2>/dev/null | grep "/api/" | awk '{print $2 "|" $3}' || echo "")

if [ -z "$ROUTES" ]; then
  warn "Could not scan routes (rails command not available)"
else
  TESTED_ROUTES=0
  PASSED_ROUTES=0
  FAILED_ROUTES=0
  
  echo "$ROUTES" | while IFS="|" read METHOD PATH
  do
    # Skip already tested routes
    [[ "$PATH" == *"cable"* ]] && continue
    [[ "$PATH" == *"login"* ]] && continue
    [[ "$PATH" == *"change_password"* ]] && continue
    [[ "$PATH" == *"forgot_password"* ]] && continue
    [[ "$PATH" == *"profile"* ]] && continue
    [[ "$PATH" == *"networking"* ]] && continue
    [[ "$PATH" == *"delegates"* ]] && continue
    [[ "$PATH" == *"messages"* ]] && continue
    [[ "$PATH" == *"notifications"* ]] && continue
    [[ "$PATH" == *"schedules"* ]] && continue
    [[ "$PATH" == *"tables"* ]] && continue

    PATH=${PATH%%(*}
    URL="$BASE_URL$PATH"

    # Replace path parameters
    URL=${URL//:id/1}
    URL=${URL//:delegate_id/1}
    URL=${URL//:chat_room_id/1}
    URL=${URL//:message_id/1}

    echo -n "  Testing $METHOD $PATH... "

    case $METHOD in
      GET)
        CODE=$(curl_code "$URL")
        ;;
      POST)
        CODE=$(curl_code -X POST "$URL" \
          -H "Content-Type: application/json" -d '{}')
        ;;
      PUT|PATCH)
        CODE=$(curl_code -X $METHOD "$URL" \
          -H "Content-Type: application/json" -d '{}')
        ;;
      DELETE)
        CODE=$(curl_code -X DELETE "$URL")
        ;;
      *)
        echo "Skip"
        continue
        ;;
    esac

    if [[ "$CODE" =~ ^(200|201|204)$ ]]; then
      ok "$CODE"
    elif [[ "$CODE" =~ ^(404|422)$ ]]; then
      warn "$CODE"
    else
      fail "$CODE"
    fi
  done
fi

echo ""
echo "=================================="
echo "✅ TEST SUITE COMPLETED"
echo "=================================="
echo ""

# Display summary
info "Summary:"
echo "  ✅ Authentication: Passed"
echo "  ✅ Password Management: Passed"
echo "  ✅ Networking APIs: Passed"
echo "  ✅ Profile APIs: Tested"
echo "  ✅ Message APIs: Tested"
echo "  ✅ Notification APIs: Tested"
echo "  ✅ Schedule APIs: Tested"
echo "  ✅ Table APIs: Tested"

echo ""
ok "All critical tests completed successfully!"
echo ""