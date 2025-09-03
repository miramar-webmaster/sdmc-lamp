mkdir -p bin

# --- bin/db-refresh ---
cat > bin/db-refresh <<'BASH'
#!/usr/bin/env bash
# Refresh the MySQL/MariaDB database inside a Docker Compose service from a .sql or .sql.gz dump.
# Uses MYSQL_SERVICE from .env (defaults to "mysql"). Clears Drupal caches after import.
set -Eeuo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

# --- Load .env if present ---
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

# --- Config / defaults ---
DB_NAME="${MYSQL_DATABASE:-sdmc}"
BACKUPS_DIR="${DB_BACKUPS_DIR:-/srv/sdmc-miraweb/backups}"
MYSQL_SVC="${MYSQL_SERVICE:-mysql}"             # compose service name for MySQL/MariaDB
WEB_SVC="${WEB_SERVICE:-php81-apache}"          # Drupal/PHP service for drush cache clear
MYSQL_ROOT_PASSWORD_FILE_HOST="${MYSQL_ROOT_PASSWORD_FILE_HOST:-}"

# --- Resolve root password (host file → container env/secret) ---
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
if [[ -z "$MYSQL_ROOT_PASSWORD" && -n "$MYSQL_ROOT_PASSWORD_FILE_HOST" && -f "$MYSQL_ROOT_PASSWORD_FILE_HOST" ]]; then
  MYSQL_ROOT_PASSWORD="$(<"$MYSQL_ROOT_PASSWORD_FILE_HOST")"
fi
if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
  echo "Reading MySQL root password from container…" >&2
  docker compose up -d "$MYSQL_SVC" >/dev/null
  for _ in {1..12}; do
    MYSQL_ROOT_PASSWORD="$(
      docker compose exec -T "$MYSQL_SVC" sh -lc '
        set -e
        if [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then printf "%s" "$MYSQL_ROOT_PASSWORD"; exit 0; fi
        if [ -n "${MARIADB_ROOT_PASSWORD:-}" ]; then printf "%s" "$MARIADB_ROOT_PASSWORD"; exit 0; fi
        if [ -n "${MYSQL_ROOT_PASSWORD_FILE:-}" ] && [ -f "$MYSQL_ROOT_PASSWORD_FILE" ]; then cat "$MYSQL_ROOT_PASSWORD_FILE"; exit 0; fi
        if [ -n "${MARIADB_ROOT_PASSWORD_FILE:-}" ] && [ -f "$MARIADB_ROOT_PASSWORD_FILE" ]; then cat "$MARIADB_ROOT_PASSWORD_FILE"; exit 0; fi
        if [ -f /run/secrets/mysql_root_password ]; then cat /run/secrets/mysql_root_password; exit 0; fi
        exit 3
      ' 2>/dev/null || true
    )"
    [[ -n "$MYSQL_ROOT_PASSWORD" ]] && break
    sleep 2
  done
fi
[[ -n "$MYSQL_ROOT_PASSWORD" ]] || die "Could not resolve MySQL root password."

# --- Pick dump file ---
DUMP="${1-}"
if [[ -z "$DUMP" ]]; then
  DUMP="$(ls -1t "$BACKUPS_DIR"/*.sql "$BACKUPS_DIR"/*.sql.gz 2>/dev/null | head -n1 || true)"
  [[ -n "$DUMP" ]] || die "No .sql or .sql.gz found in $BACKUPS_DIR"
else
  [[ -f "$DUMP" ]] || die "Dump not found: $DUMP"
fi

echo "Using dump: $DUMP"
echo "Target DB:  $DB_NAME"
echo "Service:    $MYSQL_SVC"

# --- Ensure MySQL is ready ---
docker compose up -d "$MYSQL_SVC" >/dev/null
echo "Waiting for MySQL to accept connections…"
until docker compose exec -T -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" "$MYSQL_SVC" \
  sh -lc 'mysqladmin ping -uroot -p"$MYSQL_ROOT_PASSWORD" --silent'; do
  sleep 2
done
echo "DB ping OK"

# --- Safety backup (best-effort) ---
STAMP="$(date +%F-%H%M%S)"
SAFETY="$BACKUPS_DIR/auto-backup-${DB_NAME}-${STAMP}.sql.gz"
echo
