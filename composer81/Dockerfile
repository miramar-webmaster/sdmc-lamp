FROM php:8.1-cli-bullseye

# Tools Composer needs for typical Drupal workflows
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip zip openssh-client ca-certificates \
    libzip-dev libicu-dev libxml2-dev libonig-dev \
 && docker-php-ext-install zip intl mbstring \
 && rm -rf /var/lib/apt/lists/*

# Install Composer (official installer)
ENV COMPOSER_VERSION=2
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
 && php composer-setup.php --filename=composer --install-dir=/usr/local/bin \
 && rm composer-setup.php

# Non-root default user is set at runtime via docker-compose (user: HOST_UID:HOST_GID)

