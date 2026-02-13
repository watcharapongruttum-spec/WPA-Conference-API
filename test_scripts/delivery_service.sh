#!/bin/bash
set +e

BASE_URL="http://localhost:3000"
WS_URL="ws://localhost:3000/cable"

EMAIL_A="narisara.lasan@bestgloballogistics.com"
PASSWORD_A="123456"

EMAIL_B="shammi@1shammi1.com"
PASSWORD_B="RNIrSPPICj"

step() { echo -e "\n==== $1 ===="; }

login() {
  curl -s $BASE_URL/api/v1/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

get_id() {
  curl -s $BASE_URL/api/v1/profile \
  -H "Authorization: Bearer $1" | jq -r '.id'
}

send_msg() {
  curl -s -X POST $BASE_URL/api/v1/messages \
  -H "Authorization: Bearer $1" \
  -H "Content-Type: application/json" \
  -d "{\"recipient_id\":$2,\"content\":\"DELIVERY TEST\"}" > /dev/null
}

start_ws() {
  TOKEN=$1
  NAME=$2
  TARGET_ID=$3

  (
    {
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}'

      # ===== ENTER ROOM =====
      sleep 1
      echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\"}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":$TARGET_ID}\"}"

      sleep 999
    } | wscat -c "$WS_URL?token=$TOKEN"
  ) > "ws_$NAME.log" 2>&1 &
}

step "LOGIN"
TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")

A_ID=$(get_id "$TOKEN_A")
B_ID=$(get_id "$TOKEN_B")

step "CASE 1 — B OFFLINE"
send_msg "$TOKEN_A" "$B_ID"
echo "Expect delivered_at = null"
sleep 2

step "CASE 2 — B ONLINE ONLY"
(
  {
    sleep 1
    echo '{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}'
    sleep 999
  } | wscat -c "$WS_URL?token=$TOKEN_B"
) > ws_B_online.log 2>&1 &

sleep 2
send_msg "$TOKEN_A" "$B_ID"
echo "Expect delivered_at = null (still)"
sleep 2

step "CASE 3 — B ENTER ROOM"
start_ws "$TOKEN_B" "B_room" "$A_ID"
sleep 3
send_msg "$TOKEN_A" "$B_ID"
echo "Expect delivered_at != null"

sleep 3

step "CHECK REDIS"
docker exec -it redis redis-cli KEYS chat_open:*

step "DONE"


