#!/bin/bash
set +e

BASE_URL="http://localhost:3000"
WS_URL="ws://localhost:3000/cable"

EMAIL_A="narisara.lasan@bestgloballogistics.com"
PASSWORD_A="123456"

EMAIL_B="shammi@1shammi1.com"
PASSWORD_B="RNIrSPPICj"

step() { echo -e "\n==== $1 ===="; }

# ---------------- LOGIN ----------------
login() {
  curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

get_id() {
  curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1" | jq -r '.id'
}

# ---------------- CHAT ----------------
send_msg() {
  curl -s -X POST $BASE_URL/api/v1/messages \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\":$2,\"content\":\"FULL TEST\"}" > /dev/null
}

unread_count() {
  curl -s "$BASE_URL/api/v1/messages/unread_count?sender_id=$2" \
    -H "Authorization: Bearer $1"
}

online_status() {
  curl -s "$BASE_URL/api/v1/messages/online_status?user_id=$2" \
    -H "Authorization: Bearer $1"
}

# ---------------- NOTIFICATION ----------------
notif_count() {
  curl -s "$BASE_URL/api/v1/notifications/unread_count" \
    -H "Authorization: Bearer $1"
}

notif_list() {
  curl -s "$BASE_URL/api/v1/notifications" \
    -H "Authorization: Bearer $1" | jq .
}

mark_all_notif_read() {
  curl -s -X PATCH "$BASE_URL/api/v1/notifications/mark_all_as_read" \
    -H "Authorization: Bearer $1"
}

# ---------------- WEBSOCKET ----------------
start_ws() {
  TOKEN=$1
  NAME=$2
  TARGET=$3
  AUTO_ENTER=$4

  (
    {
      sleep 1
      echo '{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}'
      sleep 1

      if [ "$AUTO_ENTER" = "yes" ]; then
        echo "{\"command\":\"message\",\"identifier\":\"{\\\"channel\\\":\\\"ChatChannel\\\"}\",\"data\":\"{\\\"action\\\":\\\"enter_room\\\",\\\"user_id\\\":$TARGET}\"}"
      fi

      sleep 999
    } | wscat -c "$WS_URL?token=$TOKEN"
  ) > "ws_$NAME.log" 2>&1 &

  echo $! > "ws_$NAME.pid"
  sleep 2
}

stop_ws() {
  kill $(cat ws_$1.pid) 2>/dev/null
  rm -f ws_$1.pid
}

# ===================================================
# START TEST
# ===================================================

step "LOGIN"
TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")

echo "TOKEN_A=$TOKEN_A"
echo "TOKEN_B=$TOKEN_B"

A_ID=$(get_id "$TOKEN_A")
B_ID=$(get_id "$TOKEN_B")

echo "A_ID=$A_ID"
echo "B_ID=$B_ID"

# -------------------------
step "CASE 1 — B OFFLINE SEND"
send_msg "$TOKEN_A" "$B_ID"
echo "Expect delivered_at = null"
sleep 2

# -------------------------
step "CASE 2 — B ONLINE ONLY"
start_ws "$TOKEN_B" "B" "$A_ID" "no"
send_msg "$TOKEN_A" "$B_ID"
echo "Expect delivered_at != null"
sleep 3

# -------------------------
step "CHECK ONLINE STATUS"
online_status "$TOKEN_A" "$B_ID"
sleep 1

# -------------------------
step "CASE 3 — ENTER ROOM (AUTO READ)"
stop_ws "B"
start_ws "$TOKEN_B" "B" "$A_ID" "yes"
send_msg "$TOKEN_A" "$B_ID"
echo "Expect read_at != null"
sleep 3

# -------------------------
step "UNREAD COUNT"
unread_count "$TOKEN_B" "$A_ID"
sleep 1

# -------------------------
step "CHECK REDIS ROOM"
docker exec redis redis-cli KEYS chat_open:*

# -------------------------
step "NOTIFICATION RECORD"
rails runner "puts Notification.last.notification_type"

# -------------------------
step "NOTIFICATION COUNT"
notif_count "$TOKEN_B"

# -------------------------
step "NOTIFICATION LIST"
notif_list "$TOKEN_B"

# -------------------------
step "MARK ALL NOTIFICATION READ"
mark_all_notif_read "$TOKEN_B"

step "NOTIFICATION COUNT AFTER READ"
notif_count "$TOKEN_B"

# -------------------------
step "STOP WS"
stop_ws "B"
sleep 2

# -------------------------
step "CHECK REDIS AFTER LEAVE"
docker exec redis redis-cli KEYS chat_open:*

# -------------------------
step "CHECK LAST MESSAGE DELIVERED"
rails runner "puts ChatMessage.last.delivered_at"

# -------------------------
step "DONE"
