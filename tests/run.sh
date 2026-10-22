#!/bin/sh
# usage: tests/run.sh <image>
# Builds tests/Dockerfile on top of <image>, starts it and checks CLI and
# Apache behave like the official php:<version>-apache image.
set -eu

image="$1"
dir="$(dirname "$0")"
test_image="$image-test"
name="php-apache-test-$$"

docker build --build-arg BASE_IMAGE="$image" -t "$test_image" "$dir"

fail() { echo >&2 "FAIL: $*"; exit 1; }

for ext in gd intl zip mysqli pdo_mysql soap curl mbstring dom simplexml json sodium; do
	docker run --rm "$test_image" php -r "exit(extension_loaded('$ext') ? 0 : 1);" || fail "CLI: $ext not loaded"
done
docker run --rm "$test_image" php -r 'exit(function_exists("opcache_get_status") ? 0 : 1);' || fail "CLI: opcache not loaded"
docker run --rm "$test_image" php -r 'exit(extension_loaded("ionCube Loader") ? 0 : 1);' || fail "CLI: ioncube not loaded"
docker run --rm "$test_image" php -r '$i = gd_info(); exit($i["FreeType Support"] && $i["JPEG Support"] && $i["WebP Support"] && $i["PNG Support"] ? 0 : 1);' || fail "gd lacks freetype/jpeg/webp/png"
warnings="$(docker run --rm "$test_image" php -r ';' 2>&1)"
[ -z "$warnings" ] || fail "php startup output: $warnings"

# a mount over conf.d must not take the baseline extensions with it
docker run --rm --tmpfs /usr/local/etc/php/conf.d "$image" \
	php -r 'foreach (["curl", "mbstring", "json", "PDO", "mysqlnd", "dom"] as $x) if (!extension_loaded($x)) exit(1);' \
	|| fail "baseline extensions lost with an empty conf.d"
[ "$(docker run --rm "$image" php -r 'echo ini_get("session.save_path");')" = '' ] || fail "default session.save_path not empty"
[ "$(docker run --rm "$image" sh -c 'echo "session.save_path=/srv/s" > "$PHP_INI_DIR/php.ini"; php -r "echo ini_get(\"session.save_path\");"')" = '/srv/s' ] \
	|| fail "session.save_path from php.ini overridden"
[ "$(docker run --rm "$image" sh -c 'cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; php -r "echo ini_get(\"session.gc_probability\"), ini_get(\"disable_functions\");"')" = '1' ] \
	|| fail "php.ini-production differs from upstream"

# helper scripts
docker run --rm "$image" sh -ec '
	docker-php-ext-install pcntl sodium curl
	mkdir /tmp/gd && cd /tmp && docker-php-ext-install --ini-name 05-opcache.ini gd opcache
	test -f "$PHP_INI_DIR/conf.d/05-opcache.ini"
	docker-php-ext-enable opcache
	out="$(php -r "exit(extension_loaded(\"gd\") && extension_loaded(\"Zend OPcache\") ? 0 : 1);" 2>&1)"
	test -z "$out"
	docker-php-ext-install mysqli redis
	php -r "exit(extension_loaded(\"mysqli\") && !extension_loaded(\"pdo_mysql\") && extension_loaded(\"redis\") ? 0 : 1);"
	test -z "$(php -r ";" 2>&1)"
' > /dev/null 2>&1 || fail "docker-php-ext-install/enable compatibility"

# package upgrades (simulated by reinstall) must not trip over the config layout
docker run --rm "$test_image" sh -ec '
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall "php$PHP_VERSION-cli" "libapache2-mod-php$PHP_VERSION" "php$PHP_VERSION-gd"
	php -r "exit(extension_loaded(\"gd\") && extension_loaded(\"ionCube Loader\") ? 0 : 1);"
	test -z "$(php -r ";" 2>&1)"
' > /dev/null 2>&1 || fail "reinstall of PHP packages"

docker run -d --name "$name" -p 127.0.0.1::80 "$test_image" > /dev/null
trap 'docker rm -f "$name" > /dev/null' EXIT
port="$(docker port "$name" 80 | head -1 | sed 's/.*://')"
i=0
until body="$(curl -fsS "http://127.0.0.1:$port/")"; do
	i=$((i + 1))
	[ "$i" -lt 20 ] || fail "apache not answering"
	sleep 0.5
done

echo "$body"
echo "$body" | grep -qx '333M' || fail "conf.d ini not applied to apache SAPI"
echo "$body" | grep -qx 'ioncube' || fail "ioncube not loaded in apache SAPI"
echo "$body" | grep -q 'Zend OPcache' || fail "opcache not loaded in apache SAPI"
phtml="$(curl -fsS "http://127.0.0.1:$port/test.phtml")" || fail ".phtml request failed"
[ "$phtml" = '<?php echo "exec" . "uted";' ] || fail ".phtml executed (official image serves it as a file): $phtml"
docker logs "$name" 2>&1 | grep -q 'GET / HTTP' || fail "access log not on stdout"

echo "OK: $image"
