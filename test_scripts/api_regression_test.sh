#!/bin/bash
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

BASE_URL="http://localhost:3000"

EMAIL="shammi@1shammi1.com"
PASSWORD="RNIrSPPICj"

LOG_FILE="api_regression_test.log"

echo "API REGRESSION TEST $(date)" > $LOG_FILE
echo "=============================" >> $LOG_FILE

# -------------------------
# LOGIN (JWT TEST)
# -------------------------
echo "---- LOGIN TEST ----" >> $LOG_FILE

LOGIN_RESPONSE=$(curl -s $BASE_URL/api/v1/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

TOKEN=$(echo $LOGIN_RESPONSE | jq -r '.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "❌ LOGIN FAILED" >> $LOG_FILE
  exit 1
fi

echo "✅ LOGIN SUCCESS" >> $LOG_FILE
AUTH_HEADER="Authorization: Bearer $TOKEN"

# -------------------------
# PROFILE (JWT Decode Test)
# -------------------------
PROFILE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "$BASE_URL/api/v1/profile" \
  -H "$AUTH_HEADER")

echo "Profile status: $PROFILE_STATUS (expect 200)" >> $LOG_FILE

# -------------------------
# STRONG PARAM TEST
# -------------------------
echo "" >> $LOG_FILE
echo "---- STRONG PARAM TEST ----" >> $LOG_FILE

INVALID_ROOM=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST "$BASE_URL/api/v1/chat_rooms" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"bad_param":"hacked"}')

STATUS=$(echo "$INVALID_ROOM" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
echo "Invalid room create status: $STATUS (expect 400/422)" >> $LOG_FILE

# -------------------------
# MESSAGE VALIDATION TEST
# -------------------------
echo "" >> $LOG_FILE
echo "---- MESSAGE VALIDATION ----" >> $LOG_FILE

BLANK_MSG=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST "$BASE_URL/api/v1/messages" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"recipient_id":2,"content":""}')

STATUS=$(echo "$BLANK_MSG" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
echo "Blank message status: $STATUS (expect 422)" >> $LOG_FILE

LONG_CONTENT=$(printf 'a%.0s' {1..2100})

LONG_MSG=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST "$BASE_URL/api/v1/messages" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{\"recipient_id\":2,\"content\":\"$LONG_CONTENT\"}")

STATUS=$(echo "$LONG_MSG" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
echo "Long message status: $STATUS (expect 422)" >> $LOG_FILE

# -------------------------
# BULK READ TEST
# -------------------------
echo "" >> $LOG_FILE
echo "---- BULK READ TEST ----" >> $LOG_FILE

READ_ALL=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST "$BASE_URL/api/v1/messages/read_all" \
  -H "$AUTH_HEADER")

STATUS=$(echo "$READ_ALL" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
echo "Read all status: $STATUS (expect 200)" >> $LOG_FILE

# -------------------------
# UNREAD COUNT
# -------------------------
UNREAD=$(curl -s "$BASE_URL/api/v1/messages/unread_count?sender_id=2" \
  -H "$AUTH_HEADER")

COUNT=$(echo "$UNREAD" | jq -r '.unread_count')
echo "Unread count after read_all: $COUNT (expect 0 or small number)" >> $LOG_FILE

# -------------------------
# NOTIFICATION STRUCTURE
# -------------------------
echo "" >> $LOG_FILE
echo "---- NOTIFICATION STRUCTURE ----" >> $LOG_FILE

NOTIFICATIONS=$(curl -s "$BASE_URL/api/v1/notifications" \
  -H "$AUTH_HEADER")

STRUCTURE=$(echo "$NOTIFICATIONS" | jq '.[0] | keys' 2>/dev/null)

echo "Notification keys:" >> $LOG_FILE
echo "$STRUCTURE" >> $LOG_FILE

# -------------------------
# NOTIFICATION PERFORMANCE TEST
# -------------------------
echo "" >> $LOG_FILE
echo "---- NOTIFICATION PERFORMANCE ----" >> $LOG_FILE

PERF=$(curl -w "%{time_total}" -o /dev/null -s \
  "$BASE_URL/api/v1/notifications" \
  -H "$AUTH_HEADER")

echo "Single request time: ${PERF}s" >> $LOG_FILE

LIMIT=0.10

awk -v perf="$PERF" -v limit="$LIMIT" 'BEGIN {
  if (perf > limit) {
    print "❌ PERFORMANCE SLOW (>" limit "s)"
  } else {
    print "✅ PERFORMANCE OK"
  }
}' >> $LOG_FILE

# -------------------------
# NOTIFICATION STRESS TEST (20x)
# -------------------------
echo "" >> $LOG_FILE
echo "---- NOTIFICATION STRESS TEST (20 requests) ----" >> $LOG_FILE

TOTAL=0

for i in {1..20}
do
  TIME=$(curl -w "%{time_total}" -o /dev/null -s \
    "$BASE_URL/api/v1/notifications" \
    -H "$AUTH_HEADER")

  echo "Request $i: $TIME s" >> $LOG_FILE
  TOTAL=$(awk "BEGIN {print $TOTAL + $TIME}")
done

AVG=$(awk "BEGIN {print $TOTAL / 20}")

echo "Average time: $AVG s" >> $LOG_FILE

awk -v avg="$AVG" -v limit="$LIMIT" 'BEGIN {
  if (avg > limit) {
    print "❌ STRESS PERFORMANCE SLOW"
  } else {
    print "✅ STRESS PERFORMANCE OK"
  }
}' >> $LOG_FILE

