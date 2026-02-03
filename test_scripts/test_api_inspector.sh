#!/bin/bash
# test_api_inspector.sh
# ทดสอบ API ทุกเส้นและแสดง Request/Response แบบละเอียด

set -e

BASE_URL="http://localhost:3000"
EMAIL="sales@triwayslogistics.com.au"
ORIGINAL_PASSWORD="NewPass123!"
TEMP_PASSWORD="Temp123456!3"

# สี
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ฟังก์ชันแสดงผล
ok() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; }
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
header() { echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"; echo -e "${CYAN}║ $1${NC}"; echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"; }
section() { echo -e "\n${MAGENTA}━━━ $1 ━━━${NC}\n"; }

# ฟังก์ชันแสดง Request
show_request() {
    local method=$1
    local url=$2
    local data=$3
    
    echo -e "${CYAN}┌─ REQUEST ─────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} Method: ${YELLOW}$method${NC}"
    echo -e "${CYAN}│${NC} URL:    ${YELLOW}$url${NC}"
    
    if [ ! -z "$TOKEN" ]; then
        echo -e "${CYAN}│${NC} Auth:   Bearer ${TOKEN:0:20}...${TOKEN: -10}"
    fi
    
    if [ ! -z "$data" ]; then
        echo -e "${CYAN}│${NC} Body:"
        echo "$data" | jq '.' 2>/dev/null | sed 's/^/│   /' || echo "$data" | sed 's/^/│   /'
    fi
    
    echo -e "${CYAN}└───────────────────────────────────────────────────────────────┘${NC}"
}

# ฟังก์ชันแสดง Response
show_response() {
    local status=$1
    local body=$2
    local duration=$3
    
    echo -e "${CYAN}┌─ RESPONSE ────────────────────────────────────────────────────┐${NC}"
    
    if [[ "$status" =~ ^(200|201|204)$ ]]; then
        echo -e "${CYAN}│${NC} Status: ${GREEN}$status OK${NC}"
    elif [[ "$status" =~ ^(404)$ ]]; then
        echo -e "${CYAN}│${NC} Status: ${YELLOW}$status NOT FOUND${NC}"
    else
        echo -e "${CYAN}│${NC} Status: ${RED}$status ERROR${NC}"
    fi
    
    if [ ! -z "$duration" ]; then
        echo -e "${CYAN}│${NC} Time:   ${duration}ms"
    fi
    
    echo -e "${CYAN}│${NC} Body:"
    
    if [ ! -z "$body" ]; then
        # ลองแปลง JSON
        if echo "$body" | jq '.' >/dev/null 2>&1; then
            echo "$body" | jq '.' | sed 's/^/│   /'
        else
            echo "$body" | sed 's/^/│   /'
        fi
    else
        echo -e "${CYAN}│${NC}   (empty)"
    fi
    
    echo -e "${CYAN}└───────────────────────────────────────────────────────────────┘${NC}"
}

# ฟังก์ชัน Login
login() {
    local password=$1
    local data="{\"email\":\"$EMAIL\",\"password\":\"$password\"}"
    
    show_request "POST" "$BASE_URL/api/v1/login" "$data"
    
    start_time=$(date +%s%3N)
    response=$(/usr/bin/curl -s -w "\n%{http_code}" -X POST "$BASE_URL/api/v1/login" \
        -H "Content-Type: application/json" \
        -d "$data")
    end_time=$(date +%s%3N)
    duration=$((end_time - start_time))
    
    body=$(echo "$response" | head -n -1)
    status=$(echo "$response" | tail -n 1)
    
    show_response "$status" "$body" "$duration"
    
    TOKEN=$(echo "$body" | jq -r '.token' 2>/dev/null)
    
    if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
        fail "Login failed"
        exit 1
    fi
    
    ok "Token extracted: ${TOKEN:0:20}...${TOKEN: -10}"
}

