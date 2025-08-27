# 1) See which compose files Compose is actually loading
for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml docker-compose.override.yml; do
  [ -f "$f" ] && echo "-> $f"
done

# 2) Show the merged config BEFORE interpolation; grep the smoking gun
docker compose config --no-interpolate 2>/dev/null | grep -n 'MYSQL_ROOT_PASSWORD' -C2 || echo "No reference in merged config"

# 3) Search ALL compose files (yml/yaml) for either ${…} or $… forms and healthchecks
grep -nRE --include='*compose*.yml' --include='*compose*.yaml' \
  -e '\${MYSQL_ROOT_PASSWORD[^}]*}' \
  -e '(^|[^A-Za-z0-9_])MYSQL_ROOT_PASSWORD([^A-Za-z0-9_]|$)' \
  -e '\-p\$MYSQL_ROOT_PASSWORD' .
