# ./composer81/Dockerfile
FROM php:8.1-cli-bullseye

# Tools Composer needs
RUN apt-get update && apt-get install -y --no-install-recommends \
      git unzip openssh-client ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Grab latest Composer binary from the official image
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Defaults (compose overrides user/working_dir)
ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_HOME=/composer

WORKDIR /workspace
ENTRYPOINT ["composer"]
