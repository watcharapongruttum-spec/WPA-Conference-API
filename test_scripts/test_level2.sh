#!/bin/bash
set -e

BASE_URL="${BASE_URL:-http://localhost:3000}"
EMAIL_A="${EMAIL_A:-narisara.lasan@bestgloballogistics.com}"
PASSWORD_A="${PASSWORD_A:-123456}"

EMAIL_B="${EMAIL_B:-shammi@1shammi1.com}"
PASSWORD_B="${PASSWORD_B:-RNIrSPPICj}"

TEST_TAG="L2_$(date +%s)"
CONCURRENT=${1:-10}

FAIL=0

echo "🚀 LEVEL 2 FULL TEST START ($TEST_TAG)"
echo "BASE_URL=$BASE_URL"

# ===============================
# LOGIN
# ===============================
login() {
  response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}")

  code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')

  if [ "$code" != "200" ]; then
    echo "❌ Login failed for $1"
    exit 1
  fi

  echo "$body" | jq -r '.token'
}

TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")

A_ID=$(curl -s $BASE_URL/api/v1/profile -H "Authorization: Bearer $TOKEN_A" | jq -r '.id')
B_ID=$(curl -s $BASE_URL/api/v1/profile -H "Authorization: Bearer $TOKEN_B" | jq -r '.id')

echo "User A=$A_ID | User B=$B_ID"

# ============================================
# 1️⃣ RACE DELETE (IDEMPOTENT SAFE)
# ============================================

echo "🔹 Testing Race Delete"

MSG_ID=$(curl -s -X POST $BASE_URL/api/v1/messages \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"recipient_id\":$B_ID,\"content\":\"$TEST_TAG Race\"}" \
  | jq -r '.id')

tmp=$(mktemp)

for i in $(seq 1 $CONCURRENT); do
{
  curl -s -o /dev/null -w "%{http_code}" \
    -X DELETE $BASE_URL/api/v1/messages/$MSG_ID \
    -H "Authorization: Bearer $TOKEN_A" >> $tmp
} &
done
wait

RESULTS=$(cat $tmp)
rm $tmp

echo "Delete results: $RESULTS"

if echo "$RESULTS" | grep -q "500"; then
  echo "❌ Race delete caused 500"
  FAIL=1
fi

# ============================================
# 2️⃣ DOUBLE JOIN
# ============================================

echo "🔹 Testing Double Join"

ROOM_ID=$(curl -s -X POST $BASE_URL/api/v1/chat_rooms \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"title\":\"$TEST_TAG Room\",\"room_kind\":\"group\"}" \
  | jq -r '.id')

tmp=$(mktemp)

for i in $(seq 1 $CONCURRENT); do
{
  curl -s -o /dev/null -w "%{http_code}" \
    -X POST $BASE_URL/api/v1/chat_rooms/$ROOM_ID/join \
    -H "Authorization: Bearer $TOKEN_B" >> $tmp
} &
done
wait

JOIN_RESULTS=$(cat $tmp)
rm $tmp

echo "Join results: $JOIN_RESULTS"

if echo "$JOIN_RESULTS" | grep -q "500"; then
  echo "❌ Double join caused 500"
  FAIL=1
fi

# ============================================
# 3️⃣ GLOBAL SOFT DELETE CHECK
# ============================================

echo "🔹 Testing Global Soft Delete"

MSG_ID=$(curl -s -X POST $BASE_URL/api/v1/messages \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"recipient_id\":$B_ID,\"content\":\"$TEST_TAG SoftDelete\"}" \
  | jq -r '.id')

curl -s -X DELETE $BASE_URL/api/v1/messages/$MSG_ID \
  -H "Authorization: Bearer $TOKEN_A" > /dev/null

curl -s "$BASE_URL/api/v1/messages/conversation/$A_ID" \
  -H "Authorization: Bearer $TOKEN_B" > /tmp/conv.json

if grep -q "$MSG_ID" /tmp/conv.json; then
  echo "❌ Soft delete failed (message still visible)"
  FAIL=1
else
  echo "✅ Soft delete OK (message hidden globally)"
fi

# ============================================
# 4️⃣ DEEP PAGINATION
# ============================================

echo "🔹 Testing Deep Pagination"

for p in 100 9999 -1 abc; do
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    "$BASE_URL/api/v1/messages/conversation/$B_ID?page=$p&per=50" \
    -H "Authorization: Bearer $TOKEN_A")

  echo "page=$p → $code"

  if [ "$code" != "200" ]; then
    echo "❌ Pagination failed on page=$p"
    FAIL=1
  fi
done

# ============================================
# RESULT
# ============================================

if [ "$FAIL" -eq 0 ]; then
  echo "🎉 LEVEL 2 PASSED"
  exit 0
else
  echo "🔥 LEVEL 2 FAILED"
  exit 1
fi
