#!/usr/bin/env bash
set -euo pipefail

# Helpful debug
echo "[entrypoint] APACHE_SERVER_NAME=${APACHE_SERVER_NAME:-}"
echo "[entrypoint] APACHE_SERVER_ALIAS=${APACHE_SERVER_ALIAS:-}"
echo "[entrypoint] APACHE_DOCROOT=${APACHE_DOCROOT:-/var/www/miraweb2024/docroot}"
echo "[entrypoint] SDMC_ENV=${SDMC_ENV:-}"
echo "[entrypoint] SSL_ENABLE=${SSL_ENABLE:-0}"

# Ensure docroot exists (avoid Apache start failure)
DOCROOT="${APACHE_DOCROOT:-/var/www/miraweb2024/docroot}"
if [[ ! -d "$DOCROOT" ]]; then
  echo "[entrypoint] ERROR: APACHE_DOCROOT not found: $DOCROOT" >&2
  ls -la "$(dirname "$DOCROOT")" || true
  exit 1
fi

# Render vhosts from templates (requires gettext's envsubst)
render_site() {
  local tmpl="$1" out="$2"
  if [[ -f "$tmpl" ]]; then
    envsubst < "$tmpl" > "$out"
    echo "[entrypoint] rendered $(basename "$out")"
    a2ensite "$(basename "$out")" >/dev/null
  else
    echo "[entrypoint] WARN: template not found: $tmpl"
  fi
}

# Disable the Debian default site to avoid conflicts
a2dissite 000-default 000-default-ssl >/dev/null 2>&1 || true

# Always render the HTTP vhost
render_site /etc/apache2/sites-available/dev.conf.template /etc/apache2/sites-available/dev.conf

# Optionally render the HTTPS vhost
if [[ "${SSL_ENABLE:-0}" = "1" ]]; then
  render_site /etc/apache2/sites-available/dev-ssl.conf.template /etc/apache2/sites-available/dev-ssl.conf
  a2enmod ssl >/dev/null || true
else
  a2dissite dev-ssl.conf >/dev/null 2>&1 || true
fi

# Minimal PassEnv (if your PHP relies on env vars directly)
# You can also do SetEnv in your vhost templates.
printf "PassEnv SDMC_ENV\n" > /etc/apache2/conf-enabled/00-passenv.conf

# Check config before starting
apachectl -t

# Hand off to the main process (from CMD)
echo "[entrypoint] starting: $*"
exec "$@"
