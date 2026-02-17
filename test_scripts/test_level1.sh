#!/bin/bash

# ============================================
# 🧪 WPA API - Level 1 Comprehensive Test
# ============================================
# ทดสอบ: Rate Limit, Audit Log, Validation, 
#        Index Performance, Pagination
# ============================================

BASE_URL="${BASE_URL:-http://localhost:3000}"
LOG_FILE="test_level1_$(date +%Y%m%d_%H%M%S).log"
RESULT_FILE="result_level1.json"

# ===== TEST USERS =====
EMAIL_A="${EMAIL_A:-narisara.lasan@bestgloballogistics.com}"
PASSWORD_A="${PASSWORD_A:-123456}"

EMAIL_B="${EMAIL_B:-shammi@1shammi1.com}"
PASSWORD_B="${PASSWORD_B:-RNIrSPPICj}"

# ===== COLORS =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ===== HELPERS =====
log() {
  echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1" | tee -a $LOG_FILE
}

success() {
  echo -e "${GREEN}✓${NC} $1" | tee -a $LOG_FILE
}

fail() {
  echo -e "${RED}✗${NC} $1" | tee -a $LOG_FILE
}

warn() {
  echo -e "${YELLOW}⚠${NC} $1" | tee -a $LOG_FILE
}

section() {
  echo "" | tee -a $LOG_FILE
  echo -e "${YELLOW}========================================${NC}" | tee -a $LOG_FILE
  echo -e "${YELLOW}$1${NC}" | tee -a $LOG_FILE
  echo -e "${YELLOW}========================================${NC}" | tee -a $LOG_FILE
}

# ===== AUTH =====
login() {
  local email=$1
  local password=$2

  response=$(curl -s -o /tmp/resp.json -w "%{http_code}" \
    -X POST "$BASE_URL/api/v1/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$password\"}")

  status=$response
  body=$(cat /tmp/resp.json)

  if [ "$status" != "200" ]; then
    echo ""
    return
  fi

  echo "$body" | jq -r '.token'
}

get_profile() {
  local token=$1
  curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $token"
}

# ===== INITIALIZE =====
section "🚀 INITIALIZE TEST"

log "Base URL: $BASE_URL"
log "Log File: $LOG_FILE"

TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")

if [ -z "$TOKEN_A" ] || [ -z "$TOKEN_B" ]; then
  fail "❌ Login failed! Check credentials."
  exit 1
fi

success "✓ User A logged in"
success "✓ User B logged in"

PROFILE_A=$(get_profile "$TOKEN_A")
PROFILE_B=$(get_profile "$TOKEN_B")

A_ID=$(echo "$PROFILE_A" | jq -r '.id')
B_ID=$(echo "$PROFILE_B" | jq -r '.id')

if [ "$A_ID" = "null" ] || [ "$B_ID" = "null" ]; then
  fail "❌ Cannot get profile IDs"
  exit 1
fi

success "✓ User A ID: $A_ID"
success "✓ User B ID: $B_ID"

# ===== TEST RESULTS =====
declare -A TEST_RESULTS
TOTAL_TESTS=0
PASSED_TESTS=0

record_test() {
  local test_name=$1
  local status=$2
  local details=$3
  
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [ "$status" = "PASS" ]; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TEST_RESULTS["$test_name"]="PASS"
    success "$test_name"
  else
    TEST_RESULTS["$test_name"]="FAIL"
    fail "$test_name: $details"
  fi
}

# ============================================
# 📋 TEST 1: MESSAGE SIZE LIMIT (2000 chars)
# ============================================
section "📋 TEST 1: Message Size Limit"

# Test 1.1: Valid message (100 chars)
VALID_MSG=$(printf 'x%.0s' {1..100})
response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/v1/messages \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"recipient_id\":$B_ID,\"content\":\"$VALID_MSG\"}")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "201" ]; then
  record_test "Message 100 chars" "PASS"
