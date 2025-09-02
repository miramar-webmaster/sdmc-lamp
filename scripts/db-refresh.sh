#!/usr/bin/env bash
# db-refresh (sdmiramar-fixed) — import exactly sdmiramar.sql(.gz) into the target DB

set -Eeuo pipefail
die(){ echo "ERROR: $*" >&2; exit 1; }

# --- Load .env (if present) ---
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

# --- Config (env or defaults) ---
DB_NAME="${MYSQL_DATABASE:-sdmc}"
BACKUPS_DIR="${DB_BACKUPS_DIR:-/srv/sdmc-miraweb/backups}"
# Prefer your .env names:
MYSQL_SVC="${MYSQL_SERVICE:-mysql}"         # DB service name in docker-compose.yml
WEB_SVC="${WEB_SERVICE:-php81-apache}"      # Web service for optional drush
DUMP_BASENAME="${DUMP_BASENAME:-sdmiramar.sql}"  # fixed dump name (without .gz by default)

# Allow an explicit path as arg (wins), otherwise look for sdmiramar.sql(.gz) in BACKUPS_DIR
if [[ $# -gt 0 ]]; then
  DUMP="$1"
else
  if [[ -f "$BACKUPS_DIR/${DUMP_BASENAME}.gz" ]]; then
    DUMP="$BACKUPS_DIR/${DUMP_BASENAME}.gz"
  elif [[ -f "$BACKUPS_DIR/${DUMP_BASENAME}" ]]; then
    DUMP="$BACKUPS_DIR/${DUMP_BASENAME}"
  else
    die "Could not find $BACKUPS_DIR/${DUMP_BASENAME}{,.gz}"
  fi
fi
[[ -f "$DUMP" ]] || die "Dump not found: $DUMP"

echo "Using dump: $DUMP"
echo "Target DB:  $DB_NAME"
echo "Service:    $MYSQL_SVC"

# --- Resolve MySQL/MariaDB root password from inside container ---
echo "Resolving DB root password…"
docker compose up -d "$MYSQL_SVC" >/dev/null
MYSQL_ROOT_PASSWORD="$(
  docker compose exec -T "$MYSQL_SVC" sh -lc '
    set -e
    # Direct envs
    if [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then printf "%s" "$MYSQL_ROOT_PASSWORD"; exit 0; fi
    if [ -n "${MARIADB_ROOT_PASSWORD:-}" ]; then printf "%s" "$MARIADB_ROOT_PASSWORD"; exit 0; fi
    # *_FILE envs
    if [ -n "${MYSQL_ROOT_PASSWORD_FILE:-}" ] && [ -f "$MYSQL_ROOT_PASSWORD_FILE" ]; then cat "$MYSQL_ROOT_PASSWORD_FILE"; exit 0; fi
    if [ -n "${MARIADB_ROOT_PASSWORD_FILE:-}" ] && [ -f "$MARIADB_ROOT_PASSWORD_FILE" ]; then cat "$MARIADB_ROOT_PASSWORD_FILE"; exit 0; fi
    # Common secret mount
    if [ -f /run/secrets/mysql_root_password ]; then cat /run/secrets/mysql_root_password; exit 0; fi
    exit 3
  ' 2>/dev/null || true
)"
[[ -n "$MYSQL_ROOT_PASSWORD" ]] || die "Could not resolve MySQL root password."

# --- Quick validation of dump file ---
if [[ "$DUMP" == *.gz ]]; then
  gzip -t -- "$DUMP" || die "gzip test failed for $DUMP"
fi

# --- Wait for DB up ---
echo "Waiting for MySQL to accept connections…"
until docker compose exec -T -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" "$MYSQL_SVC" \
  sh -lc 'mysqladmin ping -uroot -p"$MYSQL_ROOT_PASSWORD" --silent'; do
  sleep 2
done

# --- Safety backup (write to a subdir so it never becomes the “newest” dump) ---
STAMP="$(date +%F-%H%M%S)"
SAFE_DIR="$BACKUPS_DIR/safety"
mkdir -p "$SAFE_DIR"
SAFETY="$SAFE_DIR/auto-backup-${DB_NAME}-${STAMP}.sql.gz"
echo "Creating safety backup: $SAFETY"
docker compose exec -T -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" "$MYSQL_SVC" \
  sh -lc 'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --triggers "'"$DB_NAME"'" 2>/dev/null' \
  | gzip > "$SAFETY" || echo "WARN: safety backup may be empty (first load?)"

# --- Recreate target DB ---
echo "Recreating database $DB_NAME…"
docker compose exec -T -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" "$MYSQL_SVC" \
  sh -lc 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS \`'"$DB_NAME"'\`; CREATE DATABASE \`'"$DB_NAME"'\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"'

# --- Import sdmiramar dump into DB_NAME ---
echo "Importing…"
if [[ "$DUMP" == *.gz ]]; then
  gzip -dc -- "$DUMP" | docker compose exec -T -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" "$MYSQL_SVC" \
    sh -lc 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" '"$DB_NAME"
else
  cat -- "$DUMP" | docker compose exec -T -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" "$MYSQL_SVC" \
    sh -lc 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" '"$DB_NAME"
fi
echo "Import complete."

# --- Verify tables exist (expect > 0 and 'system' table) ---
echo "Verifying import…"
docker compose exec -T -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" "$MYSQL_SVC" \
  sh -lc 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"'"$DB_NAME"'\"; SHOW TABLES IN \`'"$DB_NAME"'\` LIKE \"system\";"'

# --- Optional: clear Drupal caches (if web service present) ---
if docker compose ps "$WEB_SVC" --status running >/dev/null 2>&1; then
  echo "Clearing Drupal caches…"
  docker compose exec -T "$WEB_SVC" bash -lc '
    set -e
    cd /var/www/miraweb2024 || exit 1
    if [ -x vendor/bin/drush ]; then
      vendor/bin/drush cr || true
      vendor/bin/drush status --fields=bootstrap,db-status,db-username,db-hostname,db-name || true
    fi
  ' || true
fi

echo "Done."
