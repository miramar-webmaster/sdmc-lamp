# scripts/preflight.sh
#!/usr/bin/env bash
set -euo pipefail

: "${DRUPAL_HOST_PATH:?DRUPAL_HOST_PATH must be set (absolute path to Drupal on host)}"
: "${MYSQL_DATA_DIR:=./data/mysql}"
: "${COMPOSER_CACHE_DIR:=./data/composer-cache}"

mkdir -p "$MYSQL_DATA_DIR" "$COMPOSER_CACHE_DIR" "./certs" "./solr/core" "./data"

if [ ! -d "$DRUPAL_HOST_PATH" ]; then
  echo "ERROR: DRUPAL_HOST_PATH '$DRUPAL_HOST_PATH' does not exist on the host."
  echo "Create/clone your Drupal repo there, then re-run."
  exit 1
fi

echo "Preflight OK."
echo "  Drupal path:          $DRUPAL_HOST_PATH"
echo "  MySQL data dir:       $MYSQL_DATA_DIR"
echo "  Composer cache dir:   $COMPOSER_CACHE_DIR"
echo "  Certs dir:            ./certs"
echo "  Solr core dir:        ./solr/core"

