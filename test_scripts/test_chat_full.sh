#!/bin/bash
set +e

BASE_URL="http://localhost:3000"

# ---------- USER A ----------
EMAIL_A="narisara.lasan@bestgloballogistics.com"
PASSWORD_A="123456"

# ---------- USER B ----------
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

  TOKEN=$(echo "$RESP" | jq -r '.token' 2>/dev/null)
  echo "$TOKEN"
}

request() {
  USER=$1
  TOKEN=$2
  METHOD=$3
  URL=$4
  DATA=$5

  echo ""
  debug "[$USER] $METHOD $URL"
  debug "TIME: $(date +%H:%M:%S)"

  if [ -n "$DATA" ]; then
    debug "BODY RAW:"
    echo "$DATA"
    debug "BODY JSON:"
    pretty_json "$DATA"
  fi

  if [ -z "$DATA" ]; then
    RESP=$(curl -s -w "\n%{http_code}" -X $METHOD $URL \
      -H "Authorization: Bearer $TOKEN")
  else
    RESP=$(curl -s -w "\n%{http_code}" -X $METHOD $URL \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "$DATA")
  fi

  BODY=$(echo "$RESP" | head -n -1)
  CODE=$(echo "$RESP" | tail -n1)

  debug "HTTP: $CODE"
  debug "RESPONSE RAW:"
  echo "$BODY"

  debug "RESPONSE JSON:"
  pretty_json "$BODY"

  LAST_CODE=$CODE
  LAST_BODY=$BODY
}

echo "================ CHAT DEBUG FULL ================"

# ---------- LOGIN A ----------
info "Login A"
TOKEN_A=$(login $EMAIL_A $PASSWORD_A)
if [ -z "$TOKEN_A" ] || [ "$TOKEN_A" = "null" ]; then
  fail "Login A Failed"
  exit 1
else
  pass "A OK"
fi



# ---------- GET A ID ----------
request "A" "$TOKEN_A" GET "$BASE_URL/api/v1/profile"
A_ID=$(echo "$LAST_BODY" | jq -r '.id')





# ---------- LOGIN B ----------
info "Login B"
TOKEN_B=$(login $EMAIL_B $PASSWORD_B)
if [ -z "$TOKEN_B" ] || [ "$TOKEN_B" = "null" ]; then
  fail "Login B Failed"
  exit 1
else
  pass "B OK"
fi

# ---------- GET B ID ----------
request "B" "$TOKEN_B" GET "$BASE_URL/api/v1/profile"
B_ID=$(echo "$LAST_BODY" | jq -r '.id')

# ---------- A SEND TO B ----------
info "A SEND → B"
request "A" "$TOKEN_A" POST "$BASE_URL/api/v1/messages" \
  "{\"recipient_id\":$B_ID,\"content\":\"hello from A\"}"

MSG_ID=$(echo "$LAST_BODY" | jq -r '.id')

# ---------- B READ CONVO ----------
info "B READ CONVERSATION"
request "B" "$TOKEN_B" GET "$BASE_URL/api/v1/messages/conversation/$A_ID"

# ---------- B READ ALL ----------
info "B READ ALL"
request "B" "$TOKEN_B" PATCH "$BASE_URL/api/v1/messages/read_all"

# ---------- A EDIT ----------
info "A EDIT MESSAGE"
request "A" "$TOKEN_A" PUT "$BASE_URL/api/v1/messages/$MSG_ID" \
  '{"content":"edited by A"}'

# ---------- A DELETE ----------
info "A DELETE MESSAGE"
request "A" "$TOKEN_A" DELETE "$BASE_URL/api/v1/messages/$MSG_ID"

# ---------- ROOM TEST ----------
info "CREATE ROOM"
request "A" "$TOKEN_A" POST "$BASE_URL/api/v1/chat_rooms" \
  '{"title":"DebugRoom","room_kind":"group"}'

ROOM_ID=$(echo "$LAST_BODY" | jq -r '.id')

info "DELETE ROOM"
request "A" "$TOKEN_A" DELETE "$BASE_URL/api/v1/chat_rooms/$ROOM_ID"

echo ""
pass "ALL DONE"
echo "================ END ================"
