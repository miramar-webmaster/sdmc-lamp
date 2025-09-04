#!/usr/bin/env bash
# bootstrap.sh — one-shot setup for SDMC LAMP/Drupal stack on a fresh Ubuntu workstation.
# Adds SDMC_ENV prompt and seamless re-exec under docker group.

set -Eeuo pipefail

### ----------------------- utils -----------------------
log() { printf "\n\033[1;34m[%s]\033[0m %s\n" "$(date +%H:%M:%S)" "$*"; }
warn() { printf "\033[1;33mWARN:\033[0m %s\n" "$*" >&2; }
die() { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

as_root() {
  if [[ $EUID -ne 0 ]]; then sudo bash -lc "$*"; else bash -lc "$*"; fi
}

here_repo_root_check() {
  [[ -f docker-compose.yml ]] || die "Run this script from the infra repo root (docker-compose.yml not found)."
  [[ -x bin/composer ]] || warn "bin/composer not executable (will try anyway)."
  [[ -x bin/drush    ]] || warn "bin/drush not executable (will try anyway)."
  [[ -x bin/node     ]] || warn "bin/node not executable (will try anyway)."
}

# Seamless re-exec under 'docker' group so no logout is required
ensure_docker_group_active() {
  if id -nG "$USER" | grep -qw docker; then
    return 0
  fi
  if ! getent group docker >/dev/null 2>&1; then
    as_root "groupadd docker" || true
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    sudo usermod -aG docker "$USER" || true
  else
    usermod -aG docker "$USER" || true
  fi
  log "Added $USER to 'docker' group."
  if command -v sg >/dev/null 2>&1 && [[ -z "${REEXECED_WITH_DOCKER:-}" ]]; then
    log "Re-execing this script under 'docker' group (no logout needed)…"
    exec sg docker -c "REEXECED_WITH_DOCKER=1 \"$0\" $*"
  else
    warn "Open a new shell or run:  newgrp docker  then re-run this script."
  fi
}

### -------------------- config/consts -------------------
DRUPAL_REPO_SSH="git@github.com:miramar-webmaster/miraweb2024.git"
DRUPAL_HOST_PATH="/var/www/miraweb2024"
SECRETS_DIR="/srv/sdmc-miraweb/secrets"
BACKUPS_DIR="/srv/sdmc-miraweb/backups"
MYSQL_INIT_DIR="/srv/mysql-init"
SRV_ROOT="/srv/sdmc-miraweb"

MYSQL_ROOT_SECRET="$SECRETS_DIR/mysql_root_password"
MYSQL_DRUPAL_SECRET="$SECRETS_DIR/mysql_drupal_password"

CERTS_DIR="./certs"
DEV_CERT="$CERTS_DIR/dev.crt"
DEV_KEY="$CERTS_DIR/dev.key"

APACHE_HOSTNAME_DEFAULT="dev.loc"
SDMC_ENV_VALUE="dev"   # will be prompted

### --------------------- steps --------------------------
install_prereqs() {
  log "Installing OS prerequisites (Docker, OpenSSH, CA bundle, etc.)…"
  as_root 'apt-get update -y'
  as_root 'apt-get install -y gnome-software openssh-server ca-certificates curl gnupg'
  as_root 'install -m 0755 -d /etc/apt/keyrings'
  if ! [[ -f /etc/apt/keyrings/docker.gpg ]]; then
    as_root 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg'
    as_root 'chmod a+r /etc/apt/keyrings/docker.gpg'
  fi
  if ! [[ -f /etc/apt/sources.list.d/docker.list ]]; then
    as_root 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list'
  fi
  as_root 'apt-get update -y'
  as_root 'apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin'
  as_root 'systemctl enable --now docker'
}

prompt_passwords() {
  log "Collecting MySQL passwords (blank = auto-generate)…"
  local root_pw drupal_pw
  read -rsp "MySQL ROOT password: " root_pw || true; echo
  read -rsp "MySQL DRUPAL user password: " drupal_pw || true; echo
  [[ -n "${root_pw:-}" ]]   || root_pw="$(openssl rand -base64 18)"
  [[ -n "${drupal_pw:-}" ]] || drupal_pw="$(openssl rand -base64 18)"
  mkdir -p "$SECRETS_DIR"
  umask 077
  printf "%s" "$root_pw"   > "$MYSQL_ROOT_SECRET"
  printf "%s" "$drupal_pw" > "$MYSQL_DRUPAL_SECRET"
  chmod 600 "$MYSQL_ROOT_SECRET" "$MYSQL_DRUPAL_SECRET"
  log "Wrote secrets to $SECRETS_DIR"
}

prompt_sdmc_env() {
  log "Configuring SDMC_ENV for Apache/Drupal…"
  local existing=""; [[ -f .env ]] && existing="$(grep -E '^SDMC_ENV=' .env | sed -E 's/^SDMC_ENV=//; s/"//g' || true)"
  local default="${existing:-dev}"
  read -rp "SDMC_ENV (dev/stage/prod) [${default}]: " ans
  SDMC_ENV_VALUE="${ans:-$default}"
  [[ -n "$SDMC_ENV_VALUE" ]] || SDMC_ENV_VALUE="dev"
  log "Using SDMC_ENV=$SDMC_ENV_VALUE"
}

create_srv_dirs() {
  log "Ensuring service directories exist…"
  as_root "mkdir -p '$MYSQL_INIT_DIR' '$BACKUPS_DIR' '$SECRETS_DIR' '$SRV_ROOT'"
  as_root "chown -R $USER:$USER '$SRV_ROOT' '$MYSQL_INIT_DIR'"
}

generate_certs() {
  log "Generating dev TLS certs (if missing)…"
  mkdir -p "$CERTS_DIR"
  local cn="$APACHE_HOSTNAME_DEFAULT"
  if [[ -f .env ]]; then
    cn="$(grep -E '^APACHE_SERVER_NAME=' .env | sed -E 's/APACHE_SERVER_NAME=//; s/"//g' || true)"
    [[ -n "$cn" ]] || cn="$APACHE_HOSTNAME_DEFAULT"
  fi
  if [[ ! -f "$DEV_CERT" || ! -f "$DEV_KEY" ]]; then
    log "Creating self-signed cert for CN=$cn → $DEV_CERT"
    openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
      -keyout "$DEV_KEY" -out "$DEV_CERT" \
      -subj "/CN=$cn" >/dev/null 2>&1 || die "OpenSSL failed"
    chmod 600 "$DEV_KEY"; chmod 644 "$DEV_CERT"
  else
    log "Certs already exist: $DEV_CERT / $DEV_KEY"
  fi
  if ! grep -qE "^[0-9.]+\s+$cn(\s|$)" /etc/hosts; then
    log "Adding $cn to /etc/hosts"
    as_root "printf '%s\t%s\n' '127.0.0.1' '$cn' >> /etc/hosts"
  fi
}

clone_drupal_repo() {
  log "Ensuring Drupal repo at $DRUPAL_HOST_PATH…"
  if [[ -d "$DRUPAL_HOST_PATH/.git" ]]; then
    log "Drupal repo already present."
  else
    as_root "mkdir -p /var/www && chown $USER:$USER /var/www"
    git clone "$DRUPAL_REPO_SSH" "$DRUPAL_HOST_PATH" || die "Git clone failed"
  fi
}

placeholder_fetch_backup() {
  log "PLACEHOLDER: Download/untar latest backup (DB + sites/default/files)…"
  log "→ Put DB dump into: $BACKUPS_DIR and $MYSQL_INIT_DIR"
  log "→ Extract files dir into: $DRUPAL_HOST_PATH/docroot/sites/default"
}

# update or append KEY=VALUE in .env (preserve other lines)
upsert_env() {
  local key="$1" val="$2"
  touch .env
  if grep -qE "^${key}=" .env; then
    sed -i -E "s|^${key}=.*$|${key}=${val}|" .env
  else
    echo "${key}=${val}" >> .env
  fi
}

ensure_env_file() {
  log "Preparing .env…"
  if [[ ! -f .env && -f example.env ]]; then
    cp example.env .env
    log "Created .env from example.env"
  fi
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
  log ".env updated. SDMC_ENV=$(grep -E '^SDMC_ENV=' .env | cut -d= -f2-)"
}

docker_up() {
  log "Starting containers…"
  docker compose up -d mysql memcached solr php81-apache
}

composer_install() {
  log "Composer install in Drupal repo…"
  ./bin/composer install --no-interaction
}

drush_cim() {
  log "Importing Drupal config (drush cim)…"
  ./bin/drush cim -y || warn "drush cim non-zero (ok on first boot or pending modules)"
}

node_build() {
  log "Building theme assets (npm install + build)…"
  ./bin/node all
}

drush_cache_rebuild() {
  log "Clearing Drupal caches…"
  ./bin/drush cr || true
}

### --------------------- mainline -----------------------
main() {
  here_repo_root_check
  install_prereqs
  ensure_docker_group_active "$@"
  prompt_passwords
  prompt_sdmc_env
  create_srv_dirs
  generate_certs
  ensure_env_file
  clone_drupal_repo
  placeholder_fetch_backup
  docker_up
  composer_install
  drush_cim
  node_build
  drush_cache_rebuild
  log "Done. Visit: https://dev.loc:${APACHE_SSL_PORT:-8444} or http://dev.loc:${APACHE_PORT:-8081}"
}

main "$@"