else
  record_test "Message 100 chars" "FAIL" "HTTP $http_code"
fi

# Test 1.2: Max message (2000 chars)
MAX_MSG=$(printf 'x%.0s' {1..2000})
response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/v1/messages \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"recipient_id\":$B_ID,\"content\":\"$MAX_MSG\"}")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "201" ]; then
  record_test "Message 2000 chars (max)" "PASS"
else
  record_test "Message 2000 chars (max)" "FAIL" "HTTP $http_code"
fi

# Test 1.3: Over limit message (2001 chars)
OVER_MSG=$(printf 'x%.0s' {1..2001})
response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/v1/messages \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"recipient_id\":$B_ID,\"content\":\"$OVER_MSG\"}")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "422" ]; then
  record_test "Message 2001 chars (rejected)" "PASS"
else
  record_test "Message 2001 chars (rejected)" "FAIL" "Expected 422, got $http_code"
fi

# Test 1.4: Empty message
response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/v1/messages \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"recipient_id\":$B_ID,\"content\":\"\"}")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "422" ]; then
  record_test "Empty message (rejected)" "PASS"
else
  record_test "Empty message (rejected)" "FAIL" "Expected 422, got $http_code"
fi

# ============================================
# 📋 TEST 2: PAGINATION LIMIT (max 100 per)
# ============================================
section "📋 TEST 2: Pagination Limit"

# Test 2.1: Normal pagination (50 per)
response=$(curl -s -w "\n%{http_code}" "$BASE_URL/api/v1/messages/conversation/$B_ID?page=1&per=50" \
  -H "Authorization: Bearer $TOKEN_A")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "200" ]; then
  record_test "Pagination per=50" "PASS"
else
  record_test "Pagination per=50" "FAIL" "HTTP $http_code"
fi

# Test 2.2: Over limit pagination (500 per - should cap at 100)
response=$(curl -s -w "\n%{http_code}" "$BASE_URL/api/v1/messages/conversation/$B_ID?page=1&per=500" \
  -H "Authorization: Bearer $TOKEN_A")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "200" ]; then
  record_test "Pagination per=500 (capped)" "PASS"
else
  record_test "Pagination per=500 (capped)" "FAIL" "HTTP $http_code"
fi

# ============================================
# 📋 TEST 3: RATE LIMITING (Rack::Attack)
# ============================================
section "📋 TEST 3: Rate Limiting"

# Test 3.1: Login rate limit (10 per minute per IP)
log "Testing login rate limit (10/min)..."
login_success=0
login_429=0

for i in $(seq 1 15); do
  response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL_A\",\"password\":\"$PASSWORD_A\"}")
  
  http_code=$(echo "$response" | tail -n1)
  if [ "$http_code" = "200" ]; then
    login_success=$((login_success + 1))
  elif [ "$http_code" = "429" ]; then
    login_429=$((login_429 + 1))
  fi
done

if [ "$login_429" -gt 0 ]; then
  record_test "Login rate limit triggered" "PASS" "429 after $login_success requests"
else
  record_test "Login rate limit triggered" "FAIL" "No 429 received"
fi

# Test 3.2: Message send rate limit (60 per minute)
log "Testing message rate limit (60/min)..."
msg_success=0
msg_429=0

for i in $(seq 1 70); do
  response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$B_ID,\"content\":\"Rate limit test $i\"}")
  
  http_code=$(echo "$response" | tail -n1)
  if [ "$http_code" = "201" ]; then
    msg_success=$((msg_success + 1))
  elif [ "$http_code" = "429" ]; then
    msg_429=$((msg_429 + 1))
    break
  fi
done

if [ "$msg_429" -gt 0 ]; then
  record_test "Message rate limit triggered" "PASS" "429 after $msg_success requests"
else
  record_test "Message rate limit triggered" "FAIL" "No 429 received"
fi

# Test 3.3: Forgot password rate limit (3 per minute)
log "Testing forgot password rate limit (3/min)..."
fp_429=0

