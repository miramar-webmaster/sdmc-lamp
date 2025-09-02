FROM php:8.1-apache-bullseye

# Install PHP extensions needed by Drupal 10
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions \
 && install-php-extensions \
      gd mysqli pdo_mysql intl soap zip bz2 opcache \
      dom xml xmlreader xmlwriter mbstring curl shmop readline \
      imap imagick memcached

RUN apt-get update && apt-get install -y gettext

# Enable required Apache modules
RUN a2enmod env ssl rewrite headers expires proxy proxy_http setenvif

# PHP runtime settings
COPY php.ini /usr/local/etc/php/conf.d/custom.ini

# Final, literal vhosts (use a fixed in-container docroot)
#COPY 000-default.conf     /etc/apache2/sites-available/000-default.conf
#COPY 000-default-ssl.conf /etc/apache2/sites-available/000-default-ssl.conf

# One canonical ports.conf and enable both sites
RUN printf "Listen 80\n<IfModule ssl_module>\n    Listen 443\n</IfModule>\n" > /etc/apache2/ports.conf

COPY dev.conf.template /etc/apache2/sites-available/dev.conf.template
COPY dev-ssl.conf.template /etc/apache2/sites-available/dev-ssl.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

#CMD ["apache2-foreground"]
