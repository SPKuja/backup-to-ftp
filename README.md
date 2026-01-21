# backup-to-ftp
A lightweight Docker container that zips a mounted directory and uploads it to FTP once per day, with restart-safe scheduling and persistent logging. Born out of the requirement to back up a self-hosted Minecraft world to an external server. 

Run with

<code>docker run -d &#92;<br>
  --name=BackupToFTP &#92;<br>
  -v /path/to/local/dir:/data/backup &#92;<br>
  -v /path/to/local/state:/var/lib/backup-state &#92;<br>
  -e TZ="Europe/London" &#92;<br>
  -e FTP_HOST="ftp.example.com" &#92;<br>
  -e FTP_USER="ftpuser" &#92;<br>
  -e FTP_PASS="ftppassword" &#92;<br>
  -e FTP_DIR="/backups" &#92;<br>
  -e BACKUP_TIME="02:00" &#92;<br>
  --restart=always &#92;<br>
  spkuja/backup-to-ftp</code>

