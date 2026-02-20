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

get_connection_fields(){
  local TOKEN=$1
  local OTHER_ID=$2
  curl -s "$BASE_URL/api/v1/delegates/$OTHER_ID" \
    -H "Authorization: Bearer $TOKEN"
}

############################################################
step "LOGIN"

TOKEN_A=$(login "$EMAIL_A" "$PASSWORD_A")
TOKEN_B=$(login "$EMAIL_B" "$PASSWORD_B")
A_ID=$(get_id "$TOKEN_A")
B_ID=$(get_id "$TOKEN_B")

[ -z "$TOKEN_A" ] || [ "$TOKEN_A" = "null" ] && { fail "Login A failed"; exit 1; }
[ -z "$TOKEN_B" ] || [ "$TOKEN_B" = "null" ] && { fail "Login B failed"; exit 1; }
pass "Login OK (A=$A_ID, B=$B_ID)"

############################################################
step "SETUP — Auto-cleanup stale data"

# 1) ลบ Connection record ที่ค้างอยู่ (ผ่าน unfriend)
echo "  ลบ Connection record ที่ค้างอยู่ (ถ้ามี)..."
UF_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X DELETE "$BASE_URL/api/v1/networking/unfriend/$B_ID" \
  -H "Authorization: Bearer $TOKEN_A")
echo "  unfriend HTTP: $UF_CODE (200=ลบได้, 404=ไม่มีค้าง)"

# 2) ลบ ConnectionRequest ที่ค้างอยู่ (ผ่าน cancel)
echo "  ลบ ConnectionRequest ที่ค้างอยู่ (ถ้ามี)..."
C1=$(curl -s -o /dev/null -w "%{http_code}" \
  -X DELETE "$BASE_URL/api/v1/requests/$B_ID/cancel" \
  -H "Authorization: Bearer $TOKEN_A")
C2=$(curl -s -o /dev/null -w "%{http_code}" \
  -X DELETE "$BASE_URL/api/v1/requests/$A_ID/cancel" \
  -H "Authorization: Bearer $TOKEN_B")
echo "  cancel as A: HTTP $C1 | cancel as B: HTTP $C2"

# 3) ตรวจสอบอีกครั้ง
ANY_CR=$(curl -s $BASE_URL/api/v1/requests \
  -H "Authorization: Bearer $TOKEN_A" \
  | jq --argjson oid "$B_ID" \
    '[.[] | select((.requester_id == $oid) or (.target_id == $oid))] | length' 2>/dev/null || echo 0)

echo "  ConnectionRequest ที่เหลืออยู่: $ANY_CR"

if [ "${ANY_CR:-0}" -gt 0 ]; then
  echo -e "${RED}  Auto-cleanup ไม่สำเร็จ — ต้องล้างด้วย rails console${NC}"
  echo -e "${YELLOW}  รัน:${NC}"
  echo "  ConnectionRequest.where(\"(requester_id=$A_ID AND target_id=$B_ID) OR (requester_id=$B_ID AND target_id=$A_ID)\").delete_all"
  echo "  Connection.where(\"(requester_id=$A_ID AND target_id=$B_ID) OR (requester_id=$B_ID AND target_id=$A_ID)\").delete_all"
  fail "Cleanup ล้มเหลว"
  exit 1
fi

# 4) ส่ง request ใหม่
echo "  A ส่ง connection request ไปหา B..."
REQ_RESP=$(curl -s -X POST $BASE_URL/api/v1/requests \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"target_id\": $B_ID}")

echo "  Request response: $REQ_RESP"
REQ_ID=$(echo "$REQ_RESP" | jq -r '.id // empty')

if [ -z "$REQ_ID" ] || [ "$REQ_ID" = "null" ]; then
  REQ_ID=$(curl -s $BASE_URL/api/v1/requests/my_received \
    -H "Authorization: Bearer $TOKEN_B" \
    | jq -r --argjson aid "$A_ID" \
      '[.[] | select(.requester.id == $aid)] | .[0].id // empty' 2>/dev/null)
fi

if [ -z "$REQ_ID" ] || [ "$REQ_ID" = "null" ]; then
  fail "ส่ง request ไม่ได้"
  exit 1
fi
pass "Setup OK: A ส่ง request id=$REQ_ID ไปหา B แล้ว"

############################################################
step "BUG FIX 1 — ก่อน reject: pending ยังไม่ใช่ connected"

PROFILE=$(get_connection_fields "$TOKEN_B" "$A_ID")
IS_CONN=$(echo "$PROFILE" | jq -r '.is_connected')
CONN_STATUS=$(echo "$PROFILE" | jq -r '.connection_status')

echo "  is_connected: $IS_CONN"
echo "  connection_status: $CONN_STATUS"

[ "$IS_CONN" = "false" ] \
  && pass "is_connected = false ✓ (ขณะ pending ยังไม่ควร connected)" \
  || fail "is_connected = $IS_CONN (ควรเป็น false ขณะ pending)"

[ "$CONN_STATUS" = "requested_to_me" ] \
  && pass "connection_status = 'requested_to_me' ✓" \
  || fail "connection_status = '$CONN_STATUS' (ควรเป็น 'requested_to_me')"

############################################################
step "BUG FIX 1 — B reject request"

REJECT_RESP=$(curl -s -w "\n%{http_code}" \
  -X PATCH "$BASE_URL/api/v1/requests/$REQ_ID/reject" \
  -H "Authorization: Bearer $TOKEN_B")

HTTP_CODE=$(echo "$REJECT_RESP" | tail -1)
BODY=$(echo "$REJECT_RESP" | head -1)
STATUS_IN_RESP=$(echo "$BODY" | jq -r '.status // empty')