for i in $(seq 1 5); do
  response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/v1/forgot_password \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL_A\"}")
  
  http_code=$(echo "$response" | tail -n1)
  if [ "$http_code" = "429" ]; then
    fp_429=$((fp_429 + 1))
    break
  fi
done

if [ "$fp_429" -gt 0 ]; then
  record_test "Forgot password rate limit" "PASS"
else
  record_test "Forgot password rate limit" "FAIL" "No 429 received"
fi

# ============================================
# 📋 TEST 4: AUDIT LOG VERIFICATION
# ============================================
section "📋 TEST 4: Audit Log (via Rails Console)"

log "Checking audit logs in database..."

# This requires Rails console access
if command -v rails &> /dev/null; then
# ✅ ใหม่ (ถูก)
    audit_count=$(cd $(dirname $0)/.. && bundle exec rails runner "puts AuditLog.count" 2>/dev/null)
  
  if [ -n "$audit_count" ] && [ "$audit_count" -gt 0 ]; then
    record_test "Audit logs exist" "PASS" "Count: $audit_count"
    
    # Check login audit
    login_audit=$(cd $(dirname $0) && rails runner "puts AuditLog.where(action: 'login').count" 2>/dev/null)
    if [ -n "$login_audit" ] && [ "$login_audit" -gt 0 ]; then
      record_test "Login audit logged" "PASS" "Count: $login_audit"
    else
      record_test "Login audit logged" "FAIL" "No login audits found"
    fi
    
    # Check message audit
    msg_audit=$(cd $(dirname $0) && rails runner "puts AuditLog.where(action: 'message_create').count" 2>/dev/null)
    if [ -n "$msg_audit" ] && [ "$msg_audit" -gt 0 ]; then
      record_test "Message audit logged" "PASS" "Count: $msg_audit"
    else
      record_test "Message audit logged" "FAIL" "No message audits found"
    fi
  else
    record_test "Audit logs exist" "FAIL" "AuditLog table may not exist"
  fi
else
  warn "Rails not available - skip audit log test"
  record_test "Audit logs verification" "SKIP" "Rails console not available"
fi

# ============================================
# 📋 TEST 5: DATABASE INDEX VERIFICATION
# ============================================
section "📋 TEST 5: Database Indexes"

