# php-apache

Drop-in replacement for the official `php:<version>-apache` images, kept up to
date for PHP versions the official images no longer rebuild.

The official `php:7.3-apache` was last built in 2022: PHP 7.3 is end of life,
so it receives neither PHP nor Debian security fixes. These images install PHP
from [deb.sury.org](https://deb.sury.org/), which backports security fixes
to old PHP branches (see the `Backported from 8.x` entries in the package
changelog), on top of the current Debian stable (`trixie`).
They are rebuilt weekly.

Automatically built and published to Docker Hub:
https://hub.docker.com/r/evox95/php

## Tags

| Tag | Description |
|-----|-------------|
| `7.3-apache` | latest weekly build |
| `7.3-apache-trixie` | same, pinned to the Debian release |
| `7.3-apache-YYYYMMDD-<run>` | one specific build, never overwritten; use it to pin or roll back |

Platforms: `linux/amd64`, `linux/arm64`.

## Usage

Replace the `FROM` line:

```dockerfile
FROM evox95/php:7.3-apache
```

Same layout as the official image:

- `/usr/local/etc/php/conf.d/*.ini` is loaded by both Apache and CLI;
  `php.ini-production` / `php.ini-development` live in `/usr/local/etc/php/`
- `docker-php-ext-install`, `docker-php-ext-configure`, `docker-php-ext-enable`,
  `pecl`, `php-config`, `phpize`
- Apache with `mpm_prefork` + mod_php, docroot `/var/www/html`, logs to
  stdout/stderr, `apache2-foreground` as `CMD`
- the same set of extensions enabled by default

## Differences from the official image

- Extensions come prebuilt from the `php7.3-*` packages. `docker-php-ext-install gd`
  runs `apt-get install php7.3-gd` and enables it in
  `/usr/local/etc/php/conf.d/docker-php-ext-gd.ini` (`--ini-name` works as usual).
  `docker-php-ext-configure` only accepts and ignores its flags (gd already has
  FreeType, JPEG and WebP). Building an extension from a source directory is not
  supported; use `pecl install` instead.
- Extensions the official image compiles in are shared modules here, loaded from
  `/etc/php/7.3/<sapi>/conf.d`. That directory is separate from
  `/usr/local/etc/php/conf.d`, so mounting your own `conf.d` keeps them loaded.
  The image sets `PHPRC` and `PHP_INI_SCAN_DIR` to point PHP at
  `/usr/local/etc/php`; do not override them.
- PHP binaries live in `/usr/bin` and `/usr/lib/php`, not `/usr/local`.
  There is no `docker-php-source`.
- `pcntl` is available in the CLI only (as in Debian's PHP packages).
- `PHP_VERSION` is the major.minor version (`7.3`); `php -v` prints the full
  package version, e.g. `7.3.33-35+0~20261021...`.

## Building another PHP version

```sh
docker build --build-arg PHP_VERSION=8.1 -t php:8.1-apache .
```

Any version available on deb.sury.org for the Debian release works; to publish it,
add it to the `matrix.php` list in `.github/workflows/build.yml`.

## Testing

```sh
tests/run.sh php:7.3-apache
```

Builds a typical downstream Dockerfile (gd/intl/zip/opcache/mysqli/pdo_mysql/soap
and the ionCube loader) on top of the image, then checks the CLI, Apache, the
helper scripts and PHP package reinstalls. CI runs it on both platforms before
anything is pushed; only the `master` branch publishes.

## Docker Hub setup

Repository secrets `DOCKER_USERNAME` and `DOCKER_PASSWORD` (an access token with
Read & Write scope).

## License

`apache2-foreground`, `docker-php-entrypoint`, `docker-php-ext-enable` and the
Apache setup in the `Dockerfile` come from
[docker-library/php](https://github.com/docker-library/php), see
`LICENSE.docker-library`.
