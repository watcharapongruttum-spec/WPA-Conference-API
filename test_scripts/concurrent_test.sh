#!/bin/bash

BASE_URL="http://localhost:3000"

EMAIL_A="narisara.lasan@bestgloballogistics.com"
PASSWORD_A="123456"

EMAIL_B="shammi@1shammi1.com"
PASSWORD_B="RNIrSPPICj"





login() {
  curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

get_profile_id() {
  curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1" | jq -r '.id'
}

TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")

A_ID=$(get_profile_id "$TOKEN_A")
B_ID=$(get_profile_id "$TOKEN_B")

URL="$BASE_URL/api/v1/messages"

CONCURRENT=${1:-200}

echo "🔥 Stress Test: $CONCURRENT concurrent"

success=0
fail=0

start=$(date +%s%3N)

for i in $(seq 1 $CONCURRENT)
do
  {
    code=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST $URL \
      -H "Authorization: Bearer ${TOKEN_A}" \
      -H "Content-Type: application/json" \
      -d "{\"receiver_id\":$B_ID,\"content\":\"Stress $i\"}")

    if [ "$code" = "201" ]; then
      echo "SUCCESS" >> result.log
    else
      echo "FAIL $code" >> result.log
    fi
  } &
done

wait

end=$(date +%s%3N)

success=$(grep -c SUCCESS result.log)
fail=$(grep -c FAIL result.log)

echo "==========================="
echo "Total Requests: $CONCURRENT"
echo "Success: $success"
echo "Fail: $fail"
echo "Time: $((end - start)) ms"
echo "==========================="

rm result.log

