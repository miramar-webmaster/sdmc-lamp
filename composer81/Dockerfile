FROM php:8.1-cli-bullseye

# Tools composer needs
RUN apt-get update && apt-get install -y --no-install-recommends \
      git unzip openssh-client ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Composer binary
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Robust PHP extension installer
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

# === Install the minimal set Composer needs to satisfy your project's constraints ===
# (Match your runtime: gd, intl, mbstring, zip, pdo_mysql)
RUN install-php-extensions gd intl mbstring zip pdo_mysql

WORKDIR /workspace
ENV COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_HOME=/composer
ENTRYPOINT ["composer"]
