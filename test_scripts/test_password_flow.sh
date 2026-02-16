#!/bin/bash
set +e

BASE_URL="http://localhost:3000"

EMAIL="noxterror999@gmail.com"
OLD_PASS="123456"
NEW_PASS="654321"
FINAL_PASS="111111"
RESET_BACK_PASS="123456"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; }
info() { echo -e "${YELLOW}ℹ️ $1${NC}"; }
step() { echo -e "\n${CYAN}==== $1 ====${NC}"; }

# ---------- FUNCTIONS ----------

login() {
  curl -s $BASE_URL/api/v1/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$1\"}" | jq -r '.token'
}

forgot_password() {
  curl -s -X POST $BASE_URL/api/v1/forgot_password \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\"}"
}

reset_password() {
  curl -s -X POST $BASE_URL/api/v1/reset_password \
    -H "Content-Type: application/json" \
    -d "{\"token\":\"$1\",\"password\":\"$2\",\"password_confirmation\":\"$2\"}"
}

change_password() {
  curl -s -X POST $BASE_URL/api/v1/change_password \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d "{\"new_password\":\"$2\"}"
}

# ================= START =================

# ---------- LOGIN OLD ----------
step "LOGIN OLD PASSWORD"
TOKEN=$(login "$OLD_PASS")

if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
  fail "LOGIN FAILED"
  exit 1
else
  pass "LOGIN OK"
fi

# ---------- WRONG LOGIN ----------
step "LOGIN WRONG PASSWORD"
WRONG=$(login "wrongpass")
if [ "$WRONG" = "null" ] || [ -z "$WRONG" ]; then
  pass "WRONG PASSWORD BLOCKED"
else
  fail "WRONG PASSWORD SHOULD FAIL"
fi

# ---------- CHANGE PASSWORD ----------
step "CHANGE PASSWORD"
RESP=$(change_password "$TOKEN" "$NEW_PASS")
echo $RESP
pass "CHANGE PASSWORD DONE"

# ---------- LOGIN NEW ----------
step "LOGIN WITH NEW PASSWORD"
TOKEN2=$(login "$NEW_PASS")

if [ "$TOKEN2" = "null" ] || [ -z "$TOKEN2" ]; then
  fail "NEW PASSWORD LOGIN FAILED"
  exit 1
else
  pass "NEW PASSWORD LOGIN OK"
fi

# ---------- FORGOT ----------
step "FORGOT PASSWORD"
forgot_password
pass "FORGOT SENT"

# ---------- RATE LIMIT TEST ----------
step "FORGOT RATE LIMIT TEST"
forgot_password
sleep 1
forgot_password
info "Second/Third call should be limited if implemented"

info "ไปดู token ใน rails c"
info "Delegate.find_by(email: '$EMAIL').reset_password_token"

read -p "ใส่ TOKEN: " TOKEN_INPUT

# ---------- RESET ----------
step "RESET PASSWORD"
reset_password "$TOKEN_INPUT" "$FINAL_PASS"
pass "RESET DONE"

# ---------- FAKE TOKEN ----------
step "RESET WITH FAKE TOKEN"
reset_password "fake123" "999999"
info "Should return error"

# ---------- LOGIN FINAL ----------
step "LOGIN FINAL"
TOKEN3=$(login "$FINAL_PASS")

if [ "$TOKEN3" = "null" ] || [ -z "$TOKEN3" ]; then
  fail "FINAL LOGIN FAILED"
  exit 1
else
  pass "FINAL LOGIN OK"
fi

# ---------- SHORT PASSWORD ----------
step "SHORT PASSWORD TEST"
change_password "$TOKEN3" "123"
info "Should fail validation"

# ---------- RESET BACK ----------
step "RESET BACK TO DEFAULT"
change_password "$TOKEN3" "$RESET_BACK_PASS"
pass "PASSWORD RESTORED TO 123456"

# ---------- FINAL LOGIN CHECK ----------
step "FINAL LOGIN CHECK"
TOKEN4=$(login "$RESET_BACK_PASS")

if [ "$TOKEN4" = "null" ] || [ -z "$TOKEN4" ]; then
  fail "RESTORE PASSWORD FAILED"
else
  pass "RESTORE PASSWORD SUCCESS"
fi

step "END TEST"




