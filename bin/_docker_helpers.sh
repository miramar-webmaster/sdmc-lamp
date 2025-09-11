#!/usr/bin/env bash
# bin/_docker_helpers.sh — shared Docker/Compose helpers (robust across machines)
# - Finds absolute docker-compose.yml + repo root
# - Runs compose from the repo root (so .env is loaded)
# - Avoids `-w` (runc CWD guard) by `cd` inside the shell
# - Always runs as HOST_UID:HOST_GID (no root-owned files)

set -euo pipefail

# -------- resolve compose file + repo root (absolute) --------
if [[ -n "${COMPOSE_FILE_PATH:-}" && -f "${COMPOSE_FILE_PATH}" ]]; then
  REPO_ROOT="$(cd "$(dirname "$COMPOSE_FILE_PATH")" && pwd -P)"
else
  if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT="$(git rev-parse --show-toplevel)"
    COMPOSE_FILE_PATH="${REPO_ROOT}/docker-compose.yml"
  else
    # helpers expected in repo/bin/
    _HLP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    REPO_ROOT="$(cd "${_HLP_DIR}/.." && pwd -P)"
    COMPOSE_FILE_PATH="${REPO_ROOT}/docker-compose.yml"
  fi
fi
[[ -f "$COMPOSE_FILE_PATH" ]] || { echo "ERROR: compose file missing: $COMPOSE_FILE_PATH"; return 1 2>/dev/null || exit 1; }

# -------- safe compose wrapper (always from REPO_ROOT so .env is read) --------
dc() { ( cd "$REPO_ROOT" && docker compose -f "$COMPOSE_FILE_PATH" "$@" ); }

# -------- defaults (overridable via .env or caller) --------
: "${PHP_SERVICE:=php81-apache}"
: "${DRUPAL_CONTAINER_PATH:=/var/www/miraweb2024}"
: "${HOST_UID:=$(id -u)}"
: "${HOST_GID:=$(id -g)}"

# -------- internal: get running container id for a service --------
# old:
# _get_cid() { docker ps --filter "name=^/${svc}$" --format '{{.ID}}' | head -n1 || true; }

# new (robust):
_get_cid() {
  local svc="${1:?service required}"
  # ask compose for the container ID of this service in this project
  local id
  id="$(dc ps -q "$svc" | head -n1 || true)"
  if [[ -n "$id" ]]; then
    echo "$id"; return 0
  fi
  # fallback to docker ps (prefix/suffix tolerant)
  docker ps --filter "name=${svc}" --format '{{.ID}}' | head -n1 || true
}


# -------- optional: verify that a workdir exists inside the image --------
verify_workdir() {
  local svc="${1:?service}"; shift
  local workdir="${1:?workdir}"
  # use a one-off run (no -w), check directory exists
  if ! ( cd "$REPO_ROOT" && docker compose -f "$COMPOSE_FILE_PATH" run --rm -T \
           "$svc" sh -lc "test -d $(printf %q "$workdir")" ); then
    echo "ERROR: Workdir '$workdir' not found inside service '$svc'."
    echo "  • Ensure the volume is defined in docker-compose.yml"
    echo "  • Ensure DRUPAL_HOST_PATH in .env is an absolute host path that exists"
    exit 1
  fi
}

# -------- run affecting only mounted volumes: run → exec → docker exec --------
run_in_service() {
  local svc="${1:?service}"; shift
  local workdir="${1:?workdir}"; shift
  local -a cmd=( "$@" )

  # build inner command safely
  local inner; printf -v inner '%q ' "${cmd[@]}"

  # 1) compose run (one-off), cd inside (no -w), as HOST_UID:GID
  if ( cd "$REPO_ROOT" && docker compose -f "$COMPOSE_FILE_PATH" run --rm -T \
         -u "${HOST_UID}:${HOST_GID}" \
         "$svc" sh -lc "cd $(printf %q "$workdir") && exec $inner" ); then
    return 0
  fi

  # 2) compose exec into running service, cd inside (no -w), as HOST_UID:GID
  if ( cd "$REPO_ROOT" && docker compose -f "$COMPOSE_FILE_PATH" exec -T \
         -u "${HOST_UID}:${HOST_GID}" \
         "$svc" sh -lc "cd $(printf %q "$workdir") && exec $inner" ); then
    return 0
  fi

  # 3) plain docker exec fallback, cd inside (no -w), as HOST_UID:GID
  local cid; cid="$(_get_cid "$svc")"
  [[ -n "$cid" ]] || { echo "ERROR: service '${svc}' not running."; return 1; }

  docker exec -u "${HOST_UID}:${HOST_GID}" "$cid" \
    sh -lc "cd $(printf %q "$workdir") && exec $inner"
}

# Convenience wrappers
run_in_php() { run_in_service "${PHP_SERVICE}" "${DRUPAL_CONTAINER_PATH}" "$@"; }

# -------- exec into live container for persistent changes (apt-get, enabling modules) --------
exec_in_service_live() {
  local svc="${1:?service}"; shift
  local -a cmd=( "$@" )
  if dc exec -T "$svc" "${cmd[@]}"; then return 0; fi
  local cid; cid="$(_get_cid "$svc")"
  [[ -n "$cid" ]] || { echo "ERROR: service '${svc}' not running."; return 1; }
  docker exec "$cid" "${cmd[@]}"
}

exec_in_php_live() { exec_in_service_live "${PHP_SERVICE}" "$@"; }

