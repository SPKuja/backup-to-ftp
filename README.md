# backup-to-ftp
Simple docker container to backup a directory to FTP as a zip file.

Run with

 <code>docker run &#92;<br>
--name=BackupToFTP &#92;<br>
-v /path/to/local/dir:/data/backup &#92;<br>
-e FTP_HOST="ftp.example.com" &#92;<br>
-e FTP_USER="ftpuser" &#92;<br>
-e FTP_PASS="ftppassword" &#92;<br>
-e FTP_DIR="/backups" &#92;<br>
-e BACKUP_TIME="02:00" &#92;<br>
--restart=always &#92;<br>
spkuja/backup-to-ftp</code>
