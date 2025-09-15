# 1) Show which container is running and its entrypoint/cmd
CID="$(docker compose ps -q php81-apache)"
docker inspect "$CID" --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'

# If you see /entrypoint.sh or render-and-run.sh here,
# you are still on the "runtime render" image.

