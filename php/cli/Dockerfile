FROM quay.io/centos/centos:stream9

ARG PHP_VERSION
# Core PHP extensions
ARG PHP_EXTENSIONS="bcmath cli common gd gmp intl json mbstring \
    mcrypt sodium mysqlnd pgsql opcache pdo pdo_pgsql process soap xml xmlrpc"
# PHP < 8.1 language extensions to install
ARG PECL_EXTENSIONS="pecl-msgpack pecl-amqp pecl-redis pecl-imagick pecl-zip pecl-swoole"
# PHP >= 8.1 language extensions to install
ARG PIE_EXTENSIONS="msgpack/msgpack-php php-amqp/php-amqp phpredis/phpredis imagick/imagick pecl/zip swoole/swoole"
ARG COMPOSER_VERSION=2

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
        dnf install -y ${PHP_EXTENSIONS}; \
    # For PHP >= 8.1 use the new PIE extension installer
    else \
        DNFVERS=$(dnf --version | head -n1 | awk -F '.' '{print $1}') \
        && if [[ ${DNFVERS} = '5' ]]; then \
            dnf install dnf5-plugins && dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo; \
        else \
            dnf install 'dnf-command(config-manager)' && dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo; \
        fi; \
        dnf install gh --repo gh-cli \
        && curl -fL --output pie.phar https://github.com/php/pie/releases/latest/download/pie.phar \
        && gh attestation verify --owner php pie.phar \
        && chmod +x pie.phar && mv pie.phar /usr/local/bin/pie \
        && PIE_PACKAGES= && for PKG in ${PIE_EXTENSIONS}; do \
            # Swoole isn't supported on PHP 8.5
            if [[ ${PKG} = "swoole/swoole" ]] && (( ${PHP_VERSION} = 85 )); then continue; fi; \
            PIE_PACKAGES+="${PKG} "; \
        done \
        && pie install ${PIE_PACKAGES} \
        && dnf remove gh; \
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
