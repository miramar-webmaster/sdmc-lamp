#!/usr/bin/env sh
set -eu

# --- Find repo root (parent of this script) and cd there ---
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# --- Load .env (or $ENV_FILE) and export vars ---
ENV_FILE="${ENV_FILE:-.env}"
if [ -f "$ENV_FILE" ]; then
  # Export all assignments in .env (supports quoted values; ignores comments/blank lines)
  # Tip: ensure the file has Unix line endings (run `dos2unix .env` if needed).
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
else
  echo "WARN: $ENV_FILE not found in $REPO_ROOT; using already-exported environment vars." >&2
fi

# --- Defaults (match .env.example) ---
: "${MYSQL_DATA_DIR:=./data/mysql}"
: "${COMPOSER_CACHE_DIR:=./data/composer-cache}"

# --- Validate required vars ---
: "${DRUPAL_HOST_PATH:?DRUPAL_HOST_PATH must be set (absolute path to Drupal on host)}"

case "$DRUPAL_HOST_PATH" in
  /*) : ;;  # absolute — OK
  *)
    echo "ERROR: DRUPAL_HOST_PATH must be an absolute path (got '$DRUPAL_HOST_PATH')." >&2
    exit 1
    ;;
esac

# --- Ensure expected directories exist ---
mkdir -p "$MYSQL_DATA_DIR" "$COMPOSER_CACHE_DIR" "./certs" "./solr/core" "./data"

if [ ! -d "$DRUPAL_HOST_PATH" ]; then
  echo "ERROR: DRUPAL_HOST_PATH '$DRUPAL_HOST_PATH' does not exist on the host." >&2
  echo "Create/clone your Drupal repo there, then re-run." >&2
  exit 1
fi

# --- Summary ---
echo "Preflight OK."
echo "  Repo root:            $REPO_ROOT"
echo "  Using env file:       $ENV_FILE"
echo "  Drupal path:          $DRUPAL_HOST_PATH"
echo "  MySQL data dir:       $MYSQL_DATA_DIR"
echo "  Composer cache dir:   $COMPOSER_CACHE_DIR"
echo "  Certs dir:            ./certs"
echo "  Solr core dir:        ./solr/core"

