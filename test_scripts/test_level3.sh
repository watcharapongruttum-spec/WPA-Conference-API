#!/bin/bash
set -e

BASE_URL="${BASE_URL:-http://localhost:3000}"
EMAIL_A="${EMAIL_A:-narisara.lasan@bestgloballogistics.com}"
PASSWORD_A="${PASSWORD_A:-123456}"

EMAIL_B="${EMAIL_B:-shammi@1shammi1.com}"
PASSWORD_B="${PASSWORD_B:-RNIrSPPICj}"

CONCURRENT=${1:-50}
BURST=${2:-200}
DURATION=${3:-30}

TEST_TAG="L3_$(date +%s)"
FAIL=0

echo "🚀 LEVEL 3 STRESS TEST ($TEST_TAG)"
echo "Concurrent=$CONCURRENT | Burst=$BURST | Duration=${DURATION}s"

# ========================================
# LOGIN
# ========================================
login() {
  curl -s -X POST $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" \
    | jq -r '.token'
}

TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")

A_ID=$(curl -s $BASE_URL/api/v1/profile -H "Authorization: Bearer $TOKEN_A" | jq -r '.id')
B_ID=$(curl -s $BASE_URL/api/v1/profile -H "Authorization: Bearer $TOKEN_B" | jq -r '.id')

echo "User A=$A_ID | User B=$B_ID"

# ========================================
# 1️⃣ BURST WRITE TEST
# ========================================

echo "🔥 Burst Write Test"

tmp=$(mktemp)

for i in $(seq 1 $BURST); do
{
  curl -s -w "%{time_total} %{http_code}\n" \
    -o /dev/null \
    -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$B_ID,\"content\":\"$TEST_TAG burst_$i\"}" \
    >> $tmp
} &
  
  if (( $i % $CONCURRENT == 0 )); then
    wait
  fi
done
wait

echo "📊 Burst Stats:"
awk '{sum+=$1; count++} END {print "Avg latency:", sum/count}' $tmp

if grep -q "500" $tmp; then
  echo "❌ 500 detected during burst"
  FAIL=1
fi

rm $tmp

# ========================================
# 2️⃣ SUSTAINED MIX LOAD
# ========================================

echo "🔥 Sustained Mixed Load (${DURATION}s)"

end=$((SECONDS+DURATION))

while [ $SECONDS -lt $end ]; do
{
  curl -s -o /dev/null \
    -X GET "$BASE_URL/api/v1/messages/conversation/$B_ID?page=1&per=20" \
    -H "Authorization: Bearer $TOKEN_A"
} &

{
  curl -s -o /dev/null \
    -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$B_ID,\"content\":\"$TEST_TAG sustained\"}"
} &
done

wait

echo "✅ Sustained load finished"

# ========================================
# 3️⃣ MEMORY SNAPSHOT (Basic)
# ========================================

echo "🧠 Memory snapshot"
ps aux | grep puma | grep -v grep
ps aux | grep sidekiq | grep -v grep

# ========================================
# 4️⃣ CLEANUP (DB SAFE)
# ========================================

echo "🧹 Cleaning test data"

curl -s "$BASE_URL/api/v1/messages/conversation/$B_ID?per=500" \
  -H "Authorization: Bearer $TOKEN_A" \
  | jq -r ".[] | select(.content | contains(\"$TEST_TAG\")) | .id" \
  | while read id; do
      curl -s -X DELETE $BASE_URL/api/v1/messages/$id \
        -H "Authorization: Bearer $TOKEN_A" > /dev/null
    done

echo "Cleanup complete"

# ========================================
# RESULT
# ========================================

if [ "$FAIL" -eq 0 ]; then
  echo "🎉 LEVEL 3 PASSED (System Stable Under Load)"
  exit 0
else
  echo "🔥 LEVEL 3 FAILED"
  exit 1
fi
