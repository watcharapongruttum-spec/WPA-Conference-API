#!/bin/bash

echo "========== GIT AUTO PUSH =========="

# ---------------- CONFIG ----------------
BRANCH="main"

# ---------------- CHECK MESSAGE ----------------
if [ -z "$1" ]; then
  echo "❌ กรุณาใส่ commit message"
  echo "ตัวอย่าง: ./git_push.sh \"fix auto seen\""
  exit 1
fi

MSG=$1

# ---------------- CLEAN LOG FILES ----------------
echo "🧹 CLEAN TEMP FILES"

rm -f test_scripts/*.log
rm -f test_scripts/*.pid

# ---------------- GIT ADD ----------------
echo "📦 GIT ADD"
git add .

# ---------------- COMMIT ----------------
echo "📝 COMMIT: $MSG"
git commit -m "$MSG"

# ---------------- PUSH ----------------
echo "🚀 PUSH TO $BRANCH"
git push origin $BRANCH

echo "========== DONE =========="
