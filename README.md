# Backup To FTP and SFTP

A lightweight Docker container that zips a mounted directory and uploads it to a remote server once per day.

Originally built to back up a self-hosted Minecraft world to an external server, but it can be used for any mounted directory.

Supports:

- FTP uploads
- SFTP uploads
- Daily scheduled backups
- Restart-safe scheduling
- Persistent backup state
- Persistent logging
- Automatic retry on upload failure
- Optional SFTP host key verification
- Optional SFTP private key authentication

## How it works

The container watches the configured backup time. Once per day, it:

1. Creates a `.zip` archive of the mounted backup directory.
2. Uploads the archive to the configured FTP or SFTP server.
3. Stores the last successful backup date in the persistent state directory.
4. Writes logs to the persistent state directory.

Backups are stored using this filename format:

```text
backup_YYYYMMDD_HHMMSS.zip
```

Example:

```text
backup_20260619_020001.zip
```

## Basic FTP usage

```bash
docker run -d \
  --name=BackupToFTP \
  -v /path/to/local/dir:/data/backup \
  -v /path/to/local/state:/var/lib/backup-state \
  -e TZ="Europe/London" \
  -e UPLOAD_PROTOCOL="ftp" \
  -e FTP_HOST="ftp.example.com" \
  -e FTP_USER="ftpuser" \
  -e FTP_PASS="ftppassword" \
  -e FTP_DIR="/backups" \
  -e BACKUP_TIME="02:00" \
  --restart=always \
  spkuja/backup-to-ftp
```

## Basic SFTP usage

```bash
docker run -d \
  --name=BackupToFTP \
  -v /path/to/local/dir:/data/backup \
  -v /path/to/local/state:/var/lib/backup-state \
  -e TZ="Europe/London" \
  -e UPLOAD_PROTOCOL="sftp" \
  -e FTP_HOST="sftp.example.com" \
  -e FTP_PORT="22" \
  -e FTP_USER="sftpuser" \
  -e FTP_PASS="sftppassword" \
  -e FTP_DIR="/backups" \
  -e BACKUP_TIME="02:00" \
  --restart=always \
  spkuja/backup-to-ftp
```

## Docker Compose example

```yaml
services:
  backup-to-ftp:
    image: spkuja/backup-to-ftp
    container_name: BackupToFTP
    restart: always
    environment:
      TZ: "Europe/London"
      UPLOAD_PROTOCOL: "sftp"
      FTP_HOST: "sftp.example.com"
      FTP_PORT: "22"
      FTP_USER: "sftpuser"
      FTP_PASS: "sftppassword"
      FTP_DIR: "/backups"
      BACKUP_TIME: "02:00"
    volumes:
      - /path/to/local/dir:/data/backup
      - /path/to/local/state:/var/lib/backup-state
```

## Environment variables

| Variable | Default | Required | Description |
|---|---:|:---:|---|
| `BACKUP_DIR` | `/data/backup` | Yes | Directory inside the container to zip and upload. Usually mounted from the host. |
| `UPLOAD_PROTOCOL` | `ftp` | Yes | Upload method. Supported values: `ftp` or `sftp`. |
| `FTP_HOST` | `ftp.example.com` | Yes | Remote FTP or SFTP host. |
| `FTP_PORT` | Empty | No | Optional remote port. FTP usually uses `21`; SFTP usually uses `22`. |
| `FTP_USER` | `ftpuser` | Yes | FTP or SFTP username. |
| `FTP_PASS` | `ftppassword` | Required for password auth | FTP or SFTP password. |
| `FTP_DIR` | `/` | Yes | Remote directory to upload backups into. |
| `BACKUP_TIME` | `02:00` | Yes | Daily backup time in `HH:MM` 24-hour format. |
| `TZ` | `Etc/UTC` | No | Container timezone used for scheduling. |
| `STATE_DIR` | `/var/lib/backup-state` | Yes | Directory used for logs, lock file and last-run state. Should be mounted persistently. |
| `SFTP_KNOWN_HOSTS` | Empty | Recommended for SFTP | Known hosts entry used to verify the SFTP server. |
| `SFTP_INSECURE` | `false` | No | Set to `true` to skip SFTP host key verification. Not recommended. |
| `SFTP_KEY_FILE` | Empty | No | Optional private key file path for SFTP key authentication. |
| `SFTP_KEY_PASSPHRASE` | Empty | No | Optional passphrase for the SFTP private key. |

