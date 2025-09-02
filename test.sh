NODE_SVC="${NODE_SERVICE:-node}"

docker compose run --rm \
  -w /var/www/miraweb2024/docroot/themes/custom/sdmc \
  --user "$(id -u):$(id -g)" \
  "$NODE_SVC" sh -lc 'npm ci && npm run build'