FROM php:8.1-apache-bullseye

# --- Fixed docroot inside the container ---
ARG APACHE_DOCROOT=/var/www/app
ENV APACHE_DOCUMENT_ROOT=${APACHE_DOCROOT}

# Small runtime tools
RUN apt-get update && apt-get install -y --no-install-recommends \
      gettext-base msmtp-mta ca-certificates curl git unzip \
  && rm -rf /var/lib/apt/lists/*

# Robust PHP extension installer
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

# === Your required PHP 8.1 extensions ===
RUN install-php-extensions \
      gd \
      mysqli pdo_mysql \
      intl soap zip bz2 opcache \
      dom xml xmlreader xmlwriter \
      mbstring curl shmop readline \
      imap \
      imagick \
      memcached

# Apache modules
RUN a2enmod ssl rewrite headers expires proxy proxy_http setenvif

# Point Apache configs at our fixed docroot
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
            -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf

# PHP settings
COPY php.ini /usr/local/etc/php/conf.d/custom.ini

# --- Copy final vhosts (no templating at runtime) ---
# These two files must be present in php81-apache/ in your repo.
# They should reference DocumentRoot /var/www/app and certs at /certs/dev.crt|dev.key

COPY php.ini /usr/local/etc/php/conf.d/custom.ini
COPY 000-default.conf     /etc/apache2/sites-available/000-default.conf
COPY 000-default-ssl.conf /etc/apache2/sites-available/000-default-ssl.conf

# Ensure Apache listens on 443 and enable both sites
RUN grep -q "^Listen 443" /etc/apache2/ports.conf || echo "Listen 443" >> /etc/apache2/ports.conf \
 && a2ensite 000-default 000-default-ssl

 COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
 && a2ensite 000-default 000-default-ssl

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]


# IMPORTANT: remove the custom entrypoint — we don't render templates anymore
#CMD ["apache2-foreground"]
