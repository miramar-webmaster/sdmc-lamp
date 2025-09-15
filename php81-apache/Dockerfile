# php81-apache/Dockerfile
FROM php:8.1-apache-bullseye

# PHP extensions
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions \
 && install-php-extensions \
      gd mysqli pdo_mysql intl soap zip bz2 opcache \
      dom xml xmlreader xmlwriter mbstring curl shmop readline \
      imap imagick memcached

# Tools & CA bundle (envsubst is in gettext)
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gettext \
 && update-ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Composer available inside the container
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Apache modules + PHP ini
RUN a2enmod env ssl rewrite headers expires proxy proxy_http setenvif
COPY php.ini /usr/local/etc/php/conf.d/custom.ini

# Keep vhost TEMPLATES in a neutral path (not /etc)
COPY dev.conf.template      /opt/vhost-templates/dev.conf.template
COPY dev-ssl.conf.template  /opt/vhost-templates/dev-ssl.conf.template

# Entrypoint that renders templates with envsubst, then enables sites
COPY entrypoint.sh /usr/local/bin/render-and-run.sh
RUN chmod +x /usr/local/bin/render-and-run.sh
ENTRYPOINT ["/usr/local/bin/render-and-run.sh"]

# Default CMD from base (apache2-foreground) is fine

