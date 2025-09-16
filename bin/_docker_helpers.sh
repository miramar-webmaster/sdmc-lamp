#!/usr/bin/env bash
# Shared helpers used by bin/* and install.sh
# Safe on newer Docker/runc; avoids host-PWD "breakout" issues.
set -euo pipefail

# Resolve repo root relative to *this* file
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd -P)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"
ENV_FILE="$REPO_ROOT/.env"

# CWD-agnostic Compose wrapper (runs from / + explicit project dir/env)
dc() {
  ( cd / && docker compose \
      --project-directory "$REPO_ROOT" \
      --env-file "$ENV_FILE" \
      -f "$COMPOSE_FILE" \
      "$@" )
}

# Optional: get container ID (nice for debugging)
get_cid() {
  local svc="${1:?service name required}"
  local id
  id="$(dc ps -q "$svc" || true)"
  [[ -n "$id" ]] || { echo "ERROR: service '$svc' not running" >&2; return 1; }
  printf '%s\n' "$id"
}

# ---- Service runners --------------------------------------------------------

# PHP (Drupal) — verifies workdir exists *inside* container before using -w
run_in_php() {
  local svc="${PHP_SERVICE:-php81-apache}"
  local work="${DRUPAL_CONTAINER_PATH:-/var/www/miraweb2024}"
  local uidgid=()
  [[ "${RUN_AS_HOST_USER:-0}" == "1" ]] && uidgid=(-u "$(id -u):$(id -g)")

  dc up -d "$svc" >/dev/null 2>&1 || true

  if dc exec -T "$svc" sh -lc "test -d '$work'"; then
    exec dc exec -T "${uidgid[@]}" -w "$work" "$svc" "$@"
  else
    echo "WARN: $work not found in '$svc'; running without -w. Check your volume mount or DRUPAL_CONTAINER_PATH." >&2
    exec dc exec -T "${uidgid[@]}" "$svc" "$@"
  fi
}

# Node — same pattern; default to Drupal path unless NODE_CONTAINER_PATH set
run_in_node() {
  local svc="${NODE_SERVICE:-node}"
  local work="${NODE_CONTAINER_PATH:-${DRUPAL_CONTAINER_PATH:-/var/www/miraweb2024}}"
  local uidgid=()
  [[ "${RUN_AS_HOST_USER:-0}" == "1" ]] && uidgid=(-u "$(id -u):$(id -g)")

  dc up -d "$svc" >/dev/null 2>&1 || true

  if dc exec -T "$svc" sh -lc "test -d '$work'"; then
    exec dc exec -T "${uidgid[@]}" -w "$work" "$svc" "$@"
  else
    echo "WARN: $work not found in '$svc'; running without -w. Check your volume mount or NODE_CONTAINER_PATH." >&2
    exec dc exec -T "${uidgid[@]}" "$svc" "$@"
  fi
}

# MySQL — client doesn’t need a workdir; keep -T for piping
run_in_mysql() {
  local svc="${DB_SERVICE:-mysql}"
  dc up -d "$svc" >/dev/null 2>&1 || true
  exec dc exec -T "$svc" "$@"
}

