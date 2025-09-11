# php81-apache/Dockerfile
FROM php:8.1-apache-bullseye

# --- PHP extensions (via official helper) ---
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions \
 && install-php-extensions \
      gd mysqli pdo_mysql intl soap zip bz2 opcache \
      dom xml xmlreader xmlwriter mbstring curl shmop readline \
      imap imagick memcached

# --- Core tools & CA bundle (for HTTPS fetches, patches, etc.) ---
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gettext \
 && update-ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# --- OPTIONAL guard: enforce PHP major.minor at build (unset to skip) ---
ARG REQUIRED_PHP=""
ENV REQUIRED_PHP=${REQUIRED_PHP}
# Show the version
RUN php -r 'echo PHP_VERSION, "\n";'
# Enforce if provided (e.g., --build-arg REQUIRED_PHP=8.1)
RUN if [ -n "$REQUIRED_PHP" ]; then \
      php -r 'exit(version_compare(PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION, getenv("REQUIRED_PHP"), "==") ? 0 : 1);'; \
    else \
      echo "REQUIRED_PHP not set; skipping PHP major.minor check"; \
    fi
# Sanity: make sure gd is actually loaded
RUN php -m | grep -qi '^gd$' || (echo "ext-gd missing in image" >&2; exit 1)

# --- Composer baked in (avoids runtime SSL fetch issues) ---
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# --- Apache modules you rely on ---
RUN a2enmod env ssl rewrite headers expires proxy proxy_http setenvif

# --- PHP runtime config ---
COPY php.ini /usr/local/etc/php/conf.d/custom.ini

# --- VHost templates + entrypoint ---
# The entrypoint will render these templates using .env (APACHE_SERVER_NAME, APACHE_DOCROOT, SDMC_ENV, SSL_*).
COPY dev.conf.template      /etc/apache2/sites-available/dev.conf.template
COPY dev-ssl.conf.template  /etc/apache2/sites-available/dev-ssl.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Entry flow: render vhosts in entrypoint, then hand off to apache
ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]

