#!/bin/bash
set -e

# Substitute environment variables in the template
envsubst < /etc/apache2/sites-available/dev.conf.template > /etc/apache2/sites-available/000-default.conf
envsubst < /etc/apache2/sites-available/dev-ssl.conf.template > /etc/apache2/sites-available/000-default-ssl.conf

# Enable the site (if not already enabled)
a2ensite 000-default
a2ensite 000-default-ssl

cat /etc/apache2/sites-available/000-default.conf
cat /etc/apache2/sites-available/000-default-ssl.conf

# Start Apache
exec apache2-foreground