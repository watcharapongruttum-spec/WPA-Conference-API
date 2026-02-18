#!/bin/bash

echo "========== GIT AUTO PUSH =========="

MAIN_BRANCH="main"

if [ -z "$1" ]; then
  echo "❌ กรุณาใส่ commit message"
  exit 1
fi

RAW_MSG=$1
DATE=$(date '+%Y-%m-%d %H:%M')
MSG="$RAW_MSG - $DATE"
BRANCH="temp-$(date +%H%M%S)"

echo "🧹 CLEAN TEMP FILES"
rm -f test_scripts/*.log
rm -f test_scripts/*.pid

if [ -z "$(git status --porcelain)" ]; then
  echo "⚠️ NOTHING TO COMMIT"
  exit 0
fi

echo "🌿 CREATE TEMP BRANCH"
git checkout -b $BRANCH

echo "📦 GIT ADD"
git add .

echo "📝 COMMIT: $MSG"
git commit -m "$MSG"

echo "🚀 PUSH TEMP BRANCH"
git push origin $BRANCH

echo "🔁 SWITCH BACK TO MAIN"
git checkout $MAIN_BRANCH

echo "⬇️ PULL LATEST MAIN"
git pull origin $MAIN_BRANCH

echo "🔀 MERGE TEMP INTO MAIN"
git merge $BRANCH --no-edit

echo "🚀 PUSH MAIN"
git push origin $MAIN_BRANCH

echo "🗑 DELETE TEMP BRANCH"
git branch -D $BRANCH
git push origin --delete $BRANCH

echo "========== DONE =========="
