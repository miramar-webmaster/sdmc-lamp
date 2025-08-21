#!/usr/bin/env bash
set -euo pipefail
: "${DRUPAL_HOST_PATH:?DRUPAL_HOST_PATH must be set (absolute path to Drupal on host)}"
: "${MYSQL_DATA_DIR:=./data/mysql}"

if [ ! -d "$DRUPAL_HOST_PATH" ]; then
  echo "ERROR: DRUPAL_HOST_PATH '$DRUPAL_HOST_PATH' does not exist."
  exit 1
fi

mkdir -p "$MYSQL_DATA_DIR"
echo "Preflight OK. Drupal: $DRUPAL_HOST_PATH ; MySQL data dir: $MYSQL_DATA_DIR"

