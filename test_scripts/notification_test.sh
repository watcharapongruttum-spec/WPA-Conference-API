#!/bin/bash
set +e

BASE_URL="http://localhost:3000"

EMAIL_A="narisara.lasan@bestgloballogistics.com"
PASSWORD_A="123456"

EMAIL_B="shammi@1shammi1.com"
PASSWORD_B="RNIrSPPICj"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; }
info() { echo -e "${YELLOW}ℹ️ $1${NC}"; }
debug() { echo -e "${CYAN}🐞 $1${NC}"; }

pretty_json() {
  echo "$1" | jq . 2>/dev/null || echo "$1"
}

login() {
  EMAIL=$1
  PASSWORD=$2
  RESP=$(curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
  echo "$RESP" | jq -r '.token'
}

request() {
  USER=$1
  TOKEN=$2
  METHOD=$3
  URL=$4
  DATA=$5

  echo ""
  debug "[$USER] $METHOD $URL"

  if [ -z "$DATA" ]; then
    RESP=$(curl -s -w "\n%{http_code}" -X $METHOD $URL \
      -H "Authorization: Bearer $TOKEN")
  else
    RESP=$(curl -s -w "\n%{http_code}" -X $METHOD $URL \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "$DATA")
  fi

  LAST_BODY=$(echo "$RESP" | head -n -1)
  LAST_CODE=$(echo "$RESP" | tail -n1)

  pretty_json "$LAST_BODY"
}

dashboard() {
  USER=$1
  TOKEN=$2

  echo ""
  echo -e "${CYAN}📊 DASHBOARD [$USER]${NC}"

  RESP=$(curl -s $BASE_URL/api/v1/dashboard \
    -H "Authorization: Bearer $TOKEN")

  pretty_json "$RESP"

  SYS=$(echo "$RESP" | jq '.unread_notifications_count')
  MSG=$(echo "$RESP" | jq '.unread_message_notifications_count')
  PENDING=$(echo "$RESP" | jq '.pending_requests_count')
  CONN=$(echo "$RESP" | jq '.connections_count')

  echo -e "🔔 System: $SYS | 💬 Message: $MSG | 📩 Pending: $PENDING | 🤝 Conn: $CONN"
}

echo "========== FULL DASHBOARD TEST =========="

# ---------- LOGIN ----------
info "Login A"
TOKEN_A=$(login $EMAIL_A $PASSWORD_A)
[ "$TOKEN_A" = "null" ] && fail "Login A" && exit 1 || pass "A OK"

info "Login B"
TOKEN_B=$(login $EMAIL_B $PASSWORD_B)
[ "$TOKEN_B" = "null" ] && fail "Login B" && exit 1 || pass "B OK"

# ---------- PROFILE ----------
request "A" "$TOKEN_A" GET "$BASE_URL/api/v1/profile"
A_ID=$(echo "$LAST_BODY" | jq -r '.id')

request "B" "$TOKEN_B" GET "$BASE_URL/api/v1/profile"
B_ID=$(echo "$LAST_BODY" | jq -r '.id')

# ---------- INITIAL DASHBOARD ----------
info "INITIAL DASHBOARD"
dashboard "B" "$TOKEN_B"

# ---------- SEND MESSAGE ----------
info "A SEND MESSAGE → B"
request "A" "$TOKEN_A" POST "$BASE_URL/api/v1/messages" \
  "{\"recipient_id\":$B_ID,\"content\":\"hello dashboard test\"}"

info "DASHBOARD AFTER MESSAGE"
dashboard "B" "$TOKEN_B"

# ---------- MARK MESSAGE READ ----------
info "B MARK MESSAGE READ"
request "B" "$TOKEN_B" PATCH "$BASE_URL/api/v1/notifications/mark_all_as_read?type=message"

info "DASHBOARD AFTER MARK MESSAGE"
dashboard "B" "$TOKEN_B"

# ---------- SYSTEM NOTIFICATION ----------
info "⚠️ CREATE SYSTEM NOTIFICATION IN RAILS CONSOLE"
echo "Notification.create!(delegate_id: $B_ID, notification_type: 'admin_announce')"
read -p "Press enter after create..."

info "DASHBOARD AFTER SYSTEM"
dashboard "B" "$TOKEN_B"

# ---------- MARK SYSTEM ----------
info "B MARK SYSTEM READ"
request "B" "$TOKEN_B" PATCH "$BASE_URL/api/v1/notifications/mark_all_as_read?type=system"

info "DASHBOARD AFTER MARK SYSTEM"
dashboard "B" "$TOKEN_B"

# ---------- CONNECTION REQUEST ----------
info "A SEND CONNECTION REQUEST → B"
request "A" "$TOKEN_A" POST "$BASE_URL/api/v1/requests" \
  "{\"target_id\":$B_ID}"

info "DASHBOARD AFTER REQUEST"
dashboard "B" "$TOKEN_B"

# ---------- ACCEPT CONNECTION ----------
info "B CHECK RECEIVED REQUEST"
request "B" "$TOKEN_B" GET "$BASE_URL/api/v1/requests/my_received"

REQ_ID=$(echo "$LAST_BODY" | jq -r '.[0].id')

info "B ACCEPT CONNECTION"
request "B" "$TOKEN_B" PATCH "$BASE_URL/api/v1/requests/$REQ_ID/accept"

info "FINAL DASHBOARD"
dashboard "B" "$TOKEN_B"

pass "FULL TEST COMPLETE"
echo "========== END =========="