## SFTP host key verification

For SFTP, host key verification is recommended.

From a trusted machine, get the server host key:

```bash
ssh-keyscan -p 22 sftp.example.com
```

Then pass the output into the container:

```bash
-e SFTP_KNOWN_HOSTS="sftp.example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA..."
```

Or in Docker Compose:

```yaml
environment:
  SFTP_KNOWN_HOSTS: "sftp.example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA..."
```

For quick testing only, you can disable host key verification:

```bash
-e SFTP_INSECURE="true"
```

This is not recommended for production use.

## SFTP private key authentication

Mount your private key into the container and set `SFTP_KEY_FILE`.

```bash
docker run -d \
  --name=BackupToFTP \
  -v /path/to/local/dir:/data/backup \
  -v /path/to/local/state:/var/lib/backup-state \
  -v /path/to/private/key:/run/secrets/sftp_key:ro \
  -e TZ="Europe/London" \
  -e UPLOAD_PROTOCOL="sftp" \
  -e FTP_HOST="sftp.example.com" \
  -e FTP_PORT="22" \
  -e FTP_USER="sftpuser" \
  -e SFTP_KEY_FILE="/run/secrets/sftp_key" \
  -e FTP_DIR="/backups" \
  -e BACKUP_TIME="02:00" \
  --restart=always \
  spkuja/backup-to-ftp
```

If your key has a passphrase:

```bash
-e SFTP_KEY_PASSPHRASE="your-passphrase"
```

## Volumes

| Container path | Description |
|---|---|
| `/data/backup` | The directory that will be zipped and uploaded. |
| `/var/lib/backup-state` | Persistent state, logs and lock file. |

The state directory should be mounted to the host so the container remembers whether today's backup has already completed.

## Logs

Logs are written to:

```text
/var/lib/backup-state/backup.log
```

You can also view live logs with:

```bash
docker logs -f BackupToFTP
```

## Backup scheduling

Set the daily backup time with:

```bash
-e BACKUP_TIME="02:00"
```

The value must be in 24-hour `HH:MM` format.

The timezone is controlled with:

```bash
-e TZ="Europe/London"
```

## Remote directory notes

`FTP_DIR` controls where the backup is uploaded.

Examples:

```bash
-e FTP_DIR="/backups"
```

```bash
-e FTP_DIR="/minecraft/world-backups"
```

Some SFTP providers use a chrooted root directory, so `/backups` may not mean the server's real filesystem root. If your provider expects paths relative to the user home, try:

```bash
-e FTP_DIR="/~/backups"
```

## Example: backing up a Minecraft world

```bash
docker run -d \
  --name=BackupToFTP \
  -v /home/minecraft/worlds/Glaciercraft:/data/backup \
  -v /home/minecraft/backup-state:/var/lib/backup-state \
  -e TZ="Europe/London" \
  -e UPLOAD_PROTOCOL="sftp" \
  -e FTP_HOST="sftp.example.com" \
  -e FTP_PORT="22" \
  -e FTP_USER="backupuser" \
  -e FTP_PASS="backuppassword" \
  -e FTP_DIR="/minecraft-backups" \
  -e BACKUP_TIME="02:00" \
  --restart=always \
  spkuja/backup-to-ftp
```

## Notes

- The container creates one backup per day.
- If the container restarts, it will not duplicate a completed backup for the same day.
- If an upload fails, the container will retry later.
- Backups are created temporarily inside the container and removed after a successful upload.
- For SFTP, host key verification should be configured for production use.
