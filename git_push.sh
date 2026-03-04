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

RAW_MSG=$1
DATE=$(date '+%Y-%m-%d %H:%M')
MSG="$RAW_MSG - $DATE"

# ---------------- CLEAN LOG FILES ----------------
echo "🧹 CLEAN TEMP FILES"
rm -f test_scripts/*.log
rm -f test_scripts/*.pid

# ---------------- CHECK CHANGES ----------------
if [ -z "$(git status --porcelain)" ]; then
  echo "⚠️  NOTHING TO COMMIT"
  exit 0
fi

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