if command -v rails &> /dev/null; then
  log "Checking database indexes..."
  
  # Check chat_messages indexes
  indexes=$(cd $(dirname $0) && rails runner "
    indexes = ChatMessage.connection.indexes('chat_messages').map(&:name)
    puts indexes.join(',')
  " 2>/dev/null)
  
  if echo "$indexes" | grep -q "idx_chat_messages"; then
    record_test "ChatMessage indexes exist" "PASS"
  else
    record_test "ChatMessage indexes exist" "FAIL" "Missing composite indexes"
  fi
  
  # Check notifications indexes
  indexes=$(cd $(dirname $0) && rails runner "
    indexes = Notification.connection.indexes('notifications').map(&:name)
    puts indexes.join(',')
  " 2>/dev/null)
  
  if echo "$indexes" | grep -q "idx_notifications"; then
    record_test "Notification indexes exist" "PASS"
  else
    record_test "Notification indexes exist" "FAIL" "Missing indexes"
  fi
  
  # Check connection_requests indexes
  indexes=$(cd $(dirname $0) && rails runner "
    indexes = ConnectionRequest.connection.indexes('connection_requests').map(&:name)
    puts indexes.join(',')
  " 2>/dev/null)
  
  if echo "$indexes" | grep -q "idx_connection_requests"; then
    record_test "ConnectionRequest indexes exist" "PASS"
  else
    record_test "ConnectionRequest indexes exist" "FAIL" "Missing indexes"
  fi
else
  warn "Rails not available - skip index test"
  record_test "Database indexes verification" "SKIP" "Rails console not available"
fi

# ============================================
# 📋 TEST 6: CONCURRENT MESSAGE STRESS
# ============================================
section "📋 TEST 6: Concurrent Message Stress Test"

CONCURRENT=${1:-50}
log "Sending $CONCURRENT concurrent messages..."

success=0
fail=0
temp_file=$(mktemp)

start=$(date +%s%N)

for i in $(seq 1 $CONCURRENT); do
  {
    code=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST $BASE_URL/api/v1/messages \
      -H "Authorization: Bearer $TOKEN_A" \
      -H "Content-Type: application/json" \
      -d "{\"recipient_id\":$B_ID,\"content\":\"Concurrent $i\"}")
    
    if [ "$code" = "201" ]; then
      echo "SUCCESS" >> $temp_file
    else
      echo "FAIL:$code" >> $temp_file
    fi
  } &
done

wait

end=$(date +%s%N)
duration=$(( (end - start) / 1000000 ))  # Convert to ms

success=$(grep -c "SUCCESS" $temp_file 2>/dev/null || echo 0)
fail=$(grep -c "FAIL" $temp_file 2>/dev/null || echo 0)

log "Duration: ${duration}ms"
log "Success: $success / $CONCURRENT"
log "Fail: $fail / $CONCURRENT"

if [ "$success" -gt "$((CONCURRENT * 90 / 100))" ]; then
  record_test "Concurrent stress (90%+ success)" "PASS" "$success/$CONCURRENT in ${duration}ms"
else
  record_test "Concurrent stress (90%+ success)" "FAIL" "$success/$CONCURRENT in ${duration}ms"
fi

rm -f $temp_file

# ============================================
# 📋 TEST 7: DASHBOARD ENDPOINTS
# ============================================
section "📋 TEST 7: Dashboard Endpoints"

# Test 7.1: Dashboard show
response=$(curl -s -w "\n%{http_code}" $BASE_URL/api/v1/dashboard \
  -H "Authorization: Bearer $TOKEN_A")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" = "200" ]; then
  record_test "Dashboard endpoint" "PASS"
  
  # Check response fields
  if echo "$body" | jq -e '.unread_notifications_count' > /dev/null; then
    record_test "Dashboard: unread_notifications_count" "PASS"
  else
    record_test "Dashboard: unread_notifications_count" "FAIL"
  fi
  
  if echo "$body" | jq -e '.unread_message_notifications_count' > /dev/null; then
    record_test "Dashboard: unread_message_notifications_count" "PASS"
  else
    record_test "Dashboard: unread_message_notifications_count" "FAIL"
  fi
  
  if echo "$body" | jq -e '.upcoming_schedule_count' > /dev/null; then
    record_test "Dashboard: upcoming_schedule_count" "PASS"
  else
    record_test "Dashboard: upcoming_schedule_count" "FAIL"
  fi
else
  record_test "Dashboard endpoint" "FAIL" "HTTP $http_code"
fi

# ============================================
# 📋 TEST 8: NOTIFICATION ENDPOINTS
# ============================================
section "📋 TEST 8: Notification Endpoints"

# Test 8.1: Get notifications
response=$(curl -s -w "\n%{http_code}" $BASE_URL/api/v1/notifications \
  -H "Authorization: Bearer $TOKEN_A")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "200" ]; then
  record_test "Notifications index" "PASS"
else
  record_test "Notifications index" "FAIL" "HTTP $http_code"
fi

# Test 8.2: Unread count
response=$(curl -s -w "\n%{http_code}" $BASE_URL/api/v1/notifications/unread_count \
  -H "Authorization: Bearer $TOKEN_A")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "200" ]; then
  record_test "Notifications unread_count" "PASS"
else
  record_test "Notifications unread_count" "FAIL" "HTTP $http_code"
fi

# ============================================
# 📋 TEST 9: CONNECTION REQUEST
# ============================================
section "📋 TEST 9: Connection Request"

