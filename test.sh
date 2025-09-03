# 1) Show active vhosts
docker compose exec -T php81-apache bash -lc 'apachectl -S'

# 2) Show if mod_ssl is loaded
docker compose exec -T php81-apache bash -lc 'a2query -m ssl || true'

# 3) Show rendered site files and what's enabled
docker compose exec -T php81-apache bash -lc '
  echo "--- sites-available ---"; ls -l /etc/apache2/sites-available;
  echo "--- sites-enabled ---";   ls -l /etc/apache2/sites-enabled;
  echo "--- dev.conf (HTTP) ---"; sed -n "1,160p" /etc/apache2/sites-available/dev.conf || true
  echo "--- dev-ssl.conf (HTTPS) ---"; sed -n "1,200p" /etc/apache2/sites-available/dev-ssl.conf || true
'

# 4) Check the cert/key files exist in the container and paths match
docker compose exec -T php81-apache bash -lc '
  echo "SSL_CERT_FILE=$SSL_CERT_FILE"; echo "SSL_CERT_KEY_FILE=$SSL_CERT_KEY_FILE"; echo "SSL_ENABLE=$SSL_ENABLE";
  ls -l "$SSL_CERT_FILE" "$SSL_CERT_KEY_FILE"
'
