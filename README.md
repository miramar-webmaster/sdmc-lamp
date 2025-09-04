# SDMC LAMP Infra (Docker)

This repo contains Docker Compose services for MySQL 8.0, PHP 8.1 + Apache, Memcached, Node (npm + Sass), and Solr 8.6.2.  
It mounts an **existing Drupal checkout on the HOST**.

## Prereqs on Ubuntu 24.04
- Git, Composer (already present per your environment)
- Run once to install Docker Engine + Compose:
  ```bash
  ./scripts/install-docker-ubuntu24.sh
  # log out/in or: newgrp docker

