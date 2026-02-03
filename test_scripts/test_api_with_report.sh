#!/bin/bash
# test_api_with_report.sh
# ทดสอบ API และสร้างรายงาน HTML

BASE_URL="http://localhost:3000"
EMAIL="sales@triwayslogistics.com.au"
PASSWORD="NewPass123!"
OUTPUT_DIR="api_test_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$OUTPUT_DIR/api_report_$TIMESTAMP.html"

mkdir -p "$OUTPUT_DIR"

# เริ่มสร้าง HTML
cat > "$REPORT_FILE" << 'HTML_START'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>API Test Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', system-ui, sans-serif; 
            background: #0f172a; 
            color: #e2e8f0; 
            padding: 20px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 { 
            font-size: 2.5rem; 
            margin-bottom: 10px; 
            background: linear-gradient(135deg, #3b82f6, #8b5cf6);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .meta { color: #94a3b8; margin-bottom: 30px; font-size: 0.9rem; }
        .test-section { 
            background: #1e293b; 
            border-radius: 12px; 
            padding: 20px; 
            margin-bottom: 20px;
            border: 1px solid #334155;
        }
        .section-title { 
            font-size: 1.3rem; 
            color: #60a5fa; 
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .api-test { 
            background: #0f172a; 
            border-radius: 8px; 
            padding: 15px; 
            margin-bottom: 15px;
            border-left: 4px solid #3b82f6;
        }
        .api-name { 
            font-size: 1.1rem; 
            font-weight: 600; 
            color: #f1f5f9;
            margin-bottom: 10px;
        }
        .request-box, .response-box {
            background: #020617;
            border-radius: 6px;
            padding: 12px;
            margin: 10px 0;
            border: 1px solid #334155;
        }
        .box-title {
            font-size: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            color: #94a3b8;
            margin-bottom: 8px;
            font-weight: 600;
        }
        .method {
            display: inline-block;
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 0.75rem;
            font-weight: 700;
            margin-right: 8px;
        }
        .GET { background: #22c55e; color: white; }
        .POST { background: #3b82f6; color: white; }
        .PATCH { background: #f59e0b; color: white; }
        .DELETE { background: #ef4444; color: white; }
        .status {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 4px;
            font-weight: 600;
            font-size: 0.85rem;
        }
        .status-200 { background: #22c55e; color: white; }
        .status-201 { background: #22c55e; color: white; }
        .status-404 { background: #f59e0b; color: white; }
        .status-500 { background: #ef4444; color: white; }
        pre {
            background: #000;
            padding: 12px;
            border-radius: 4px;
            overflow-x: auto;
            font-size: 0.85rem;
            line-height: 1.5;
            color: #a5f3fc;
        }
        .info-line {
            color: #cbd5e1;
            font-size: 0.9rem;
            margin: 5px 0;
        }
        .url { color: #60a5fa; font-family: monospace; }
        .duration { color: #4ade80; }
        .summary {
            background: linear-gradient(135deg, #1e293b, #334155);
            padding: 20px;
            border-radius: 12px;
            margin-top: 30px;
            border: 1px solid #475569;
        }
        .summary h2 { color: #60a5fa; margin-bottom: 15px; }
        .stat { 
            display: inline-block; 
            margin-right: 20px;
            padding: 10px 15px;
            background: #0f172a;
            border-radius: 6px;
        }
        .stat-value { 
            font-size: 1.8rem; 
            font-weight: 700; 
            color: #f1f5f9;
        }
        .stat-label { 
            font-size: 0.8rem; 
            color: #94a3b8;
            text-transform: uppercase;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 API Test Report</h1>
        <div class="meta">
            Generated: <span id="timestamp"></span> | 
            Base URL: <span class="url">http://localhost:3000</span>
        </div>
HTML_START

echo "<script>document.getElementById('timestamp').textContent = new Date().toLocaleString();</script>" >> "$REPORT_FILE"

# ตัวนับ
total_tests=0
passed_tests=0
failed_tests=0

# ฟังก์ชัน Login
login() {
    echo "Logging in..." >&2
    
    local response=$(/usr/bin/curl -s -w "\n%{http_code}" -X POST "$BASE_URL/api/v1/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
    
    local body=$(echo "$response" | head -n -1)
    TOKEN=$(echo "$body" | jq -r '.token' 2>/dev/null)
    
    if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
        echo "Login failed!" >&2
        exit 1
    fi
    
    echo "Login successful!" >&2
}

# ฟังก์ชันทดสอบ API
test_api() {
    local section_name=$1
    local api_name=$2
    local method=$3
    local endpoint=$4
    local data=$5
    
    total_tests=$((total_tests + 1))
    
    local url="$BASE_URL$endpoint"
    
    echo "Testing: $api_name..." >&2
    
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
    esac
    
    end_time=$(date +%s%3N)
    duration=$((end_time - start_time))
    
    body=$(echo "$response" | head -n -1)
    status=$(echo "$response" | tail -n 1)
    
    # นับผลลัพธ์
    if [[ "$status" =~ ^(200|201|204)$ ]]; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
    
    # สร้าง HTML
    cat >> "$REPORT_FILE" << HTML_TEST
        <div class="api-test">
            <div class="api-name">
                <span class="method $method">$method</span>
                $api_name
            </div>
            
            <div class="request-box">
                <div class="box-title">📤 Request</div>
                <div class="info-line">URL: <span class="url">$endpoint</span></div>
HTML_TEST

    if [ ! -z "$data" ]; then
        echo "<pre>$(echo "$data" | jq '.' 2>/dev/null || echo "$data")</pre>" >> "$REPORT_FILE"
    fi

    cat >> "$REPORT_FILE" << HTML_RESPONSE
            </div>
            
            <div class="response-box">
                <div class="box-title">📥 Response</div>
                <div class="info-line">
                    Status: <span class="status status-$status">$status</span> | 
                    Duration: <span class="duration">${duration}ms</span>
                </div>
HTML_RESPONSE

    if [ ! -z "$body" ]; then
        formatted_body=$(echo "$body" | jq '.' 2>/dev/null || echo "$body")
        echo "<pre>$(echo "$formatted_body" | head -30)</pre>" >> "$REPORT_FILE"
        
        # ถ้า response ยาวเกิน 30 บรรทัด
        lines=$(echo "$formatted_body" | wc -l)
        if [ $lines -gt 30 ]; then
            echo "<div class='info-line' style='color: #94a3b8;'>... truncated ($lines lines total)</div>" >> "$REPORT_FILE"
        fi
    fi

    echo "            </div>" >> "$REPORT_FILE"
    echo "        </div>" >> "$REPORT_FILE"
}

# เริ่มสร้างส่วน section
start_section() {
    local title=$1
    cat >> "$REPORT_FILE" << HTML_SECTION
        <div class="test-section">
            <div class="section-title">$title</div>
HTML_SECTION
}

end_section() {
    echo "        </div>" >> "$REPORT_FILE"
}

# เริ่มทดสอบ
echo "Starting API tests..." >&2
login

# ========== AUTHENTICATION ==========
start_section "🔐 Authentication"
test_api "auth" "Login" "POST" "/api/v1/login" "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}"
end_section

# ========== NETWORKING ==========
start_section "🌐 Networking APIs"
test_api "networking" "Get Directory" "GET" "/api/v1/networking/directory" ""
test_api "networking" "Get My Connections" "GET" "/api/v1/networking/my_connections" ""
test_api "networking" "Get Pending Requests" "GET" "/api/v1/networking/pending_requests" ""
end_section

# ========== PROFILE ==========
start_section "👤 Profile APIs"
test_api "profile" "Get Profile" "GET" "/api/v1/profile" ""
test_api "profile" "Get Delegates" "GET" "/api/v1/delegates" ""
test_api "profile" "Search Delegates" "GET" "/api/v1/delegates/search?q=test" ""
end_section

# ========== MESSAGES ==========
start_section "💬 Message APIs"
test_api "messages" "Get Messages" "GET" "/api/v1/messages" ""
test_api "messages" "Get Conversation" "GET" "/api/v1/messages/conversation/1" ""
end_section

# ========== NOTIFICATIONS ==========
start_section "🔔 Notification APIs"
test_api "notifications" "Get Notifications" "GET" "/api/v1/notifications" ""
test_api "notifications" "Get Unread Count" "GET" "/api/v1/notifications/unread_count" ""
end_section

# ========== SCHEDULES ==========
start_section "📅 Schedule APIs"
test_api "schedules" "Get Schedules" "GET" "/api/v1/schedules" ""
test_api "schedules" "Get My Schedule" "GET" "/api/v1/schedules/my_schedule" ""
end_section

# ========== TABLES ==========
start_section "🪑 Table APIs"
test_api "tables" "Get Grid View" "GET" "/api/v1/tables/grid_view" ""
end_section

# ========== REQUESTS ==========
start_section "📨 Connection Request APIs"
test_api "requests" "Get Requests" "GET" "/api/v1/requests" ""
end_section

# ========== CHAT ROOMS ==========
start_section "💭 Chat Room APIs"
test_api "chat" "Get Chat Rooms" "GET" "/api/v1/chat_rooms" ""
end_section

# สรุปผล
cat >> "$REPORT_FILE" << HTML_SUMMARY
        <div class="summary">
            <h2>📊 Test Summary</h2>
            <div class="stat">
                <div class="stat-value">$total_tests</div>
                <div class="stat-label">Total Tests</div>
            </div>
            <div class="stat" style="border-left: 3px solid #22c55e;">
                <div class="stat-value" style="color: #22c55e;">$passed_tests</div>
                <div class="stat-label">Passed</div>
            </div>
            <div class="stat" style="border-left: 3px solid #ef4444;">
                <div class="stat-value" style="color: #ef4444;">$failed_tests</div>
                <div class="stat-label">Failed</div>
            </div>
        </div>
    </div>
</body>
</html>
HTML_SUMMARY

echo ""
echo "✅ Report generated: $REPORT_FILE"
echo "📊 Total: $total_tests | Passed: $passed_tests | Failed: $failed_tests"
echo ""
echo "Open the report with:"
echo "  firefox $REPORT_FILE"
echo "  or"
echo "  google-chrome $REPORT_FILE"
