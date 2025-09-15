#!/usr/bin/env bash
set -Eeuo pipefail

log(){ printf "[entrypoint] %s\n" "$*"; }
die(){ echo "[entrypoint:ERROR] $*" >&2; exit 1; }

# Show critical envs (for quick debugging)
log "APACHE_SERVER_NAME=${APACHE_SERVER_NAME:-}"
log "APACHE_SERVER_ALIAS=${APACHE_SERVER_ALIAS:-}"
log "APACHE_DOCROOT=${APACHE_DOCROOT:-/var/www/miraweb2024/docroot}"
log "SDMC_ENV=${SDMC_ENV:-dev}"
log "SSL_ENABLE=${SSL_ENABLE:-0}"

# Ensure a global ServerName so Apache doesn’t complain
printf "ServerName %s\n" "${APACHE_SERVER_NAME:-dev.loc}" \
  > /etc/apache2/conf-available/servername.conf
a2enconf servername >/dev/null 2>&1 || true

# Basic sanity
command -v envsubst >/dev/null || die "envsubst not found (gettext missing)."
[ -d /etc/apache2/sites-available ] || die "Apache sites-available missing."

# Guard against read-only /etc (helps diagnose compose misconfig)
if ! touch /etc/apache2/.rwtest 2>/dev/null; then
  die "/etc/apache2 is not writable (read-only FS). Remove any 'read_only: true' or RO bind mounts to /etc in compose."
fi
rm -f /etc/apache2/.rwtest || true

# Render vhosts from templates using current env
render() {
  local tpl="$1" out="$2"
  [ -f "$tpl" ] || die "Template not found: $tpl"
  envsubst <"$tpl" >"$out".tmp
  mv -f "$out".tmp "$out"
  log "Rendered $(basename "$out")"
}

render "/opt/vhost-templates/dev.conf.template"     "/etc/apache2/sites-available/dev.conf"
if [ "${SSL_ENABLE:-0}" = "1" ]; then
  render "/opt/vhost-templates/dev-ssl.conf.template" "/etc/apache2/sites-available/dev-ssl.conf"
fi

# Enable our sites
a2dissite 000-default >/dev/null 2>&1 || true
a2ensite dev >/dev/null
if [ "${SSL_ENABLE:-0}" = "1" ]; then
  a2enmod ssl >/dev/null || true
  a2ensite dev-ssl >/dev/null
else
  a2dissite dev-ssl >/dev/null 2>&1 || true
fi

# Final config test
apache2ctl -t

# Hand off to Apache
exec apache2-foreground

