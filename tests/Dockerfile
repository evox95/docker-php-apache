# Builds a typical downstream Dockerfile (PrestaShop extensions, ioncube) on
# top of the image to prove it works as a drop-in for php:<version>-apache.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG TARGETARCH

RUN set -eux; \
    apt-get update; \
    ICU="$(apt-cache search --names-only '^libicu[0-9]+$' | awk '{print $1}' | sort -V | tail -1)"; \
    ZIP="$(apt-cache search --names-only '^libzip[0-9]+$'  | awk '{print $1}' | sort -V | tail -1)"; \
    WEBP="$(apt-cache search --names-only '^libwebp[0-9]+$' | awk '{print $1}' | sort -V | tail -1)"; \
    apt-get install -y --no-install-recommends \
        libfreetype6 libjpeg62-turbo libpng16-16 libwebpmux3 libwebpdemux2 \
        $ICU $ZIP $WEBP default-mysql-client; \
    apt-get install -y --no-install-recommends \
        libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
        libicu-dev libzip-dev libxml2-dev libcurl4-openssl-dev; \
    PHP_MM="$(php-config --version | cut -d. -f1,2)"; \
    case "$PHP_MM" in \
      7.2|7.3) docker-php-ext-configure gd --with-freetype-dir=/usr --with-jpeg-dir=/usr --with-webp-dir=/usr ;; \
      *)       docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp ;; \
    esac; \
    docker-php-ext-install -j"$(nproc)" gd intl zip opcache mysqli pdo_mysql soap; \
    apt-get purge -y --auto-remove \
        libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
        libicu-dev libzip-dev libxml2-dev libcurl4-openssl-dev; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    PHP_V="$(php-config --version | cut -d. -f1,2)"; \
    case "$TARGETARCH" in \
      amd64) IONCUBE_URL="https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz" ;; \
      arm64) IONCUBE_URL="https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_aarch64.tar.gz" ;; \
      *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "$IONCUBE_URL" | tar -xz -C /usr/local; \
    LOADER="/usr/local/ioncube/ioncube_loader_lin_${PHP_V}.so"; \
    test -f "$LOADER" || { echo "no ioncube loader for PHP ${PHP_V}" >&2; exit 1; }; \
    echo "zend_extension=${LOADER}" > /usr/local/etc/php/conf.d/00-ioncube.ini

RUN a2enmod rewrite headers expires remoteip

RUN printf 'memory_limit = 333M\n' > /usr/local/etc/php/conf.d/zz-test.ini \
    && printf '<?php\nheader("Content-Type: text/plain");\necho PHP_VERSION, "\\n", ini_get("memory_limit"), "\\n", implode(",", get_loaded_extensions()), "\\n", extension_loaded("ionCube Loader") ? "ioncube" : "no-ioncube", "\\n";\n' > index.php \
    && printf '<?php echo "exec" . "uted";\n' > test.phtml
