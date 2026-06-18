FROM ubuntu:24.04

ENV BACKUP_DIR="/data/backup" \
    UPLOAD_PROTOCOL="ftp" \
    FTP_HOST="ftp.example.com" \
    FTP_PORT="" \
    FTP_USER="ftpuser" \
    FTP_PASS="ftppassword" \
    FTP_DIR="/" \
    SFTP_KNOWN_HOSTS="" \
    SFTP_INSECURE="false" \
    SFTP_KEY_FILE="" \
    SFTP_KEY_PASSPHRASE="" \
    BACKUP_TIME="02:00" \
    TZ="Etc/UTC" \
    STATE_DIR="/var/lib/backup-state"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash ca-certificates curl zip tzdata util-linux openssh-client && \
    rm -rf /var/lib/apt/lists/*

COPY backup_and_upload.sh /usr/local/bin/backup_and_upload.sh

RUN sed -i 's/\r$//' /usr/local/bin/backup_and_upload.sh && \
    chmod +x /usr/local/bin/backup_and_upload.sh && \
    mkdir -p "$STATE_DIR" && \
    mkdir -p "$BACKUP_DIR" && \
    test -s /usr/local/bin/backup_and_upload.sh && \
    grep -q "while true" /usr/local/bin/backup_and_upload.sh && \
    grep -q "UPLOAD_PROTOCOL" /usr/local/bin/backup_and_upload.sh && \
    grep -q "SFTP_INSECURE" /usr/local/bin/backup_and_upload.sh

VOLUME ["/data/backup", "/var/lib/backup-state"]

ENTRYPOINT ["bash", "/usr/local/bin/backup_and_upload.sh"]
