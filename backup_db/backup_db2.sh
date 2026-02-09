#!/bin/bash
set -e

# ================= CONFIG =================
CONTAINER_NAME="my-postgres-17"
LOCAL_DB_NAME="wpa_development"
LOCAL_DB_USER="postgres"

RENDER_DB_URL="postgresql://wpa_db_546549_user:2JZT9jTBdGh7cWQJj4va3fnIHtfJ26He@dpg-d6079ba4d50c73clrnh0-a.singapore-postgres.render.com/wpa_db_546549"

BACKUP_DIR="./backups"
LOG_DIR="./logs"


DATE=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE="$BACKUP_DIR/${LOCAL_DB_NAME}_${DATE}.dump"
LOG_FILE="$LOG_DIR/sync_${DATE}.log"

# ================= PREPARE =================
mkdir -p "$BACKUP_DIR"
mkdir -p "$LOG_DIR"

START_TIME=$(date +%s)

log() {
  echo -e "$1"
  echo "$(date '+%F %T') | $1" >> "$LOG_FILE"
}

step() {
  log "\n========== $1 =========="
}

progress() {
  log "Progress: $1%"
}

# ================= START =================
log "=== SYNC START ==="
progress 0

# ================= STEP 1 BACKUP =================
step "STEP 1 BACKUP LOCAL DB"
progress 5

log "Running pg_dump -Fc from Docker..."
docker exec -t $CONTAINER_NAME pg_dump -Fc -U $LOCAL_DB_USER $LOCAL_DB_NAME > "$BACKUP_FILE"

log "Backup file created: $BACKUP_FILE"
progress 25

SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
log "Backup size: $SIZE"
progress 30

# ================= STEP 2 CLEAR RENDER =================
step "STEP 2 CLEAR RENDER DB"
progress 40

log "Dropping public schema..."
psql "$RENDER_DB_URL" <<EOF >> "$LOG_FILE" 2>&1
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
EOF

log "Render DB cleared"
progress 55

# ================= STEP 3 RESTORE =================
step "STEP 3 RESTORE TO RENDER"
progress 60

log "Starting pg_restore..."

pg_restore \
  --clean \
  --no-owner \
  --verbose \
  -d "$RENDER_DB_URL" \
  "$BACKUP_FILE" >> "$LOG_FILE" 2>&1

progress 90
log "Restore completed"

# ================= STEP 4 CLEAN OLD =================
step "STEP 4 CLEAN OLD BACKUPS"
progress 95

find "$BACKUP_DIR" -type f -name "*.dump" -mtime +7 -delete
log "Old backups cleaned"

progress 100

# ================= END =================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log "\n=== DONE ==="
log "Total Time: ${DURATION}s"
log "Backup Size: $SIZE"
log "Log File: $LOG_FILE"
