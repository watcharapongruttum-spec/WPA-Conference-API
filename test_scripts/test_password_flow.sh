#!/bin/bash
set +e

BASE_URL="http://localhost:3000"

EMAIL="65011213056@msu.ac.th"
OLD_PASS="123456"
NEW_PASS="65432100"
FINAL_PASS="11111111"
RESET_BACK_PASS="12345678"

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
    -d "{\"email\":\"$EMAIL\",\"password\":\"$1\"}"
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
    -d "{\"current_password\":\"$2\",\"new_password\":\"$3\"}"
}

extract_token() {
  echo "$1" | jq -r '.token'
}

has_error() {
  echo "$1" | grep -q '"error"'
}

# ================= START =================

step "LOGIN OLD PASSWORD"
RESP=$(login "$OLD_PASS")
TOKEN=$(extract_token "$RESP")

if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
  fail "LOGIN FAILED"
  echo $RESP
  exit 1
else
  pass "LOGIN OK"
fi

step "LOGIN WRONG PASSWORD"
RESP=$(login "wrongpass")
TOKEN_WRONG=$(extract_token "$RESP")

if [ "$TOKEN_WRONG" = "null" ] || [ -z "$TOKEN_WRONG" ]; then
  pass "WRONG PASSWORD BLOCKED"
else
  fail "WRONG PASSWORD SHOULD FAIL"
fi

step "CHANGE PASSWORD"
RESP=$(change_password "$TOKEN" "$OLD_PASS" "$NEW_PASS")
echo $RESP

if has_error "$RESP"; then
  fail "CHANGE PASSWORD FAILED"
  exit 1
else
  pass "CHANGE PASSWORD DONE"
fi

step "LOGIN WITH NEW PASSWORD"
RESP=$(login "$NEW_PASS")
TOKEN2=$(extract_token "$RESP")

if [ "$TOKEN2" = "null" ] || [ -z "$TOKEN2" ]; then
  fail "NEW PASSWORD LOGIN FAILED"
  exit 1
else
  pass "NEW PASSWORD LOGIN OK"
fi

step "FORGOT PASSWORD"
RESP=$(forgot_password)
echo $RESP
pass "FORGOT SENT"

info "ไปดู token ใน rails c"
info "Delegate.find_by(email: '$EMAIL').reset_password_token"
read -p "ใส่ TOKEN: " TOKEN_INPUT

step "RESET PASSWORD"
RESP=$(reset_password "$TOKEN_INPUT" "$FINAL_PASS")
echo $RESP

if has_error "$RESP"; then
  fail "RESET FAILED"
  exit 1
else
  pass "RESET DONE"
fi

step "LOGIN FINAL"
RESP=$(login "$FINAL_PASS")
TOKEN3=$(extract_token "$RESP")

if [ "$TOKEN3" = "null" ] || [ -z "$TOKEN3" ]; then
  fail "FINAL LOGIN FAILED"
  exit 1
else
  pass "FINAL LOGIN OK"
fi

step "RESET BACK TO DEFAULT"
RESP=$(change_password "$TOKEN3" "$FINAL_PASS" "$RESET_BACK_PASS")
echo $RESP

if has_error "$RESP"; then
  fail "RESTORE PASSWORD FAILED"
  exit 1
else
  pass "PASSWORD RESTORED"
fi

step "END TEST"



