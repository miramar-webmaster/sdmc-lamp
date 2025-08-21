#!/usr/bin/env bash
set -e
envsubst < /etc/apache2/sites-available/000-default.conf.template > /etc/apache2/sites-available/000-default.conf
touch /var/log/msmtp.log || true
chmod 666 /var/log/msmtp.log || true
exec "$@"

