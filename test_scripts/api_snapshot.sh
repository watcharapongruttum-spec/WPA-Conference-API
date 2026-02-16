#!/bin/bash
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

BASE_URL="http://localhost:3000"

EMAIL="shammi@1shammi1.com"
PASSWORD="RNIrSPPICj"

LOG_FILE="api_snapshot.log"

echo "API SNAPSHOT $(date)" > $LOG_FILE
echo "====================" >> $LOG_FILE

# -------- LOGIN --------
TOKEN=$(curl -s $BASE_URL/api/v1/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
  | jq -r '.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "LOGIN FAILED" >> $LOG_FILE
  exit 1
fi

AUTH_HEADER="Authorization: Bearer $TOKEN"

# -------- ENDPOINTS --------
ENDPOINTS="
profile
dashboard
delegates
delegates/search
schedules
schedules/my_schedule?year=2025
messages
messages/rooms
messages/unread_count
chat_rooms
networking/directory
notifications
leave_types
"

# -------- TEST --------
echo "$ENDPOINTS" | while read P
do
  [ -z "$P" ] && continue

  URL="$BASE_URL/api/v1/$P"

  RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    "$URL" \
    -H "$AUTH_HEADER")

  BODY=$(echo "$RESPONSE" | sed -n '1,/HTTP_STATUS:/p' | sed '$d')
  STATUS=$(echo "$RESPONSE" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')

  # ---- TRIM JSON ----
  SHORT=$(echo "$BODY" | jq -c '
    if type=="array" then .[:2]
    elif type=="object" then
      with_entries(select(.key | IN("id","name","status","title")))
    else .
    end
  ' 2>/dev/null)

  [ -z "$SHORT" ] && SHORT="$BODY"

  echo "[$(date +%H:%M:%S)] $P -> $STATUS" >> $LOG_FILE
  echo "$SHORT" >> $LOG_FILE
  echo "" >> $LOG_FILE

done