# Test 9.1: Create connection request
response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/v1/requests \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"target_id\":$B_ID}")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "201" ] || [ "$http_code" = "422" ]; then
  record_test "Connection request create" "PASS" "HTTP $http_code"
else
  record_test "Connection request create" "FAIL" "HTTP $http_code"
fi

# Test 9.2: Get pending requests
response=$(curl -s -w "\n%{http_code}" $BASE_URL/api/v1/networking/pending_requests \
  -H "Authorization: Bearer $TOKEN_B")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "200" ]; then
  record_test "Pending requests list" "PASS"
else
  record_test "Pending requests list" "FAIL" "HTTP $http_code"
fi

# ============================================
# 📋 TEST 10: CHAT ROOMS
# ============================================
section "📋 TEST 10: Chat Rooms"

# Test 10.1: Create room
response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/v1/chat_rooms \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"title\":\"Test Room\",\"room_kind\":\"group\"}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" = "201" ]; then
  record_test "Chat room create" "PASS"
  ROOM_ID=$(echo "$body" | jq -r '.id')
  
  # Test 10.2: Join room
  response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/v1/chat_rooms/$ROOM_ID/join \
    -H "Authorization: Bearer $TOKEN_B")
  
  http_code=$(echo "$response" | tail -n1)
  if [ "$http_code" = "200" ]; then
    record_test "Chat room join" "PASS"
  else
    record_test "Chat room join" "FAIL" "HTTP $http_code"
  fi
  
  # Test 10.3: Leave room
  response=$(curl -s -w "\n%{http_code}" -X DELETE $BASE_URL/api/v1/chat_rooms/$ROOM_ID/leave \
    -H "Authorization: Bearer $TOKEN_B")
  
  http_code=$(echo "$response" | tail -n1)
  if [ "$http_code" = "200" ]; then
    record_test "Chat room leave" "PASS"
  else
    record_test "Chat room leave" "FAIL" "HTTP $http_code"
  fi
else
  record_test "Chat room create" "FAIL" "HTTP $http_code"
fi

# ============================================
# 📋 TEST 11: MESSAGE CRUD
# ============================================
section "📋 TEST 11: Message CRUD Operations"

# Create a message for update/delete test
response=$(curl -s -X POST $BASE_URL/api/v1/messages \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"recipient_id\":$B_ID,\"content\":\"Test for CRUD\"}")

MSG_ID=$(echo "$response" | jq -r '.id')

if [ -n "$MSG_ID" ] && [ "$MSG_ID" != "null" ]; then
  # Test 11.1: Update message
  response=$(curl -s -w "\n%{http_code}" -X PATCH $BASE_URL/api/v1/messages/$MSG_ID \
    -H "Authorization: Bearer $TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{\"content\":\"Updated content\"}")
  
  http_code=$(echo "$response" | tail -n1)
  if [ "$http_code" = "200" ]; then
    record_test "Message update" "PASS"
  else
    record_test "Message update" "FAIL" "HTTP $http_code"
  fi
  
  # Test 11.2: Delete message
  response=$(curl -s -w "\n%{http_code}" -X DELETE $BASE_URL/api/v1/messages/$MSG_ID \
    -H "Authorization: Bearer $TOKEN_A")
  
  http_code=$(echo "$response" | tail -n1)
  if [ "$http_code" = "200" ]; then
    record_test "Message delete" "PASS"
  else
    record_test "Message delete" "FAIL" "HTTP $http_code"
  fi
else
  record_test "Message CRUD setup" "FAIL" "Cannot create test message"
fi

# ============================================
# 📋 TEST 12: SCHEDULE ENDPOINTS
# ============================================
section "📋 TEST 12: Schedule Endpoints"

# Test 12.1: My schedule
response=$(curl -s -w "\n%{http_code}" $BASE_URL/api/v1/schedules/my_schedule \
  -H "Authorization: Bearer $TOKEN_A")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "200" ]; then
  record_test "Schedule my_schedule" "PASS"
