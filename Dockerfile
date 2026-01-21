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
      ca-certificates curl zip tzdata util-linux && \
    rm -rf /var/lib/apt/lists/*

# Create the backup script inside the image (no separate file needed)
RUN cat > /usr/local/bin/backup_and_upload.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date -Is)] $*"; }

: "${BACKUP_DIR:?BACKUP_DIR is required}"
: "${FTP_HOST:?FTP_HOST is required}"
: "${FTP_USER:?FTP_USER is required}"
: "${FTP_PASS:?FTP_PASS is required}"
: "${FTP_DIR:?FTP_DIR is required}"
: "${BACKUP_TIME:?BACKUP_TIME is required}"
: "${STATE_DIR:=/var/lib/backup-state}"

LAST_RUN_FILE="$STATE_DIR/last_run_date"
LOCK_FILE="$STATE_DIR/lock"

mkdir -p "$STATE_DIR"

# Prevent concurrent runs (e.g., restart during a backup)
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "Another backup process is running; exiting."
  exit 0
fi

# Validate BACKUP_TIME format HH:MM (24h)
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
    exit 1
  fi

  log "Creating zip from $BACKUP_DIR -> $backup_path"
  zip -r -y "$backup_path" "$BACKUP_DIR" >/dev/null

  log "Uploading -> $ftp_url"
  curl --fail --ftp-create-dirs \
       --retry 5 --retry-delay 10 --retry-connrefused \
       -T "$backup_path" -u "$FTP_USER:$FTP_PASS" \
       "$ftp_url"

  rm -f "$backup_path"
  log "Done."
}

while true; do
  last="$(get_last_run)"
  tdy="$(today)"
  now="$(now_epoch)"
  target="$(today_backup_epoch)"

  # If we've passed today's scheduled time and haven't run today, run now.
  if [[ "$last" != "$tdy" ]] && (( now >= target )); then
    log "Backup due (last run: ${last:-never}). Running now."
    do_backup_and_upload
    set_last_run "$tdy"
  fi

  # Sleep until the next scheduled time (no fragile minute polling)
  next="$(next_run_epoch)"
  sleep_for=$(( next - $(now_epoch) ))
  if (( sleep_for < 1 )); then sleep_for=1; fi
  log "Next run at $(date -d "@$next" -Is). Sleeping ${sleep_for}s."
  sleep "$sleep_for"
done
EOF

RUN chmod +x /usr/local/bin/backup_and_upload.sh && \
    mkdir -p "$STATE_DIR" && \
    mkdir -p "$BACKUP_DIR"

VOLUME ["/data/backup", "/var/lib/backup-state"]

ENTRYPOINT ["/usr/local/bin/backup_and_upload.sh"]