# ฟังก์ชันทดสอบ API
test_api() {
    local name=$1
    local method=$2
    local endpoint=$3
    local data=$4
    
    section "$name"
    
    local url="$BASE_URL$endpoint"
    show_request "$method" "$url" "$data"
    
    start_time=$(date +%s%3N)
    
    case $method in
        GET)
            response=$(/usr/bin/curl -s -w "\n%{http_code}" \
                -H "Authorization: Bearer $TOKEN" \
                "$url")
            ;;
        POST)
            response=$(/usr/bin/curl -s -w "\n%{http_code}" -X POST \
                -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: application/json" \
                -d "$data" \
                "$url")
            ;;
        PATCH)
            response=$(/usr/bin/curl -s -w "\n%{http_code}" -X PATCH \
                -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: application/json" \
                -d "$data" \
                "$url")
            ;;
        DELETE)
            response=$(/usr/bin/curl -s -w "\n%{http_code}" -X DELETE \
                -H "Authorization: Bearer $TOKEN" \
                "$url")
            ;;
    esac
    
    end_time=$(date +%s%3N)
    duration=$((end_time - start_time))
    
    body=$(echo "$response" | head -n -1)
    status=$(echo "$response" | tail -n 1)
    
    show_response "$status" "$body" "$duration"
    
    # แสดงสรุป
    if [[ "$status" =~ ^(200|201|204)$ ]]; then
        ok "$name - SUCCESS"
        
        # นับจำนวน records ถ้าเป็น array
        if echo "$body" | jq -e 'type == "array"' >/dev/null 2>&1; then
            count=$(echo "$body" | jq 'length')
            info "   → Returned $count record(s)"
        fi
    elif [[ "$status" =~ ^(404)$ ]]; then
        warn "$name - NOT FOUND (expected)"
    else
        fail "$name - FAILED"
    fi
    
    echo ""
}

# เริ่มทดสอบ
clear
header "🔍 API INSPECTOR - REQUEST/RESPONSE VIEWER"

# ========================================
# AUTHENTICATION
# ========================================
header "1️⃣  AUTHENTICATION FLOW"

section "Login with original password"
login "$ORIGINAL_PASSWORD"

section "Change password to TEMP"
test_api "Change Password" "POST" "/api/v1/change_password" \
    "{\"old_password\":\"$ORIGINAL_PASSWORD\",\"new_password\":\"$TEMP_PASSWORD\"}"

section "Login with TEMP password"
login "$TEMP_PASSWORD"

section "Change password back to ORIGINAL"
test_api "Revert Password" "POST" "/api/v1/change_password" \
    "{\"old_password\":\"$TEMP_PASSWORD\",\"new_password\":\"$ORIGINAL_PASSWORD\"}"

section "Final login"
login "$ORIGINAL_PASSWORD"

# ========================================
# NETWORKING APIs
# ========================================
header "2️⃣  NETWORKING APIs"

test_api "Get Directory" "GET" "/api/v1/networking/directory" ""
test_api "Get My Connections" "GET" "/api/v1/networking/my_connections" ""
test_api "Get Pending Requests" "GET" "/api/v1/networking/pending_requests" ""

# ========================================
# PROFILE APIs
# ========================================
header "3️⃣  PROFILE APIs"

test_api "Get Profile" "GET" "/api/v1/profile" ""
test_api "Get Delegates List" "GET" "/api/v1/delegates" ""
test_api "Search Delegates" "GET" "/api/v1/delegates/search?q=test" ""

# ========================================
# MESSAGE APIs
# ========================================
header "4️⃣  MESSAGE APIs"

test_api "Get Messages" "GET" "/api/v1/messages" ""
test_api "Get Conversation with Delegate 1" "GET" "/api/v1/messages/conversation/1" ""
test_api "Send Message" "POST" "/api/v1/messages" \
    "{\"recipient_id\":205,\"content\":\"Test message from API inspector\"}"

# ========================================
# NOTIFICATION APIs
# ========================================
header "5️⃣  NOTIFICATION APIs"

test_api "Get Notifications" "GET" "/api/v1/notifications" ""
test_api "Get Unread Count" "GET" "/api/v1/notifications/unread_count" ""

# ========================================
# SCHEDULE APIs
# ========================================
header "6️⃣  SCHEDULE APIs"

test_api "Get All Schedules" "GET" "/api/v1/schedules" ""
test_api "Get My Schedule" "GET" "/api/v1/schedules/my_schedule" ""

# ========================================
# TABLE APIs
# ========================================
header "7️⃣  TABLE APIs"

test_api "Get Table Grid View" "GET" "/api/v1/tables/grid_view" ""
test_api "Get Table Details (Table 1)" "GET" "/api/v1/tables/1" ""

# ========================================
# REQUEST APIs
# ========================================
header "8️⃣  CONNECTION REQUEST APIs"

test_api "Get All Requests" "GET" "/api/v1/requests" ""
test_api "Accept Request (ID 1)" "PATCH" "/api/v1/requests/1/accept" ""
test_api "Reject Request (ID 1)" "PATCH" "/api/v1/requests/1/reject" ""

# ========================================
# CHAT ROOM APIs
# ========================================
header "9️⃣  CHAT ROOM APIs"

test_api "Get Chat Rooms" "GET" "/api/v1/chat_rooms" ""

# ========================================
# สรุปผล
# ========================================
echo ""
header "✅ API INSPECTION COMPLETED"
echo ""
info "All API endpoints have been tested with detailed request/response logging"
echo ""
