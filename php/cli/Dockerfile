FROM quay.io/centos/centos:stream9

ARG PHP_VERSION
# Core PHP extensions
## !!!!!!!!
## msgpack and amqp haven't released a PIE-compatible stable version yet, once it does we can use
## PIE to install msgpack/msgpack-php and php-amqp/php-amqp and move the pecl-msgpack to the PECL_EXTENSIONS var
## !!!!!!!!
ARG PHP_EXTENSIONS="bcmath cli common gd gmp intl json mbstring \
    mcrypt sodium mysqlnd pgsql opcache pdo pdo_pgsql process soap xml xmlrpc pecl-amqp pecl-msgpack"
# PHP < 8.1 language extensions to install
ARG PECL_EXTENSIONS="pecl-redis pecl-imagick pecl-zip pecl-swoole"
# PHP >= 8.1 language extensions to install
ARG PIE_EXTENSIONS="phpredis/phpredis imagick/imagick pecl/zip swoole/swoole"
ARG COMPOSER_VERSION=2
ARG GH_TOKEN

RUN dnf update -y \
    && dnf clean all \
    && rm -rf /var/cache/dnf

RUN set -eux \
    && dnf install -y epel-release \
    && dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm \
    && dnf module reset php -y \
    && dnf module install -y php:remi-${PHP_VERSION} \
    && PHP_VERSION=$(echo ${PHP_VERSION} | awk -F '.' '{print $1$2}') \
    && PHP_PACKAGES= && for PKG in ${PHP_EXTENSIONS}; do \
        if [[ ${PKG} = "mcrypt" ]] && (( ${PHP_VERSION} > 71 )); then continue; fi; \
        if [[ ${PKG} = "sodium" ]] && (( ${PHP_VERSION} < 72 )); then continue; fi; \
        if [[ ${PKG} = "xmlrpc" ]] && (( ${PHP_VERSION} > 83 )); then continue; fi; \
        PHP_PACKAGES+="php-${PKG} "; \
    done \
    && dnf install -y ${PHP_PACKAGES} git perl which npm patch gettext unzip bzip2 pwgen procps nmap-ncat jq \
    # For PHP < 8.1 use the deprecated PECL extension
    && if [[ ${PHP_VERSION} < 81 ]]; then \
        PECL_PACKAGES= && for PKG in ${PECL_EXTENSIONS}; do \
            PECL_PACKAGES+="php-${PKG} "; \
        done \
        && dnf install -y ${PECL_PACKAGES}; \
    # For PHP >= 8.1 use the new PIE extension installer
    else \
        DNFVERS=$(dnf --version | head -n1 | awk -F '.' '{print $1}') \
        && if [[ ${DNFVERS} = '5' ]]; then \
            dnf install -y dnf5-plugins && dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo; \
        else \
            dnf install -y 'dnf-command(config-manager)' && dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo; \
        fi; \
        dnf install -y gh --repo gh-cli \
        && dnf install -y autoconf automake libtool m4 make gcc php-devel \
        && curl -fL --output pie.phar https://github.com/php/pie/releases/latest/download/pie.phar \
        && gh attestation verify --owner php pie.phar \
        && dnf remove -y gh \
        && chmod +x pie.phar && mv pie.phar /usr/local/bin/pie \
        && PIE_PACKAGES= && for PKG in ${PIE_EXTENSIONS}; do \
            # Swoole isn't supported on PHP 8.5
            if [[ ${PKG} = "swoole/swoole" ]] && (( ${PHP_VERSION} == 85 )); then continue; fi; \
            PIE_PACKAGES+="${PKG} "; \
        done \
        && pie install ${PIE_PACKAGES}; \
    fi; \
    dnf clean all \
    && rm -rf /var/cache/dnf

RUN set -eux \
    && cp /etc/php.ini /etc/php-cli.ini \
    && perl -pi -e 's/memory_limit(.*)/memory_limit=-1/g' /etc/php-cli.ini

ENV COMPOSER_ALLOW_SUPERUSER=1
ENV COMPOSER_HOME=/tmp/composer
COPY --from=composer:1 /usr/bin/composer /usr/bin/composer1
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer2
COPY --from=composer:2.2 /usr/bin/composer /usr/bin/composer2lts
