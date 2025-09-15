#!/usr/bin/env bash
# install.sh — one-shot setup for SDMC LAMP/Drupal stack
# Delegates app tasks to ./bin/composer, ./bin/drush, ./bin/node, and scripts/db-refresh(.sh) if present.

set -Eeuo pipefail

# ---------- flags ----------
FORCE_CERT_REGEN="${REGEN_CERTS:-0}"
if [[ "${1-}" == "--regen-certs" ]]; then FORCE_CERT_REGEN=1; shift || true; fi

# ---------- utils ----------
log()  { printf "\n\033[1;34m[%s]\033[0m %s\n" "$(date +%H:%M:%S)" "$*"; }
warn() { printf "\033[1;33mWARN:\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

as_root() { if [[ $EUID -ne 0 ]]; then sudo bash -lc "$*"; else bash -lc "$*"; fi; }

ensure_sudo() {
  if [[ $EUID -ne 0 ]]; then
    need_cmd sudo
    sudo -v || die "Sudo authentication failed."
    ( while true; do sleep 60; sudo -n true || exit; done ) & SUDO_KEEPALIVE=$!
    trap '[[ -n "${SUDO_KEEPALIVE:-}" ]] && kill "$SUDO_KEEPALIVE" 2>/dev/null || true' EXIT
  fi
}

here_repo_root_check() {
  [[ -f docker-compose.yml ]] || die "Run from repo root (docker-compose.yml not found)."
  [[ -x bin/composer ]] || warn "bin/composer not executable."
  [[ -x bin/drush    ]] || warn "bin/drush not executable."
  [[ -x bin/node     ]] || warn "bin/node not executable."
}

# Seamless re-exec under 'docker' group so no logout is required
ensure_docker_group_active() {
  if id -nG "$USER" | grep -qw docker; then return 0; fi
  if ! getent group docker >/dev/null 2>&1; then as_root "groupadd docker" || true; fi
  if [[ "$(id -u)" -ne 0 ]]; then sudo usermod -aG docker "$USER" || true; else usermod -aG docker "$USER" || true; fi
  log "Added $USER to 'docker' group."
  if command -v sg >/dev/null 2>&1 && [[ -z "${REEXECED_WITH_DOCKER:-}" ]]; then
    log "Re-execing under 'docker' group (no logout needed)…"
    exec sg docker -c "REEXECED_WITH_DOCKER=1 \"$0\" \"$@\""
  else
    warn "Open a new shell or run:  newgrp docker  then re-run this script."
  fi
}

# ---------- absolute paths for compose & bin ----------
REPO_ROOT="$(pwd -P)"
COMPOSE_FILE_PATH="$REPO_ROOT/docker-compose.yml"
BIN_COMPOSER="$REPO_ROOT/bin/composer"
BIN_DRUSH="$REPO_ROOT/bin/drush"
BIN_NODE="$REPO_ROOT/bin/node"

# Safe compose wrapper (avoids CWD mount-namespace guard)
dc() { ( cd / && docker compose -f "$COMPOSE_FILE_PATH" "$@" ); }

# ---------- config ----------
DRUPAL_REPO_SSH="git@github.com:miramar-webmaster/miraweb2024.git"
DRUPAL_HOST_PATH="/var/www/miraweb2024"

SRV_ROOT="/srv/sdmc-miraweb"
SECRETS_DIR="$SRV_ROOT/secrets"
BACKUPS_DIR="$SRV_ROOT/backups"
MYSQL_INIT_DIR="/srv/mysql-init"

MYSQL_ROOT_SECRET="$SECRETS_DIR/mysql_root_password"
MYSQL_DRUPAL_SECRET="$SECRETS_DIR/mysql_drupal_password"

CERTS_DIR="./certs"
DEV_CERT="$CERTS_DIR/dev.crt"
DEV_KEY="$CERTS_DIR/dev.key"

APACHE_HOSTNAME_DEFAULT="dev.loc"
SDMC_ENV_VALUE="dev"

# ---------- steps ----------
install_prereqs() {
  log "Installing OS prerequisites…"
  as_root 'apt-get update -y'
  as_root 'apt-get install -y gnome-software openssh-server ca-certificates curl gnupg'
  as_root 'install -m 0755 -d /etc/apt/keyrings'
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    as_root 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg'
    as_root 'chmod a+r /etc/apt/keyrings/docker.gpg'
  fi
  if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    as_root 'bash -lc ". /etc/os-release; echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable\" > /etc/apt/sources.list.d/docker.list"'
  fi
  as_root 'apt-get update -y'
  as_root 'apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin'
  as_root 'systemctl enable --now docker'
}

create_srv_dirs() {
  log "Ensuring /srv directories…"
  as_root "install -d -m 0755 -o $USER -g $USER '$SRV_ROOT'"
  as_root "install -d -m 0755 -o $USER -g $USER '$BACKUPS_DIR'"
  as_root "install -d -m 0700 -o $USER -g $USER '$SECRETS_DIR'"
  as_root "install -d -m 0755 -o $USER -g $USER '$MYSQL_INIT_DIR'"
}

prompt_passwords() {
  log "Collecting MySQL passwords (blank = auto-generate)…"
  local root_pw="" drupal_pw=""
  read -rsp "MySQL ROOT password: " root_pw || true; echo
  read -rsp "MySQL DRUPAL user password: " drupal_pw || true; echo
  [[ -n "${root_pw:-}"   ]] || root_pw="$(openssl rand -base64 18)"
  [[ -n "${drupal_pw:-}" ]] || drupal_pw="$(openssl rand -base64 18)"
  umask 077
  printf "%s" "$root_pw"   > "$MYSQL_ROOT_SECRET"
  printf "%s" "$drupal_pw" > "$MYSQL_DRUPAL_SECRET"
  chmod 600 "$MYSQL_ROOT_SECRET" "$MYSQL_DRUPAL_SECRET"
  log "Wrote secrets to $SECRETS_DIR"
}

prompt_sdmc_env() {
  log "Configuring SDMC_ENV…"
  local existing=""; [[ -f .env ]] && existing="$(grep -E '^SDMC_ENV=' .env | sed -E 's/^SDMC_ENV=//; s/"//g' || true)"
  local default="${existing:-dev}"
  read -rp "SDMC_ENV (dev/stage/prod) [${default}]: " ans
  SDMC_ENV_VALUE="${ans:-$default}"
  [[ -n "$SDMC_ENV_VALUE" ]] || SDMC_ENV_VALUE="dev"
  log "Using SDMC_ENV=$SDMC_ENV_VALUE"
}

# update or append KEY=VALUE in .env (preserve other lines; escape & and \)
upsert_env() {
  local key="$1" val="$2"
  touch .env
  if grep -qE "^${key}=" .env; then
    local esc="${val//\\/\\\\}"; esc="${esc//&/\\&}"
    sed -i -E "s|^(${key})=.*$|\1=${esc}|" .env
  else
    printf "%s=%s\n" "$key" "$val" >> .env
  fi
}

ensure_env_file() {
  log "Preparing .env…"
  [[ ! -f .env && -f example.env ]] && { cp example.env .env; log "Created .env from example.env"; }

  upsert_env "DRUPAL_HOST_PATH" "$DRUPAL_HOST_PATH"
  upsert_env "DRUPAL_CONTAINER_PATH" "$DRUPAL_HOST_PATH"
  upsert_env "APACHE_DOCROOT" "$DRUPAL_HOST_PATH/docroot"
  upsert_env "APACHE_SERVER_NAME" "$APACHE_HOSTNAME_DEFAULT"
  upsert_env "APACHE_SERVER_ALIAS" "$APACHE_HOSTNAME_DEFAULT"
  upsert_env "SSL_ENABLE" "1"
  upsert_env "SSL_CERT_FILE" "/certs/dev.crt"
  upsert_env "SSL_CERT_KEY_FILE" "/certs/dev.key"
  upsert_env "MYSQL_ROOT_PASSWORD_FILE_HOST" "$MYSQL_ROOT_SECRET"
  upsert_env "MYSQL_DRUPAL_PASSWORD_FILE_HOST" "$MYSQL_DRUPAL_SECRET"
  upsert_env "DB_BACKUPS_DIR" "$BACKUPS_DIR"
  upsert_env "DB_INIT_DIR" "$MYSQL_INIT_DIR"
  upsert_env "MYSQL_DATABASE" "sdmc"
  upsert_env "MYSQL_USER" "drupal"
  upsert_env "WEB_SERVICE" "php81-apache"
  upsert_env "PHP_SERVICE" "php81-apache"
  upsert_env "DRUSH_SERVICE" "php81-apache"
  upsert_env "MYSQL_SERVICE" "mysql"
  upsert_env "SDMC_ENV" "$SDMC_ENV_VALUE"

  if [[ ! -d "$DRUPAL_HOST_PATH" ]]; then
    warn "Host path $DRUPAL_HOST_PATH does not exist yet; will create and clone repo."
  fi
}

generate_certs() {
  log "Ensuring dev TLS certs…"
  as_root "install -d -m 0755 -o $USER -g $USER '$CERTS_DIR'"

  local cn="$APACHE_HOSTNAME_DEFAULT" alias="$APACHE_HOSTNAME_DEFAULT"
  if [[ -f .env ]]; then
    cn="$(grep -E '^APACHE_SERVER_NAME=' .env | sed -E 's/^APACHE_SERVER_NAME=//; s/\"//g' || true)"
    alias="$(grep -E '^APACHE_SERVER_ALIAS=' .env | sed -E 's/^APACHE_SERVER_ALIAS=//; s/\"//g' || true)"
    [[ -n "$cn" ]]    || cn="$APACHE_HOSTNAME_DEFAULT"
    [[ -n "$alias" ]] || alias="$APACHE_HOSTNAME_DEFAULT"
  fi

  if [[ "$FORCE_CERT_REGEN" != "1" && -f "$DEV_CERT" && -f "$DEV_KEY" ]]; then
    log "Certs already present (use --regen-certs to replace)."
  else
    if [[ -f "$DEV_CERT" || -f "$DEV_KEY" ]]; then
      local ts bdir; ts="$(date +%F-%H%M%S)"; bdir="$CERTS_DIR/.backup-$ts"
      as_root "install -d -m 0700 -o $USER -g $USER '$bdir'"
      [[ -f "$DEV_CERT" ]] && (mv -f "$DEV_CERT" "$bdir/" 2>/dev/null || as_root "mv -f '$DEV_CERT' '$bdir/'")
      [[ -f "$DEV_KEY"  ]] && (mv -f "$DEV_KEY"  "$bdir/" 2>/dev/null || as_root "mv -f '$DEV_KEY'  '$bdir/'")
      log "Backed up old certs to $bdir"
    fi

    local cfg; cfg="$(mktemp)"
    cat >"$cfg" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn
[dn]
CN = $cn
[req_ext]
subjectAltName = @alt_names
[alt_names]
DNS.1 = $cn
DNS.2 = $alias
DNS.3 = localhost
IP.1  = 127.0.0.1
IP.2  = ::1
EOF
    openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
      -keyout "$DEV_KEY" -out "$DEV_CERT" -config "$cfg" -extensions req_ext >/dev/null 2>&1 || die "OpenSSL failed"
    rm -f "$cfg"
    chmod 600 "$DEV_KEY"; chmod 644 "$DEV_CERT"
  fi

  local host="$APACHE_HOSTNAME_DEFAULT"
  [[ -f .env ]] && host="$(grep -E '^APACHE_SERVER_NAME=' .env | sed -E 's/^APACHE_SERVER_NAME=//; s/\"//g' || true)"
  [[ -n "$host" ]] || host="$APACHE_HOSTNAME_DEFAULT"
  if ! grep -qE "^[0-9.]+\s+$host(\s|$)" /etc/hosts; then
    log "Adding $host to /etc/hosts"
    as_root "printf '%s\t%s\n' '127.0.0.1' '$host' >> /etc/hosts"
  fi
}

clone_drupal_repo() {
  log "Ensuring Drupal repo at $DRUPAL_HOST_PATH…"
  if [[ -d "$DRUPAL_HOST_PATH/.git" ]]; then
    log "Drupal repo already present."
  else
    as_root "install -d -m 0755 -o $USER -g $USER /var/www"
    git clone "$DRUPAL_REPO_SSH" "$DRUPAL_HOST_PATH" || die "Git clone failed"
  fi
}

# ---------- settings sync (update DB password and stage into Drupal) ----------
# ---------- settings sync (update DB password and stage into Drupal) ----------
update_and_stage_settings() {
  local SRC="$REPO_ROOT/settings"
  local DEST_ROOT="${DRUPAL_HOST_PATH:-/var/www/miraweb2024}/docroot/sites/default"
  local DEST="$DEST_ROOT/settings"
  local SECRET="${MYSQL_DRUPAL_SECRET:-/srv/sdmc-miraweb/secrets/mysql_drupal_password}"

  [[ -d "$SRC" ]] || { warn "No settings/ folder at $SRC; skipping settings sync."; return 0; }
  [[ -f "$SECRET" ]] || die "Drupal DB password secret not found at $SECRET"
  local drupal_pw; drupal_pw="$(<"$SECRET")"
  [[ -n "$drupal_pw" ]] || die "Drupal DB password empty in $SECRET"

  # Work in a temp copy so we never edit repo files in-place
  local TMP; TMP="$(mktemp -d)"
  cp -a "$SRC"/. "$TMP"/

  # Escape password for sed
  local esc_pw="$drupal_pw"
  esc_pw="${esc_pw//\\/\\\\}"   # backslashes
  esc_pw="${esc_pw//&/\\&}"     # &
  esc_pw="${esc_pw//|/\\|}"     # delimiter

  # Update any *.php file in the temp settings dir
  shopt -s nullglob
  local f
  for f in "$TMP"/*.php; do
    sed -E -i "s|('password'[[:space:]]*=>[[:space:]]*)'[^']*'|\1'${esc_pw}'|" "$f"
  done
  shopt -u nullglob

  # Create dest and copy
  local GROUP="www-data"; getent group "$GROUP" >/dev/null 2>&1 || GROUP="$(id -gn)"
  as_root "install -d -m 2775 -o $USER -g $GROUP '$DEST_ROOT'"
  as_root "install -d -m 2775 -o $USER -g $GROUP '$DEST'"

  # Copy the contents of TMP into $DEST
  as_root "cp -a \"$TMP\"/. \"$DEST\"/"

  # Ownership/perms
  as_root "chown -R $USER:$GROUP '$DEST'"
  as_root "find '$DEST' -type d -exec chmod 2775 {} +"
  as_root "find '$DEST' -type f -exec chmod 664  {} +"

  rm -rf "$TMP"
  log "Settings synced → $DEST"
}



# ---------- permissions normalization (host) ----------
ensure_www_data_group() {
  # Ubuntu/Debian already have www-data (gid 33). If not, fall back to user's group.
  if getent group www-data >/dev/null 2>&1; then
    TARGET_GROUP="www-data"
  else
    warn "Group 'www-data' not found; using your primary group instead."
    TARGET_GROUP="$(id -gn)"
  fi
  export TARGET_GROUP
}

# Run a heredoc as root while passing env safely
root_sh_env() {
  # usage: root_sh_env VAR1=val VAR2=val <<'BASH'
  # (the heredoc content is read from stdin)
  if [[ $EUID -ne 0 ]]; then
    sudo -E env "$@" bash -se
  else
    env "$@" bash -se
  fi
}

# Generic normalizer: owner=$USER, group=www-data (fallback: user's group)
# Usage:
#   set_perms                       # whole repo (DRUPAL_HOST_PATH)
#   set_perms "/var/www/.../sdmc"   # theme-only
 set_perms() {
  local TARGET="${1:-${DRUPAL_HOST_PATH:-/var/www/miraweb2024}}"
  local OWNER="${SUDO_USER:-$USER}"
  local GROUP="www-data"
  getent group "$GROUP" >/dev/null 2>&1 || GROUP="$(id -gn)"

  log "Normalizing ownership/permissions under $TARGET (owner: $OWNER, group: $GROUP)…"

  root_sh_env OWNER="$OWNER" GROUP="$GROUP" TARGET="$TARGET" <<'BASH'
set -e
# 1) Ownership
chown -R "$OWNER:$GROUP" "$TARGET"

# 2) Directories: 2775 (setgid so new files inherit group)
find "$TARGET" -type d -print0 | xargs -0 chmod 2775

# 3) Files: 664
find "$TARGET" -type f -print0 | xargs -0 chmod 664
BASH

  # If we touched the project root, also ensure sites/default/files is writable
  if [[ "$TARGET" == "${DRUPAL_HOST_PATH:-/var/www/miraweb2024}"* ]]; then
    local FILES_DIR="$DRUPAL_HOST_PATH/docroot/sites/default/files"
    if [[ -d "$FILES_DIR" ]]; then
      log "Ensuring writable files dir: $FILES_DIR"
      root_sh_env OWNER="${SUDO_USER:-$USER}" GROUP="$GROUP" FILES_DIR="$FILES_DIR" <<'BASH'
set -e
chown -R "$OWNER:$GROUP" "$FILES_DIR"
find "$FILES_DIR" -type d -print0 | xargs -0 chmod 2775
find "$FILES_DIR" -type f -print0 | xargs -0 chmod 664
BASH
    fi
  fi
}

# Optional convenience wrappers (can delete old ones):
# BROKEN LINE COMMENTED OUT: set_perms()        { set_perms "${DRUPAL_HOST_PATH:-/var/www/miraweb2024}"; }
# BROKEN LINE COMMENTED OUT: set_perms "${DRUPAL_HOST_PATH:-/var/www/miraweb2024}/docroot/themes/custom/sdmc"()  { set_perms "${DRUPAL_HOST_PATH:-/var/www/miraweb2024}/docroot/themes/custom/sdmc"; }


maybe_seed_node_as_root() {
  # One-time helper: if node-sass/native deps exist and npm as user fails,
  # allow a single root build inside the Node container, then chown back.
  local ROOT="${DRUPAL_HOST_PATH:-/var/www/miraweb2024}"
  local THEME="$ROOT/docroot/themes/custom/sdmc"
  [[ -f "$THEME/package.json" ]] || return 0

  if grep -q '"node-sass"' "$THEME/package.json" 2>/dev/null; then
    log "Detected node-sass — performing one-time root build (Node 16)…"
    USE_ONE_OFF=1 NODE_IMAGE=node:16-alpine ./bin/node --root install || true

    ensure_www_data_group
    sudo chown -R "$USER":"$TARGET_GROUP" "$THEME/node_modules" "$THEME/package-lock.json" 2>/dev/null || true
    sudo find "$THEME/node_modules" -type d -exec chmod 2775 {} + 2>/dev/null || true
    sudo find "$THEME/node_modules" -type f -exec chmod 664 {} + 2>/dev/null || true
  fi
}

docker_up() {
  log "Starting containers…"
  dc up -d mysql memcached solr php81-apache
}

wait_for_mysql() {
  log "Waiting for MySQL to accept connections…"

  local svc pw pw_file
  svc="$(grep -E '^MYSQL_SERVICE=' .env | cut -d= -f2- | tr -d '"')"
  [[ -n "$svc" ]] || svc="mysql"

  pw_file="$(grep -E '^MYSQL_ROOT_PASSWORD_FILE_HOST=' .env | cut -d= -f2- | tr -d '"')"
  if [[ -n "$pw_file" && -f "$pw_file" ]]; then pw="$(<"$pw_file")"; fi
  [[ -n "${pw:-}" ]] || pw="$(grep -E '^MYSQL_ROOT_PASSWORD=' .env | cut -d= -f2- | tr -d '"')"

  if [[ -z "${pw:-}" ]]; then
    pw="$(dc exec -T "$svc" sh -lc '
      set -e
      if [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then printf "%s" "$MYSQL_ROOT_PASSWORD"; exit 0; fi
      if [ -n "${MARIADB_ROOT_PASSWORD:-}" ]; then printf "%s" "$MARIADB_ROOT_PASSWORD"; exit 0; fi
      if [ -n "${MYSQL_ROOT_PASSWORD_FILE:-}" ] && [ -f "$MYSQL_ROOT_PASSWORD_FILE" ]; then cat "$MYSQL_ROOT_PASSWORD_FILE"; exit 0; fi
      if [ -n "${MARIADB_ROOT_PASSWORD_FILE:-}" ] && [ -f "$MARIADB_ROOT_PASSWORD_FILE" ]; then cat "$MARIADB_ROOT_PASSWORD_FILE"; exit 0; fi
      if [ -f /run/secrets/mysql_root_password ]; then cat /run/secrets/mysql_root_password; exit 0; fi
      exit 3
    ' 2>/dev/null || true)"
  fi
  [[ -n "$pw" ]] || die "Could not resolve MySQL root password (check .env/secrets and the DB container)."

  local tries=60 i
  for i in $(seq 1 "$tries"); do
    if dc exec -T "$svc" sh -lc 'mysqladmin ping -uroot -p"'"$pw"'" --silent' >/dev/null 2>&1; then
      log "MySQL is ready (exec)."; return 0
    fi
    if dc run --rm -T "$svc" sh -lc 'mysqladmin ping -h"'"$svc"'" --protocol=TCP -uroot -p"'"$pw"'" --silent' >/dev/null 2>&1; then
      log "MySQL is ready (run)."; return 0
    fi
    sleep 2
  done

  warn "MySQL did not become ready in time. Recent logs:"
  dc logs --no-color --since=2m "$svc" | tail -n 80 || true
  die "MySQL not ready."
}

# TEMP ONLY: copy ~/sdmiramar.sql into /srv folders for testing
stage_temp_backup() {
  local src="$HOME/sdmiramar.sql"
  if [[ -f "$src" ]]; then
    log "Staging temp DB dump from $src"
    as_root "install -d -m 0755 -o $USER -g $USER '$SRV_ROOT' '$BACKUPS_DIR'"
    as_root "cp -f '$src' '$SRV_ROOT/sdmiramar.sql'"
    as_root "cp -f '$src' '$BACKUPS_DIR/sdmiramar.sql'"
    as_root "chown $USER:$USER '$SRV_ROOT/sdmiramar.sql' '$BACKUPS_DIR/sdmiramar.sql'"
    as_root "chmod 640 '$SRV_ROOT/sdmiramar.sql' '$BACKUPS_DIR/sdmiramar.sql'"
    log "Temp dump copied. (Remove stage_temp_backup() once real fetch is in place.)"
  else
    warn "Temp dump $src not found; skipping."
  fi
}

# -------- resolve & run db-refresh (bin or scripts) --------
resolve_db_refresh() {
  local candidates=(
    "$REPO_ROOT/bin/db-refresh"
    "$REPO_ROOT/bin/db-refresh.sh"
    "$REPO_ROOT/scripts/db-refresh"
    "$REPO_ROOT/scripts/db-refresh.sh"
  )
  for p in "${candidates[@]}"; do
    if [[ -f "$p" ]]; then chmod +x "$p" 2>/dev/null || true; echo "$p"; return 0; fi
  done
  echo ""; return 1
}

db_refresh_if_present() {
  local script; script="$(resolve_db_refresh || true)"
  if [[ -n "$script" ]]; then
    log "Refreshing DB via: ${script#$REPO_ROOT/}"
    "$script" || warn "db-refresh returned non-zero"
  else
    log "No db-refresh script found (skipping)."
  fi
}

# ---------- app tasks via ./bin/* ----------
composer_install()    { log "Composer install…";    "$BIN_COMPOSER" install --no-interaction --ansi; }
drush_cim()           { log "drush cim…";           "$BIN_DRUSH" cim -y || warn "drush cim non-zero"; }
node_build()          { log "Theme build…";         "$BIN_NODE" all; }
drush_cache_rebuild() { log "drush cr…";            "$BIN_DRUSH" cr || true; }

# ---------- main ----------
main() {
  here_repo_root_check
  ensure_sudo
  ensure_docker_group_active "$@"
  install_prereqs
  create_srv_dirs
  prompt_passwords
  prompt_sdmc_env
  ensure_env_file
  generate_certs
  clone_drupal_repo
  set_perms
  update_and_stage_settings
  docker_up
  wait_for_mysql

  # TEMP for testing backups until you wire the real fetch:
  stage_temp_backup
  db_refresh_if_present

  composer_install
  drush_cim
  node_build
  maybe_seed_node_as_root
  set_perms "$DRUPAL_HOST_PATH/docroot/themes/custom/sdmc"
  drush_cache_rebuild

  log "Done. Visit: https://dev.loc:${APACHE_SSL_PORT:-8444} or http://dev.loc:${APACHE_PORT:-8081}"
}

main "$@"
