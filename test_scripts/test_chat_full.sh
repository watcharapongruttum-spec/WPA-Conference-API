#!/bin/bash
set +e

BASE_URL="http://localhost:3000"
EMAIL="narisara.lasan@bestgloballogistics.com"
PASSWORD="123456"
RECIPIENT_ID=205

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; }
info() { echo -e "${YELLOW}ℹ️ $1${NC}"; }

request() {
  METHOD=$1
  URL=$2
  DATA=$3

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

  echo "HTTP: $CODE"
  echo "BODY: $BODY"
  echo ""

  LAST_CODE=$CODE
  LAST_BODY=$BODY
}

echo "================ CHAT TEST DEBUG ================"

# ---------------- LOGIN ----------------
echo "🔐 Login..."
LOGIN_RESP=$(curl -s $BASE_URL/api/v1/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

TOKEN=$(echo $LOGIN_RESP | jq -r '.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "$LOGIN_RESP"
  fail "Login Failed"
  exit 1
else
  pass "Login Success"
fi

# ---------------- SEED ----------------
echo ""
info "Seed Messages"
IDS=()

for i in 1 2 3
do
  request POST "$BASE_URL/api/v1/messages" \
    "{\"recipient_id\": $RECIPIENT_ID, \"content\": \"seed $i\"}"

  ID=$(echo $LAST_BODY | jq -r '.id')
  IDS+=($ID)
done

LAST_ID=${IDS[2]}
echo "Seeded IDs: ${IDS[@]}"

# ---------------- EDIT ----------------
echo ""
info "Edit Message ID=$LAST_ID"

request PUT "$BASE_URL/api/v1/messages/$LAST_ID" \
  '{"content":"edited message"}'

if [ "$LAST_CODE" = "200" ]; then
  pass "Edit OK"
else
  fail "Edit Failed"
fi

# ---------------- DELETE ----------------
echo ""
info "Delete Message"

request DELETE "$BASE_URL/api/v1/messages/$LAST_ID"

if [ "$LAST_CODE" = "200" ]; then
  pass "Delete OK"
else
  fail "Delete Failed"
fi

# ---------------- FILTER ----------------
echo ""
info "Conversation Filter"

request GET "$BASE_URL/api/v1/messages/conversation/$RECIPIENT_ID"

echo "$LAST_BODY" | grep -q "\"id\":$LAST_ID"
if [ $? -eq 0 ]; then
  fail "Deleted message still exists"
else
  pass "Filter OK"
fi

# ---------------- ROOM ----------------
echo ""
info "Create Room"

request POST "$BASE_URL/api/v1/chat_rooms" \
  '{"title":"TestRoom","room_kind":"group"}'

ROOM_ID=$(echo $LAST_BODY | jq -r '.id')

if [ "$LAST_CODE" = "201" ] || [ "$LAST_CODE" = "200" ]; then
  pass "Room Created"
else
  fail "Room Create Failed"
fi

echo ""
info "Delete Room"

request DELETE "$BASE_URL/api/v1/chat_rooms/$ROOM_ID"

if [ "$LAST_CODE" = "200" ]; then
  pass "Room Deleted"
else
  fail "Room Delete Failed"
fi

# ---------------- CLEANUP ----------------
echo ""
info "Cleanup Messages"

for ID in "${IDS[@]}"
do
  request DELETE "$BASE_URL/api/v1/messages/$ID"
done

pass "Cleanup Done"

echo "================ DONE ================"
