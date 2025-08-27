#!/usr/bin/env bash
set -Eeuo pipefail

# Usage:
#   bash scripts/db-refresh.sh                # restore from newest *.sql[.gz] in $DB_BACKUPS_DIR
#   bash scripts/db-refresh.sh /path/dump.sql.gz   # restore from a specific file

# --- config from .env (or fallbacks) ---
DB_NAME="${MYSQL_DATABASE:-drupal}"
BACKUPS_DIR="${DB_BACKUPS_DIR:-/srv/sdmc-miraweb/backups}"

# compose service names
MYSQL_SVC="mysql"
WEB_SVC="php81-apache"

die() { echo "ERROR: $*" >&2; exit 1; }

# Resolve dump file
DUMP="${1-}"
if [[ -z "$DUMP" ]]; then
  # newest *.sql or *.sql.gz in BACKUPS_DIR
  DUMP="$(ls -1t "$BACKUPS_DIR"/*.sql "$BACKUPS_DIR"/*.sql.gz 2>/dev/null | head -n1 || true)"
  [[ -n "$DUMP" ]] || die "No .sql or .sql.gz found in $BACKUPS_DIR"
else
  [[ -f "$DUMP" ]] || die "Dump not found: $DUMP"
fi

echo "Using dump: $DUMP"
echo "Target DB:  $DB_NAME"

# Ensure MySQL is up
echo "Bringing up MySQL…"
docker compose up -d "$MYSQL_SVC" >/dev/null

echo "Waiting for MySQL to accept connections…"
until docker compose exec -T "$MYSQL_SVC" \
  mysqladmin ping -uroot -p"$MYSQL_ROOT_PASSWORD" --silent; do
  sleep 2
done

# Safety: make a quick backup of current DB before wiping
STAMP="$(date +%F-%H%M%S)"
SAFETY="$BACKUPS_DIR/auto-backup-${DB_NAME}-${STAMP}.sql.gz"
echo "Creating safety backup: $SAFETY"
docker compose exec -T "$MYSQL_SVC" \
  mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" \
  --single-transaction --routines --triggers "$DB_NAME" 2>/dev/null \
  | gzip > "$SAFETY" || echo "WARN: safety backup may be empty (first load?)"

# Drop + recreate DB with utf8mb4
echo "Recreating database $DB_NAME…"
docker compose exec -T "$MYSQL_SVC" \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e \
  "DROP DATABASE IF EXISTS \`$DB_NAME\`;
   CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Import
echo "Importing… (this can take a while)"
if [[ "$DUMP" == *.gz ]]; then
  zcat "$DUMP" | docker compose exec -T "$MYSQL_SVC" \
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$DB_NAME"
else
  docker compose exec -T "$MYSQL_SVC" \
    sh -lc 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" '"$DB_NAME" < /dev/stdin \
    < "$DUMP"
fi

echo "Import complete."

# Optional: post-restore Drupal maintenance
if docker compose ps "$WEB_SVC" --status running >/dev/null 2>&1; then
  echo "Clearing Drupal caches…"
  docker compose exec -T "$WEB_SVC" bash -lc '
    set -e
    cd /var/www/miraweb2024 || cd /var/www/app || exit 1
    if [ -x vendor/bin/drush ]; then
      vendor/bin/drush cr || true
      # Uncomment if you want to run DB updates automatically:
      # vendor/bin/drush updb -y || true
    fi
  ' || true
fi

echo "Done."