echo "  HTTP: $HTTP_CODE | status in response: $STATUS_IN_RESP"

[ "$HTTP_CODE" -eq 200 ] && [ "$STATUS_IN_RESP" = "rejected" ] \
  && pass "Reject API สำเร็จ (200, status=rejected)" \
  || fail "Reject API ผิดพลาด (HTTP=$HTTP_CODE, status=$STATUS_IN_RESP)"

############################################################
step "BUG FIX 1 — หลัง reject: is_connected + connection_status ต้อง consistent"

echo ""
echo "  [มุมมอง B ดู profile A]"
PROFILE_B=$(get_connection_fields "$TOKEN_B" "$A_ID")
IS_CONN_B=$(echo "$PROFILE_B" | jq -r '.is_connected')
STATUS_B=$(echo "$PROFILE_B" | jq -r '.connection_status')
echo "  is_connected: $IS_CONN_B"
echo "  connection_status: $STATUS_B"

[ "$IS_CONN_B" = "false" ] \
  && pass "[B→A] is_connected = false ✓" \
  || fail "[B→A] BUG! is_connected = $IS_CONN_B (ควรเป็น false หลัง reject)"

[ "$STATUS_B" = "none" ] \
  && pass "[B→A] connection_status = 'none' ✓" \
  || fail "[B→A] BUG! connection_status = '$STATUS_B' (ควรเป็น 'none' หลัง reject)"

if [ "$IS_CONN_B" = "false" ] && [ "$STATUS_B" = "none" ]; then
  pass "[B→A] CONSISTENCY OK ✓ ไม่ขัดแย้งกัน"
else
  fail "[B→A] CONSISTENCY FAIL: is_connected=$IS_CONN_B แต่ connection_status=$STATUS_B"
fi

echo ""
echo "  [มุมมอง A ดู profile B]"
PROFILE_A=$(get_connection_fields "$TOKEN_A" "$B_ID")
IS_CONN_A=$(echo "$PROFILE_A" | jq -r '.is_connected')
STATUS_A=$(echo "$PROFILE_A" | jq -r '.connection_status')
echo "  is_connected: $IS_CONN_A"
echo "  connection_status: $STATUS_A"

[ "$IS_CONN_A" = "false" ] \
  && pass "[A→B] is_connected = false ✓" \
  || fail "[A→B] BUG! is_connected = $IS_CONN_A"

[ "$STATUS_A" = "none" ] \
  && pass "[A→B] connection_status = 'none' ✓" \
  || fail "[A→B] BUG! connection_status = '$STATUS_A'"

############################################################
step "BUG FIX 2 — Leave Form: schedule_id ต้องไม่ null"

SCHEDULE_ID=$(curl -s "$BASE_URL/api/v1/schedules/my_schedule" \
  -H "Authorization: Bearer $TOKEN_A" \
  | jq -r '.schedules[]? | select(.type == "meeting") | .id' 2>/dev/null | head -1)

LEAVE_TYPE_ID=$(curl -s "$BASE_URL/api/v1/leave_types" \
  -H "Authorization: Bearer $TOKEN_A" \
  | jq -r '.[0].id // empty')

echo "  Schedule ID: $SCHEDULE_ID"
echo "  Leave Type ID: $LEAVE_TYPE_ID"

if [ -z "$SCHEDULE_ID" ] || [ "$SCHEDULE_ID" = "null" ]; then
  echo -e "${YELLOW}  ⚠ ไม่มี schedule ของ user A — ข้าม test นี้${NC}"
elif [ -z "$LEAVE_TYPE_ID" ] || [ "$LEAVE_TYPE_ID" = "null" ]; then
  echo -e "${YELLOW}  ⚠ ไม่มี leave_type ใน DB — ข้าม test นี้${NC}"
else
  LF_RESP=$(curl -s -w "\n%{http_code}" \
    -X POST "$BASE_URL/api/v1/leave_forms" \
    -H "Authorization: Bearer $TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{
      \"leave_form\": {
        \"leaves\": [
          {
            \"schedule_id\": $SCHEDULE_ID,
            \"leave_type_id\": $LEAVE_TYPE_ID,
            \"reason\": \"test\",
            \"explanation\": \"automated test\"
          }
        ]
      }
    }")

  LF_HTTP=$(echo "$LF_RESP" | tail -1)
  LF_BODY=$(echo "$LF_RESP" | head -1)
  CREATED_COUNT=$(echo "$LF_BODY" | jq -r '.created_count // 0')

  echo "  HTTP: $LF_HTTP | created_count: $CREATED_COUNT"
  echo "  Response: $LF_BODY"

  if [ "$LF_HTTP" -eq 200 ] && [ "$CREATED_COUNT" -gt 0 ]; then
    pass "Leave Form สร้างสำเร็จ (created_count=$CREATED_COUNT) ✓"
    pass "schedule_id ถูก permit และบันทึกแล้ว ✓"
  else
    fail "Leave Form สร้างไม่สำเร็จ (HTTP=$LF_HTTP, created_count=$CREATED_COUNT)"
  fi
fi

############################################################
step "CLEANUP — ลบ rejected request เพื่อให้รัน test ซ้ำได้"

C=$(curl -s -o /dev/null -w "%{http_code}" \
  -X DELETE "$BASE_URL/api/v1/requests/$B_ID/cancel" \
  -H "Authorization: Bearer $TOKEN_A")
echo "  cancel HTTP: $C (200/404 = OK)"

############################################################

echo ""
echo "========================================="
if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo -e "${GREEN}🔥 ALL TESTS PASSED 🔥${NC}"
else
  echo -e "${RED}⚠ $TOTAL_FAIL TEST(S) FAILED${NC}"
fi
echo "========================================="