# -------------------------
# JWT TAMPER TEST
# -------------------------
echo "" >> $LOG_FILE
echo "---- JWT TAMPER TEST ----" >> $LOG_FILE

BAD_TOKEN="abc.def.ghi"

BAD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "$BASE_URL/api/v1/profile" \
  -H "Authorization: Bearer $BAD_TOKEN")

echo "Tampered JWT status: $BAD_STATUS (expect 401)" >> $LOG_FILE

echo "" >> $LOG_FILE
echo "=============================" >> $LOG_FILE
echo "TEST COMPLETE" >> $LOG_FILE


# -------------------------
# DEVICE TOKEN VALIDATION TEST
# -------------------------
echo "" >> $LOG_FILE
echo "---- DEVICE TOKEN VALIDATION ----" >> $LOG_FILE

INVALID_DEVICE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X PATCH "$BASE_URL/api/v1/device_token" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"device":{"device_token":""}}')

STATUS=$(echo "$INVALID_DEVICE" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
echo "Blank device_token status: $STATUS (expect 422)" >> $LOG_FILE


BAD_FORMAT_DEVICE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X PATCH "$BASE_URL/api/v1/device_token" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"device":{"device_token":"@@@invalid@@@"}}')

STATUS=$(echo "$BAD_FORMAT_DEVICE" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
echo "Invalid format device_token status: $STATUS (expect 422)" >> $LOG_FILE


# -------------------------
# DEVICE TOKEN RATE LIMIT TEST
# -------------------------
echo "" >> $LOG_FILE
echo "---- DEVICE TOKEN RATE LIMIT ----" >> $LOG_FILE

RATE_LIMIT_HIT=0

for i in {1..15}
do
  TOKEN_VALUE="testtoken$i-abcdefghijklmnopqrstuvwxyz123456"

  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PATCH "$BASE_URL/api/v1/device_token" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "{\"device\":{\"device_token\":\"$TOKEN_VALUE\"}}")

  echo "Attempt $i: $STATUS" >> $LOG_FILE

  if [ "$STATUS" = "429" ]; then
    RATE_LIMIT_HIT=1
  fi
done

if [ "$RATE_LIMIT_HIT" = "1" ]; then
  echo "✅ Device token rate limit working" >> $LOG_FILE
else
  echo "❌ Device token rate limit NOT triggered" >> $LOG_FILE
fi


# -------------------------
# MESSAGE RATE LIMIT TEST
# -------------------------
echo "" >> $LOG_FILE
echo "---- MESSAGE RATE LIMIT ----" >> $LOG_FILE

RATE_LIMIT_MSG=0

for i in {1..80}
do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$BASE_URL/api/v1/messages" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d '{"recipient_id":2,"content":"spam test"}')

  if [ "$STATUS" = "429" ]; then
    RATE_LIMIT_MSG=1
    break
  fi
done

if [ "$RATE_LIMIT_MSG" = "1" ]; then
  echo "✅ Message rate limit working" >> $LOG_FILE
else
  echo "❌ Message rate limit NOT triggered" >> $LOG_FILE
fi


# -------------------------
# GENERAL API RATE LIMIT TEST
# -------------------------
echo "" >> $LOG_FILE
echo "---- GENERAL API RATE LIMIT ----" >> $LOG_FILE

GENERAL_LIMIT_HIT=0

for i in {1..400}
do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "$BASE_URL/api/v1/profile" \
    -H "$AUTH_HEADER")

  if [ "$STATUS" = "429" ]; then
    GENERAL_LIMIT_HIT=1
    break
  fi
done

if [ "$GENERAL_LIMIT_HIT" = "1" ]; then
  echo "✅ General API rate limit working" >> $LOG_FILE
else
  echo "⚠️ General API rate limit not triggered (check limit config)" >> $LOG_FILE
fi




echo "✅ Regression + Performance test finished. Check $LOG_FILE"
