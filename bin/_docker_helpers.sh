#!/usr/bin/env bash
# bin/_docker_helpers.sh — shared Compose helpers used by bin/* and install.sh
set -euo pipefail

# Resolve repo root, compose file, and .env (works no matter where it's sourced from)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd -P)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"
ENV_FILE="$REPO_ROOT/.env"

# Always run compose with the repo’s .env and compose file
dc() {
  docker compose \
    --project-directory "$REPO_ROOT" \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    "$@"
}

# Exec inside the PHP service at the Drupal path, as the host user
run_in_php() {
  local svc="${PHP_SERVICE:-php81-apache}"
  local work="${DRUPAL_CONTAINER_PATH:-/var/www/miraweb2024}"
  local uid="${HOST_UID:-$(id -u)}"
  local gid="${HOST_GID:-$(id -g)}"
  dc up -d "$svc" >/dev/null 2>&1 || true
  dc exec -T -u "${uid}:${gid}" -w "$work" "$svc" "$@"
}

# Get container ID robustly (works even if compose ps is empty)
get_cid() {
  local svc="${1:?service name required}"
  local id
  id="$(dc ps -q "$svc" || true)"
  if [[ -z "$id" ]]; then
    id="$(docker ps --format '{{.ID}}\t{{.Names}}' | awk -v s="$svc" '$2 ~ ("_" s "_") || $2 ~ (s"$") {print $1; exit}')"
  fi
  [[ -n "$id" ]] || { echo "ERROR: service '$svc' not running"; return 1; }
  printf '%s\n' "$id"
}

