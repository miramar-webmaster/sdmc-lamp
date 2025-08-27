#!/usr/bin/env bash
set -Eeuo pipefail

# Defaults if not provided (safe for dev)
: "${APACHE_SERVER_NAME:=localhost}"
: "${APACHE_SERVER_ALIAS:=localhost}"
: "${APACHE_DOCROOT:=/var/www/miraweb2024}"
: "${SSL_CERT_FILE:=/certs/dev.crt}"
: "${SSL_CERT_KEY_FILE:=/certs/dev.key}"
: "${SSL_ENABLE:=1}"   # 1 = enable SSL vhost, 0 = disable

# Ensure required modules are on
a2enmod env headers rewrite ssl >/dev/null 2>&1 || true

# Clean ports.conf to avoid duplicate Listeners
cat >/etc/apache2/ports.conf <<EOF
Listen 80
<IfModule ssl_module>
    Listen 443
</IfModule>
EOF

# Inject variables Apache can expand in configs
cat >/etc/apache2/conf-available/00-sdmc-vars.conf <<EOF
Define APACHE_SERVER_NAME ${APACHE_SERVER_NAME}
Define APACHE_SERVER_ALIAS ${APACHE_SERVER_ALIAS}
Define APACHE_DOCROOT ${APACHE_DOCROOT}
Define SSL_CERT_FILE ${SSL_CERT_FILE}
Define SSL_CERT_KEY_FILE ${SSL_CERT_KEY_FILE}
EOF
a2enconf 00-sdmc-vars >/dev/null

# Enable/disable SSL site based on flag
a2ensite 000-default >/dev/null
if [ "${SSL_ENABLE}" = "1" ]; then a2ensite 000-default-ssl >/dev/null; else a2dissite 000-default-ssl >/dev/null || true; fi

# Final sanity
apache2ctl -t

# Run Apache in foreground
exec apache2-foreground