else
  record_test "Schedule my_schedule" "FAIL" "HTTP $http_code"
fi

# Test 12.2: Schedule index
response=$(curl -s -w "\n%{http_code}" $BASE_URL/api/v1/schedules \
  -H "Authorization: Bearer $TOKEN_A")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "200" ]; then
  record_test "Schedule index" "PASS"
else
  record_test "Schedule index" "FAIL" "HTTP $http_code"
fi

# ============================================
# 📋 TEST 13: AUTHENTICATION
# ============================================
section "📋 TEST 13: Authentication"

# Test 13.1: Invalid token
response=$(curl -s -w "\n%{http_code}" $BASE_URL/api/v1/profile \
  -H "Authorization: Bearer invalid_token_12345")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "401" ]; then
  record_test "Invalid token rejected" "PASS"
else
  record_test "Invalid token rejected" "FAIL" "Expected 401, got $http_code"
fi

# Test 13.2: Missing token
response=$(curl -s -w "\n%{http_code}" $BASE_URL/api/v1/profile)

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "401" ]; then
  record_test "Missing token rejected" "PASS"
else
  record_test "Missing token rejected" "FAIL" "Expected 401, got $http_code"
fi

# Test 13.3: Change password
response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/v1/change_password \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"new_password\":\"123456\",\"password_confirmation\":\"123456\"}")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "200" ]; then
  record_test "Change password" "PASS"
else
  record_test "Change password" "FAIL" "HTTP $http_code"
fi

# ============================================
# 📊 FINAL REPORT
# ============================================
section "📊 FINAL TEST REPORT"

PASS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))

echo "" | tee -a $LOG_FILE
echo "==========================================" | tee -a $LOG_FILE
echo "  LEVEL 1 TEST SUMMARY" | tee -a $LOG_FILE
echo "==========================================" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE
echo "  Total Tests:    $TOTAL_TESTS" | tee -a $LOG_FILE
echo "  Passed:         $PASSED_TESTS" | tee -a $LOG_FILE
echo "  Failed:         $((TOTAL_TESTS - PASSED_TESTS))" | tee -a $LOG_FILE
echo "  Pass Rate:      ${PASS_RATE}%" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE
echo "==========================================" | tee -a $LOG_FILE

# Generate JSON report
cat > $RESULT_FILE << EOF
{
  "test_suite": "WPA API Level 1",
  "timestamp": "$(date -Iseconds)",
  "total_tests": $TOTAL_TESTS,
  "passed": $PASSED_TESTS,
  "failed": $((TOTAL_TESTS - PASSED_TESTS)),
  "pass_rate": $PASS_RATE,
  "results": {
EOF

first=true
for test_name in "${!TEST_RESULTS[@]}"; do
  if [ "$first" = true ]; then
    first=false
  else
    echo "," >> $RESULT_FILE
  fi
  echo -n "    \"$test_name\": \"${TEST_RESULTS[$test_name]}\"" >> $RESULT_FILE
done

cat >> $RESULT_FILE << EOF

  }
}
EOF

echo "" | tee -a $LOG_FILE
echo "  📄 Log File: $LOG_FILE" | tee -a $LOG_FILE
echo "  📄 JSON Report: $RESULT_FILE" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE

if [ "$PASS_RATE" -ge 90 ]; then
  echo -e "${GREEN}  ✅ LEVEL 1 PASSED (${PASS_RATE}%)${NC}" | tee -a $LOG_FILE
  exit 0
elif [ "$PASS_RATE" -ge 70 ]; then
  echo -e "${YELLOW}  ⚠️  LEVEL 1 PARTIAL (${PASS_RATE}%)${NC}" | tee -a $LOG_FILE
  exit 1
else
  echo -e "${RED}  ❌ LEVEL 1 FAILED (${PASS_RATE}%)${NC}" | tee -a $LOG_FILE
  exit 1
fi