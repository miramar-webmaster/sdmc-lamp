FROM php:8.1-apache-bullseye

ARG APACHE_DOCROOT=/var/www/miraweb2024
ENV APACHE_DOCUMENT_ROOT=${APACHE_DOCROOT}

# Tiny utilities we actually use at runtime
# - gettext-base -> envsubst used by entrypoint
# - msmtp-mta    -> sendmail shim for PHP mail()
RUN apt-get update && apt-get install -y --no-install-recommends \
      gettext-base msmtp-mta ca-certificates curl git unzip \
  && rm -rf /var/lib/apt/lists/*

# Robust installer for PHP extensions (handles apt/pecl deps automatically)
# Docs: https://github.com/mlocati/docker-php-extension-installer
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

# === Install ALL required extensions for PHP 8.1 ===
# (xmlrpc is not available on PHP 8.1, everything else is here)
RUN install-php-extensions \
      gd \
      mysqli pdo_mysql \
      intl soap zip bz2 opcache \
      dom xml xmlreader xmlwriter \
      mbstring curl shmop readline \
      imap \
      imagick \
      memcached

# Apache modules commonly needed
RUN a2enmod ssl rewrite headers expires proxy proxy_http setenvif

# Point Apache to your docroot
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
            -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf

# (Your existing templates)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
COPY apache-vhost.conf.template /etc/apache2/sites-available/000-default.conf.template
COPY php.ini /usr/local/etc/php/conf.d/custom.ini

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]
