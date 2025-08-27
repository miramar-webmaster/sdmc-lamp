#!/usr/bin/env bash
set -Eeuo pipefail

DB_NAME="${MYSQL_DATABASE:-drupal}"
BACKUPS_DIR="${DB_BACKUPS_DIR:-/srv/sdmc-miraweb/backups}"
MYSQL_SVC="mysql"

mkdir -p "$BACKUPS_DIR"

STAMP="$(date +%F-%H%M)"
OUT="$BACKUPS_DIR/${DB_NAME}-${STAMP}.sql.gz"
echo "Writing: $OUT"

docker compose exec -T "$MYSQL_SVC" \
  mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" \
  --single-transaction --routines --triggers "$DB_NAME" \
  | gzip > "$OUT"

echo "Backup complete: $OUT"
