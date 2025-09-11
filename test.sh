# from repo root
git show 68f94d3:bin/composer > bin/composer-strict
chmod +x bin/composer bin/composer-strict
git add bin/composer bin/composer-strict
git commit -m "Composer: minimal container-only wrapper; keep advanced checks as bin/composer-strict"

