FROM ubuntu:24.04

ENV BACKUP_DIR="/data/backup" \
    FTP_HOST="ftp.example.com" \
    FTP_USER="ftpuser" \
    FTP_PASS="ftppassword" \
    FTP_DIR="/" \
    BACKUP_TIME="02:00" \
    TZ="Etc/UTC" \
    STATE_DIR="/var/lib/backup-state"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash ca-certificates curl zip tzdata util-linux && \
    rm -rf /var/lib/apt/lists/*

RUN cat > /usr/local/bin/backup_and_upload.sh <<'EOF'
#!/usr/bin/env bash
set -Euo pipefail

: "${STATE_DIR:=/var/lib/backup-state}"
mkdir -p "$STATE_DIR"
LOG_FILE="$STATE_DIR/backup.log"

log() {
  local msg="[$(date -Is)] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

trap 'rc=$?; log "ERROR rc=$rc at line ${LINENO}: ${BASH_COMMAND}"; exit $rc' ERR

: "${BACKUP_DIR:?BACKUP_DIR is required}"
: "${FTP_HOST:?FTP_HOST is required}"
: "${FTP_USER:?FTP_USER is required}"
: "${FTP_PASS:?FTP_PASS is required}"
: "${FTP_DIR:?FTP_DIR is required}"
: "${BACKUP_TIME:?BACKUP_TIME is required}"

log "STARTING backup container"
log "BACKUP_DIR=$BACKUP_DIR"
log "FTP_HOST=$FTP_HOST FTP_DIR=$FTP_DIR"
log "BACKUP_TIME=$BACKUP_TIME TZ=${TZ:-unset} STATE_DIR=$STATE_DIR"
log "Current container time: $(date -Is)"
log "Log file: $LOG_FILE"

LAST_RUN_FILE="$STATE_DIR/last_run_date"
LOCK_FILE="$STATE_DIR/lock"

if [[ ! "$BACKUP_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  log "ERROR: BACKUP_TIME must be HH:MM (24h). Got: $BACKUP_TIME"
  exit 1
fi

today() { date +%F; }
now_epoch() { date +%s; }

today_backup_epoch() {
  date -d "$(today) $BACKUP_TIME:00" +%s
}

get_last_run() {
  cat "$LAST_RUN_FILE" 2>/dev/null || true
}

set_last_run() {
  printf '%s\n' "$1" > "$LAST_RUN_FILE"
}

next_run_epoch() {
  local now target
  now="$(now_epoch)"
  target="$(today_backup_epoch)"
  if (( now <= target )); then
    echo "$target"
  else
    date -d "tomorrow $BACKUP_TIME:00" +%s
  fi
}

do_backup_and_upload() {
  local stamp backup_name backup_path ftp_url
  stamp="$(date +%Y%m%d_%H%M%S)"
  backup_name="backup_${stamp}.zip"
  backup_path="/tmp/${backup_name}"
  ftp_url="ftp://${FTP_HOST}${FTP_DIR%/}/${backup_name}"

  if [[ ! -d "$BACKUP_DIR" ]]; then
    log "ERROR: BACKUP_DIR does not exist: $BACKUP_DIR"
    return 1
  fi

  log "Creating zip from $BACKUP_DIR -> $backup_path"
  # Zip the contents from inside the directory (more reliable for odd paths/symlinks)
  ( cd "$BACKUP_DIR" && zip -r "$backup_path" . ) >/dev/null

  log "Zip created: $backup_path ($(du -h "$backup_path" | awk '{print $1}'))"

  log "Uploading -> $ftp_url"
  curl --fail --ftp-create-dirs \
       --retry 5 --retry-delay 10 --retry-connrefused \
       -T "$backup_path" -u "$FTP_USER:$FTP_PASS" \
       "$ftp_url"

  rm -f "$backup_path"
  log "Backup completed successfully"
  return 0
}

# Acquire lock WITHOUT exiting (prevents restart loop)
exec 9>"$LOCK_FILE"
until flock -n 9; do
  log "Lock busy or unavailable; waiting 10s..."
  sleep 10
done
log "Lock acquired."

# Main loop with heartbeat every 60s
while true; do
  last="$(get_last_run)"
  tdy="$(today)"
  now="$(now_epoch)"
  target="$(today_backup_epoch)"

  if [[ "$last" != "$tdy" ]] && (( now >= target )); then
    log "Backup due (last run: ${last:-never}). Running now."
    if do_backup_and_upload; then
      set_last_run "$tdy"
      log "Marked last run date as $tdy"
    else
      log "Backup/upload failed; will retry later."
    fi
  else
    log "Heartbeat: not due yet. last_run=${last:-none} today=$tdy scheduled_today=$(date -d "@$target" -Is)"
  fi

  sleep 60
done
EOF

RUN sed -i 's/\r$//' /usr/local/bin/backup_and_upload.sh && \
    chmod +x /usr/local/bin/backup_and_upload.sh && \
    mkdir -p "$STATE_DIR" && \
    mkdir -p "$BACKUP_DIR"

VOLUME ["/data/backup", "/var/lib/backup-state"]

ENTRYPOINT ["bash", "/usr/local/bin/backup_and_upload.sh"]
