# Strictly PHP 8.1 with Apache (mod_php)
FROM php:8.1-apache-bullseye

ARG APACHE_DOCROOT=/var/www/miraweb2024

# System libs for requested PHP extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip ca-certificates curl \
    libzip-dev libicu-dev libxml2-dev libonig-dev libbz2-dev \
    libjpeg-dev libpng-dev libfreetype6-dev libwebp-dev \
    libcurl4-openssl-dev libreadline-dev \
    libssl-dev zlib1g-dev libmemcached-dev \
    libmagickwand-dev \
    libc-client2007e-dev libkrb5-dev \
    # sendmail shim:
    msmtp-mta \
 && rm -rf /var/lib/apt/lists/*

# Core extensions covering your list
# - mysqli (php8.1-mysqli)
# - mysqlnd (bundled — used by mysqli/pdo_mysql)
# - imap (php8.1-imap)
# - xml, xmlreader, xmlwriter, dom
# - curl, gd, imagick (via PECL), cli is included
# - ctype, gettext (built-in), dev headers not needed at runtime
# - mbstring, opcache
# - memcached (via PECL)
# - readline, soap, zip, intl, bz2, shmop
# - xmlrpc: not available on PHP 8.x (see note below)
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
 && docker-php-ext-install -j"$(nproc)" \
    mysqli pdo_mysql intl soap zip bz2 opcache dom xml xmlreader xmlwriter \
    ctype mbstring curl shmop readline gd

# IMAP (enable with SSL/Kerberos); keep build robust if headers differ
RUN docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
 && docker-php-ext-install -j"$(nproc)" imap || true

# PECL: imagick + memcached
RUN pecl install imagick \
 && docker-php-ext-enable imagick \
 && printf "\n" | pecl install memcached \
 && docker-php-ext-enable memcached

# Apache mods commonly needed by Drupal
RUN a2enmod rewrite headers expires proxy proxy_http setenvif

# Set document root
ENV APACHE_DOCUMENT_ROOT=${APACHE_DOCROOT}
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
            -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf

# Health/verification: list enabled modules at build time (useful in CI logs)
RUN php -v && php -m | sort

# Entrypoint will render vhost from template at runtime
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

COPY apache-vhost.conf.template /etc/apache2/sites-available/000-default.conf.template
COPY php.ini /usr/local/etc/php/conf.d/custom.ini

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]

