# Drop-in replacement for the official php:<version>-apache image, built from
# the deb.sury.org packages instead of the upstream source tarball. Sury keeps
# backporting security fixes to PHP releases that upstream no longer patches,
# so a rebuild picks up both PHP and Debian security updates.
ARG DEBIAN_RELEASE=trixie
FROM debian:${DEBIAN_RELEASE}-slim

# major.minor, e.g. 7.3
ARG PHP_VERSION=7.3
ENV PHP_VERSION=${PHP_VERSION}

# Same build toolchain the official image keeps installed, so pecl/phpize work.
ENV PHPIZE_DEPS="\
		autoconf \
		dpkg-dev \
		file \
		g++ \
		gcc \
		libc-dev \
		make \
		pkg-config \
		re2c"

# Only Sury may provide PHP; Debian's own php* packages are a different version.
RUN set -eux; \
	{ \
		echo 'Package: php*'; \
		echo 'Pin: release o=Debian'; \
		echo 'Pin-Priority: -1'; \
	} > /etc/apt/preferences.d/no-debian-php; \
	apt-get update; \
	apt-get install -y --no-install-recommends ca-certificates curl xz-utils; \
	curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb; \
	dpkg -i /tmp/debsuryorg-archive-keyring.deb; \
	rm /tmp/debsuryorg-archive-keyring.deb; \
	. /etc/os-release; \
	echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $VERSION_CODENAME main" > /etc/apt/sources.list.d/php.list; \
	rm -rf /var/lib/apt/lists/*

ENV PHP_INI_DIR=/usr/local/etc/php
# php.ini is looked up in PHPRC first; the leading ":" appends to the
# compiled-in scan dir instead of replacing it.
ENV PHPRC=$PHP_INI_DIR
ENV PHP_INI_SCAN_DIR=:$PHP_INI_DIR/conf.d
ENV APACHE_CONFDIR=/etc/apache2
ENV APACHE_ENVVARS=$APACHE_CONFDIR/envvars

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends $PHPIZE_DEPS apache2; \
	# Extensions the official image ships enabled; the rest are opt-in through
	# docker-php-ext-install. Packages missing for a given PHP version (json is
	# built in since 8.0) are skipped.
	pkgs="libapache2-mod-php$PHP_VERSION php$PHP_VERSION-cli php$PHP_VERSION-dev"; \
	for ext in curl json mbstring mysql opcache readline sqlite3 xml; do \
		if apt-cache policy "php$PHP_VERSION-$ext" | grep -q 'Candidate: [0-9]'; then pkgs="$pkgs php$PHP_VERSION-$ext"; fi; \
	done; \
	apt-get install -y --no-install-recommends $pkgs; \
	# php-pear depends on php-xml, which php$PHP_VERSION-xml provides once it is
	# installed; installing them together would pull in Sury's default PHP.
	apt-get install -y --no-install-recommends php-pear; \
	rm -rf /var/lib/apt/lists/*; \
	\
	others="$(dpkg-query -W -f '${Package}\n' | grep -E '^(php|libapache2-mod-php)[0-9]' | grep -vF "$PHP_VERSION" || :)"; \
	[ -z "$others" ] || { echo >&2 "unexpected PHP packages: $others"; exit 1; }; \
	\
	# The per-SAPI /etc/php/$PHP_VERSION/<sapi>/{php.ini,conf.d} stay
	# package-managed and hold the baseline: extensions the official image has
	# compiled in. Their php.ini becomes empty, as the official image runs on
	# built-in defaults; ucf keeps that local edit on package upgrades. Everything
	# user-facing lives in $PHP_INI_DIR, reached through PHPRC and
	# PHP_INI_SCAN_DIR, so mounting over $PHP_INI_DIR/conf.d keeps the baseline.
	mkdir -p "$PHP_INI_DIR/conf.d"; \
	for sapi in apache2 cli; do \
		echo "; intentionally empty, use $PHP_INI_DIR/php.ini" > "/etc/php/$PHP_VERSION/$sapi/php.ini"; \
		# Debian's build defaults session.save_path to /var/lib/php/sessions;
		# upstream defaults to "" (system temp dir). Keep a value from php.ini.
		echo 'session.save_path = "${session.save_path}"' > "/etc/php/$PHP_VERSION/$sapi/conf.d/00-docker-php-session.ini"; \
	done; \
	\
	for mod in $(phpquery -v "$PHP_VERSION" -M); do \
		case " ctype curl dom fileinfo ftp iconv json mbstring mysqlnd pdo pdo_sqlite phar posix readline simplexml sodium sqlite3 tokenizer xml xmlreader xmlwriter " in \
			*" $mod "*) ;; \
			*) phpdismod -v "$PHP_VERSION" -s ALL "$mod" ;; \
		esac; \
	done; \
	\
	# Upstream templates, as in the official image; Debian's differ (session GC
	# off, pcntl functions disabled).
	v="$(php -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION, ".", PHP_RELEASE_VERSION;')"; \
	for f in php.ini-development php.ini-production; do \
		curl -fsSL -o "$PHP_INI_DIR/$f" "https://raw.githubusercontent.com/php/php-src/php-$v/$f"; \
	done; \
	\
	mkdir -p /var/www/html; \
	chown www-data:www-data /var/www/html; \
	chmod 777 /var/www/html; \
	\
	# Apache setup copied from the official image.
	sed -ri 's/^export ([^=]+)=(.*)$/: ${\1:=\2}\nexport \1/' "$APACHE_ENVVARS"; \
	. "$APACHE_ENVVARS"; \
	for dir in \
		"$APACHE_LOCK_DIR" \
		"$APACHE_RUN_DIR" \
		"$APACHE_LOG_DIR" \
	; do \
		rm -rvf "$dir"; \
		mkdir -p "$dir"; \
		chown "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$dir"; \
		chmod 777 "$dir"; \
	done; \
	rm -rvf /var/www/html/*; \
	ln -sfT /dev/stderr "$APACHE_LOG_DIR/error.log"; \
	ln -sfT /dev/stdout "$APACHE_LOG_DIR/access.log"; \
	ln -sfT /dev/stdout "$APACHE_LOG_DIR/other_vhosts_access.log"; \
	chown -R --no-dereference "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$APACHE_LOG_DIR"; \
	\
	a2dismod mpm_event; \
	a2enmod mpm_prefork "php$PHP_VERSION"; \
	# Debian's handler also executes .phtml/.phar; the official one only .php.
	echo '# replaced by conf-available/docker-php.conf' > "/etc/apache2/mods-available/php$PHP_VERSION.conf"

RUN { \
		echo '<FilesMatch \.php$>'; \
		echo '\tSetHandler application/x-httpd-php'; \
		echo '</FilesMatch>'; \
		echo; \
		echo 'DirectoryIndex disabled'; \
		echo 'DirectoryIndex index.php index.html'; \
		echo; \
		echo '<Directory /var/www/>'; \
		echo '\tOptions -Indexes'; \
		echo '\tAllowOverride All'; \
		echo '</Directory>'; \
	} | tee "$APACHE_CONFDIR/conf-available/docker-php.conf" \
	&& a2enconf docker-php

COPY docker-php-ext-* docker-php-entrypoint apache2-foreground /usr/local/bin/

RUN php --version && php -m

ENTRYPOINT ["docker-php-entrypoint"]
STOPSIGNAL SIGWINCH
WORKDIR /var/www/html
EXPOSE 80
CMD ["apache2-foreground"]
