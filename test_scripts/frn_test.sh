#!/bin/bash
set +e

BASE_URL="http://localhost:3000"

EMAIL_A="narisara.lasan@bestgloballogistics.com"
PASSWORD_A="123456"

EMAIL_B="shammi@1shammi1.com"
PASSWORD_B="RNIrSPPICj"

step() {
  echo -e "\n=============================="
  echo "== $1"
  echo "=============================="
}

login() {
  curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

get_id() {
  curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1" | jq -r '.id'
}

# ✅ แสดงแค่ 3 field
get_status() {
  curl -s $BASE_URL/api/v1/delegates/$2 \
    -H "Authorization: Bearer $1" \
    | jq '{id, email, connection_status}'
}

# ==========================================
# LOGIN
# ==========================================

step "LOGIN USERS"

TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")

A_ID=$(get_id "$TOKEN_A")
B_ID=$(get_id "$TOKEN_B")

echo "A_ID=$A_ID"
echo "B_ID=$B_ID"

# ==========================================
# RESET DB STATE
# ==========================================

step "RESET CONNECTION REQUESTS"

rails runner "
ConnectionRequest.where(requester_id: $A_ID, target_id: $B_ID).destroy_all
ConnectionRequest.where(requester_id: $B_ID, target_id: $A_ID).destroy_all
puts 'Cleared'
"

sleep 1

# ==========================================
# CASE 1 — NONE
# ==========================================

step "CASE 1 — NONE"

echo "A sees B:"
get_status "$TOKEN_A" "$B_ID"

echo "B sees A:"
get_status "$TOKEN_B" "$A_ID"

# ==========================================
# CASE 2 — REQUESTED_BY_ME
# ==========================================

step "CASE 2 — A SEND REQUEST TO B"

curl -s -X POST $BASE_URL/api/v1/requests \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"target_id\":$B_ID}" \
  | jq '{id, requester_id, status}'

sleep 1

echo "A sees B:"
get_status "$TOKEN_A" "$B_ID"

echo "B sees A:"
get_status "$TOKEN_B" "$A_ID"

# ==========================================
# CASE 3 — ACCEPT
# ==========================================

step "CASE 3 — B ACCEPTS"

REQ_ID=$(curl -s $BASE_URL/api/v1/requests/my_received \
  -H "Authorization: Bearer $TOKEN_B" \
  | jq -r '.[0].id')

echo "Request ID=$REQ_ID"

curl -s -X PATCH $BASE_URL/api/v1/requests/$REQ_ID/accept \
  -H "Authorization: Bearer $TOKEN_B" \
  | jq '{id, status, updated_at}'

sleep 1

echo "A sees B:"
get_status "$TOKEN_A" "$B_ID"

echo "B sees A:"
get_status "$TOKEN_B" "$A_ID"

# ==========================================
# CASE 4 — REJECT FLOW
# ==========================================

step "CASE 4 — RESET AND REJECT"

rails runner "
ConnectionRequest.where(requester_id: $A_ID, target_id: $B_ID).destroy_all
ConnectionRequest.where(requester_id: $B_ID, target_id: $A_ID).destroy_all
puts 'Cleared'
"

sleep 1

curl -s -X POST $BASE_URL/api/v1/requests \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"target_id\":$B_ID}" > /dev/null

sleep 1

REQ_ID=$(curl -s $BASE_URL/api/v1/requests/my_received \
  -H "Authorization: Bearer $TOKEN_B" \
  | jq -r '.[0].id')

curl -s -X PATCH $BASE_URL/api/v1/requests/$REQ_ID/reject \
  -H "Authorization: Bearer $TOKEN_B" \
  | jq '{id, status, updated_at}'

sleep 1

echo "After reject:"
echo "A sees B:"
get_status "$TOKEN_A" "$B_ID"

echo "B sees A:"
get_status "$TOKEN_B" "$A_ID"

# ==========================================
step "DONE"
