# From your infra repo root:
docker compose config --services

docker compose ps

# Bring ONLY the web service up (so we know it’s running)
docker compose up -d php81-apache

# Sanity: does the container have Apache?
docker compose exec php81-apache bash -lc 'apache2 -v || which apache2ctl'
