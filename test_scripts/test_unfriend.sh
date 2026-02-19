#!/bin/bash

BASE_URL="http://localhost:3000"

EMAIL_A="narisara.lasan@bestgloballogistics.com"
PASSWORD_A="123456"

EMAIL_B="shammi@1shammi1.com"
PASSWORD_B="RNIrSPPICj"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

TOTAL_FAIL=0
pass(){ echo -e "${GREEN}✅ $1${NC}"; }
fail(){ echo -e "${RED}❌ $1${NC}"; TOTAL_FAIL=$((TOTAL_FAIL+1)); }
step(){ echo -e "\n${CYAN}==== $1 ====${NC}"; }

login(){
  curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.token'
}

get_id(){
  curl -s $BASE_URL/api/v1/profile \
    -H "Authorization: Bearer $1" | jq -r '.id'
}

is_friend(){
  local MY_TOKEN=$1
  local OTHER_ID=$2
  curl -s $BASE_URL/api/v1/networking/my_connections \
    -H "Authorization: Bearer $MY_TOKEN" \
    | jq --argjson oid "$OTHER_ID" \
      '[.[] | select(
          (.requester.id == $oid) or (.target.id == $oid)
        )] | length' 2>/dev/null || echo 0
}

############################################################
step "LOGIN"

TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")
A_ID=$(get_id "$TOKEN_A")
B_ID=$(get_id "$TOKEN_B")

[ -z "$TOKEN_A" ] && { fail "Login A failed"; exit 1; }
[ -z "$TOKEN_B" ] && { fail "Login B failed"; exit 1; }
pass "Login OK (A=$A_ID, B=$B_ID)"

############################################################
step "SETUP — ส่ง friend request แล้ว accept อัตโนมัติ"

# เช็คก่อนว่าเป็นเพื่อนกันแล้วหรือยัง
ALREADY=$(is_friend "$TOKEN_A" "$B_ID")

if [ "${ALREADY:-0}" -gt 0 ]; then
  echo -e "${YELLOW}  ℹ เป็นเพื่อนกันอยู่แล้ว — ข้าม setup${NC}"
else
  echo "  A ส่ง friend request ไปหา B..."
  REQ_RESPONSE=$(curl -s -X POST $BASE_URL/api/v1/requests \
    -H "Authorization: Bearer $TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{\"target_id\": $B_ID}")
  echo "  Request response: $REQ_RESPONSE"

  REQ_ID=$(echo "$REQ_RESPONSE" | jq -r '.id // empty')

  if [ -z "$REQ_ID" ]; then
    # อาจมี pending request อยู่แล้ว — ลองดึงจาก B
    echo "  ลอง get pending request ของ B..."
    REQ_ID=$(curl -s $BASE_URL/api/v1/requests/my_received \
      -H "Authorization: Bearer $TOKEN_B" \
      | jq --argjson aid "$A_ID" \
        '[.[] | select(.requester.id == $aid)] | .[0].id' 2>/dev/null)
  fi

  if [ -z "$REQ_ID" ] || [ "$REQ_ID" = "null" ]; then
    fail "ส่ง friend request ไม่ได้ — ตรวจสอบ requests controller"
    exit 1
  fi

  echo "  B accept request id=$REQ_ID..."
  ACCEPT_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PATCH "$BASE_URL/api/v1/requests/$REQ_ID/accept" \
    -H "Authorization: Bearer $TOKEN_B")

  if [ "$ACCEPT_RESPONSE" -eq 200 ]; then
    pass "Setup OK: A และ B เป็นเพื่อนกันแล้ว"
  else
    fail "Accept request failed (HTTP $ACCEPT_RESPONSE)"
    exit 1
  fi
fi

############################################################
step "CASE 1 — ยืนยันว่าเป็นเพื่อนกันก่อน unfriend"

COUNT=$(is_friend "$TOKEN_A" "$B_ID")
if [ "${COUNT:-0}" -gt 0 ]; then
  pass "Confirmed: A และ B เป็นเพื่อนกัน (connections=$COUNT)"
else
  fail "ไม่พบ connection — setup ล้มเหลว"
  exit 1
fi

############################################################
step "CASE 2 — A unfriend B"

BODY=$(curl -s -w "\n%{http_code}" \
  -X DELETE "$BASE_URL/api/v1/networking/unfriend/$B_ID" \
  -H "Authorization: Bearer $TOKEN_A")

HTTP_CODE=$(echo "$BODY" | tail -1)
RESPONSE=$(echo "$BODY" | head -1)

echo "  HTTP Status: $HTTP_CODE"
echo "  Response: $RESPONSE"

if [ "$HTTP_CODE" -eq 200 ]; then
  pass "Unfriend สำเร็จ (200 OK)"
else
  fail "Unfriend failed (HTTP $HTTP_CODE)"
fi

############################################################
step "CASE 3 — ยืนยันว่าไม่เป็นเพื่อนกันแล้ว"

COUNT_AFTER=$(is_friend "$TOKEN_A" "$B_ID")
if [ "${COUNT_AFTER:-1}" -eq 0 ]; then
  pass "Confirmed: B หายออกจาก connections ของ A แล้ว"
else
  fail "B ยังอยู่ใน connections — unfriend ไม่สำเร็จ"
fi

# เช็คจาก B ด้วย
COUNT_B=$(is_friend "$TOKEN_B" "$A_ID")
if [ "${COUNT_B:-1}" -eq 0 ]; then
  pass "Confirmed: A หายออกจาก connections ของ B ด้วย (bidirectional)"
else
  fail "A ยังอยู่ใน connections ของ B — ลบไม่ครบ"
fi

############################################################
step "CASE 4 — unfriend ซ้ำ (ต้อง 404)"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X DELETE "$BASE_URL/api/v1/networking/unfriend/$B_ID" \
  -H "Authorization: Bearer $TOKEN_A")

echo "  HTTP Status: $HTTP_CODE"
if [ "$HTTP_CODE" -eq 404 ]; then
  pass "404 Not Found ถูกต้อง (ลบซ้ำไม่ได้)"
else
  fail "Expected 404 got $HTTP_CODE"
fi

############################################################
step "CASE 5 — unfriend delegate ที่ไม่มีอยู่ (ต้อง 404)"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X DELETE "$BASE_URL/api/v1/networking/unfriend/99999999" \
  -H "Authorization: Bearer $TOKEN_A")

echo "  HTTP Status: $HTTP_CODE"
if [ "$HTTP_CODE" -eq 404 ]; then
  pass "404 Not Found ถูกต้อง"
else
  fail "Expected 404 got $HTTP_CODE"
fi

############################################################
step "CASE 6 — unfriend โดยไม่มี token (ต้อง 401)"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X DELETE "$BASE_URL/api/v1/networking/unfriend/$B_ID")

echo "  HTTP Status: $HTTP_CODE"
if [ "$HTTP_CODE" -eq 401 ]; then
  pass "401 Unauthorized ถูกต้อง"
else
  fail "Expected 401 got $HTTP_CODE"
fi

############################################################

echo ""
echo "========================================="
if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo -e "${GREEN}🔥 ALL TESTS PASSED 🔥${NC}"
else
  echo -e "${RED}⚠ $TOTAL_FAIL TEST(S) FAILED${NC}"
fi
echo "========================================="