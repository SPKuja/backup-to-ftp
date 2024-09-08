# Base image
FROM ubuntu:latest

# Set default environment variables for FTP and backup directory
ENV BACKUP_DIR="/data/backup" \
    FTP_HOST="ftp.example.com" \
    FTP_USER="ftpuser" \
    FTP_PASS="ftppassword" \
    FTP_DIR="/" \
    BACKUP_TIME="02:00"  # Default backup time is 2 AM

# Install required packages
RUN apt-get update && \
    apt-get install -y curl zip && \
    rm -rf /var/lib/apt/lists/*

# Create the backup script directly within the Dockerfile
RUN echo '#!/bin/bash\n' \
    'while true; do\n' \
    '    CURRENT_TIME=$(date +%H:%M)\n' \
    '    if [ "$CURRENT_TIME" == "$BACKUP_TIME" ]; then\n' \
    '        BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S).zip"\n' \
    '        BACKUP_PATH="/tmp/$BACKUP_NAME"\n' \
    '        echo "Creating backup of $BACKUP_DIR..."\n' \
    '        zip -r "$BACKUP_PATH" "$BACKUP_DIR"\n' \
    '        if [ $? -eq 0 ]; then\n' \
    '            echo "Backup created successfully: $BACKUP_PATH"\n' \
    '        else\n' \
    '            echo "Error creating backup"\n' \
    '            exit 1\n' \
    '        fi\n' \
    '        echo "Uploading $BACKUP_NAME to FTP server $FTP_HOST..."\n' \
    '        curl -T "$BACKUP_PATH" -u "$FTP_USER:$FTP_PASS" "ftp://$FTP_HOST$FTP_DIR/$BACKUP_NAME"\n' \
    '        if [ $? -eq 0 ]; then\n' \
    '            echo "Backup uploaded successfully to FTP server"\n' \
    '        else\n' \
    '            echo "Error uploading backup to FTP server"\n' \
    '            exit 1\n' \
    '        fi\n' \
    '        rm "$BACKUP_PATH"\n' \
    '        echo "Backup and upload process completed."\n' \
    '        sleep 60  # Sleep for 1 minute to prevent multiple backups at the same time\n' \
    '    else\n' \
    '        echo "Waiting for $BACKUP_TIME... (current time is $CURRENT_TIME)"\n' \
    '        sleep 60  # Sleep for 1 minute before checking the time again\n' \
    '    fi\n' \
    'done\n' \
    > /usr/local/bin/backup_and_upload.sh

# Make the script executable
RUN chmod +x /usr/local/bin/backup_and_upload.sh

# Create a directory to be backed up (can be replaced with a volume)
RUN mkdir -p $BACKUP_DIR

# Set the entrypoint to run the backup script
ENTRYPOINT ["/usr/local/bin/backup_and_upload.sh"]
