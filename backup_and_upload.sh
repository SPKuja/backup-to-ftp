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
: "${UPLOAD_PROTOCOL:=ftp}"
: "${FTP_HOST:?FTP_HOST is required}"
: "${FTP_USER:?FTP_USER is required}"
: "${FTP_DIR:?FTP_DIR is required}"
: "${BACKUP_TIME:?BACKUP_TIME is required}"

UPLOAD_PROTOCOL="$(echo "$UPLOAD_PROTOCOL" | tr '[:upper:]' '[:lower:]')"

case "$UPLOAD_PROTOCOL" in
  ftp|sftp)
    ;;
  *)
    log "ERROR: UPLOAD_PROTOCOL must be either 'ftp' or 'sftp'. Got: $UPLOAD_PROTOCOL"
    exit 1
    ;;
esac

if [[ "$UPLOAD_PROTOCOL" == "ftp" ]]; then
  : "${FTP_PASS:?FTP_PASS is required for FTP}"
fi

if [[ "$UPLOAD_PROTOCOL" == "sftp" && -z "${FTP_PASS:-}" && -z "${SFTP_KEY_FILE:-}" ]]; then
  log "ERROR: SFTP requires either FTP_PASS for password auth or SFTP_KEY_FILE for key auth."
  exit 1
fi

log "STARTING backup container"
log "BACKUP_DIR=$BACKUP_DIR"
log "UPLOAD_PROTOCOL=$UPLOAD_PROTOCOL"
log "FTP_HOST=$FTP_HOST FTP_PORT=${FTP_PORT:-default} FTP_DIR=$FTP_DIR"
log "BACKUP_TIME=$BACKUP_TIME TZ=${TZ:-unset} STATE_DIR=$STATE_DIR"
log "Current container time: $(date -Is)"
log "Log file: $LOG_FILE"

LAST_RUN_FILE="$STATE_DIR/last_run_date"
LOCK_FILE="$STATE_DIR/lock"

if [[ ! "$BACKUP_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  log "ERROR: BACKUP_TIME must be HH:MM (24h). Got: $BACKUP_TIME"
  exit 1
fi

today() {
  date +%F
}

now_epoch() {
  date +%s
}

today_backup_epoch() {
  date -d "$(today) $BACKUP_TIME:00" +%s
}

get_last_run() {
  cat "$LAST_RUN_FILE" 2>/dev/null || true
}

set_last_run() {
  printf '%s\n' "$1" > "$LAST_RUN_FILE"
}

normalise_remote_dir() {
  local dir="${FTP_DIR:-/}"

  if [[ -z "$dir" ]]; then
    dir="/"
  fi

  if [[ "$dir" != /* ]]; then
    dir="/$dir"
  fi

  if [[ "$dir" == "/" ]]; then
    echo ""
  else
    echo "${dir%/}"
  fi
}

build_upload_url() {
  local backup_name="$1"
  local remote_dir port_part

  remote_dir="$(normalise_remote_dir)"

  if [[ -n "${FTP_PORT:-}" ]]; then
    port_part=":$FTP_PORT"
  else
    port_part=""
  fi

  echo "${UPLOAD_PROTOCOL}://${FTP_HOST}${port_part}${remote_dir}/${backup_name}"
}

prepare_sftp_security() {
  if [[ "$UPLOAD_PROTOCOL" != "sftp" ]]; then
    return 0
  fi

  mkdir -p /root/.ssh
  chmod 700 /root/.ssh

  if [[ -n "${SFTP_KNOWN_HOSTS:-}" ]]; then
    printf '%s\n' "$SFTP_KNOWN_HOSTS" > /root/.ssh/known_hosts
    chmod 600 /root/.ssh/known_hosts
    log "SFTP known_hosts configured from SFTP_KNOWN_HOSTS."
    return 0
  fi

  if [[ -s /root/.ssh/known_hosts ]]; then
    log "SFTP known_hosts already exists."
    return 0
  fi

  if [[ "${SFTP_INSECURE:-false}" == "true" ]]; then
    log "WARNING: SFTP_INSECURE=true. Host key verification will be skipped. This is not recommended."
    return 0
  fi

  log "ERROR: SFTP selected but no host key is configured."
  log "Set SFTP_KNOWN_HOSTS using something like:"
  log "ssh-keyscan -p ${FTP_PORT:-22} $FTP_HOST"
  log "Or, less safely, set SFTP_INSECURE=true."
  return 1
}

do_backup_and_upload() {
  local stamp backup_name backup_path upload_url size
  stamp="$(date +%Y%m%d_%H%M%S)"
  backup_name="backup_${stamp}.zip"
  backup_path="/tmp/${backup_name}"
  upload_url="$(build_upload_url "$backup_name")"

  if [[ ! -d "$BACKUP_DIR" ]]; then
    log "ERROR: BACKUP_DIR does not exist: $BACKUP_DIR"
    return 1
  fi

  prepare_sftp_security

  log "Creating zip from $BACKUP_DIR -> $backup_path"

  if ! ( cd "$BACKUP_DIR" && zip -r "$backup_path" . ) >/dev/null; then
    log "ERROR: Failed to create zip from $BACKUP_DIR"
    rm -f "$backup_path"
    return 1
  fi

  size="$(du -h "$backup_path" | awk '{print $1}')"
  log "Zip created: $backup_path ($size)"

  log "Uploading -> $upload_url"

  curl_args=(
    --fail
    --ftp-create-dirs
    --retry 5
    --retry-delay 10
    --retry-connrefused
    -T "$backup_path"
    -u "$FTP_USER:${FTP_PASS:-}"
  )

  if [[ "$UPLOAD_PROTOCOL" == "sftp" ]]; then
    if [[ "${SFTP_INSECURE:-false}" == "true" ]]; then
      curl_args+=(--insecure)
    fi

    if [[ -n "${SFTP_KEY_FILE:-}" ]]; then
      if [[ ! -f "$SFTP_KEY_FILE" ]]; then
        log "ERROR: SFTP_KEY_FILE does not exist: $SFTP_KEY_FILE"
        return 1
      fi

      chmod 600 "$SFTP_KEY_FILE" || true
      curl_args+=(--key "$SFTP_KEY_FILE")

      if [[ -n "${SFTP_KEY_PASSPHRASE:-}" ]]; then
        curl_args+=(--pass "$SFTP_KEY_PASSPHRASE")
      fi
    fi
  fi

  if ! curl "${curl_args[@]}" "$upload_url"; then
    log "ERROR: Upload failed"
    rm -f "$backup_path"
    return 1
  fi

  rm -f "$backup_path"
  log "Backup completed successfully"
  return 0
}

exec 9>"$LOCK_FILE"

until flock -n 9; do
  log "Lock busy or unavailable; waiting 10s..."
  sleep 10
done

log "Lock acquired."

while true; do
  last="$(get_last_run)"
  tdy="$(today)"
  now="$(now_epoch)"
  target="$(today_backup_epoch)"

  if [[ "$last" != "$tdy" ]] && (( now >= target )); then
    log "Backup due. Last run: ${last:-never}. Running now."

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
