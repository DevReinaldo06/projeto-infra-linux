#!/bin/bash
set -euo pipefail
umask 077

BACKUP_DIR="/var/backups/postgresql"
DB_NAME="appdb"

SMB_SHARE="//arquivos.empresa.local/backups"
SMB_CRED="/etc/backup/smb.cred"

exec >> /var/log/backup-postgres/backup.log 2>&1
trap  'echo "$(date -Is) ERRO na linha $LINENO" >&2' ERR
echo "$(date -Is) INICIO do backup"

exec 9>"$BACKUP_DIR/backup.lock"
flock -n 9 || exit 0

find "$BACKUP_DIR" -maxdepth 1 -type f -name 'appdb-*.sql' -mmin +10080 -delete
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'appdb-*.tar.gz' -mmin +10080 -delete

STAMP=$(date +%Y%m%d_%H%M%S)
BASE="$DB_NAME-$STAMP"

SQL_FILE="$BACKUP_DIR/$BASE.sql"
ARCHIVE="$BACKUP_DIR/$BASE.tar.gz"

pg_dump -Fp --no-owner "$DB_NAME" > "$SQL_FILE"
test -s "$SQL_FILE"
tar -czf "$ARCHIVE" -C "$BACKUP_DIR" "$BASE.sql"
tar -tzf "$ARCHIVE" > /dev/null

echo "$(date -Is) SUCESSO backup local: $ARCHIVE"

if timeout 60 smbclient "$SMB_SHARE" -A "$SMB_CRED" -c "put $ARCHIVE $BASE.tar.gz"; then
rm -- "$SQL_FILE" "$ARCHIVE"

    echo "$(date -Is) SUCESSO envio SMB: $BASE.tar.gz"
else
    echo "$(date -Is) ERRO no envio SMB; backup local preservado"
    exit 1
fi

