FROM composer:2 AS vendor

WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --prefer-dist --no-interaction --no-progress --optimize-autoloader --no-scripts

FROM php:8.2-apache

RUN apt-get update \
    && apt-get install -y --no-install-recommends libzip-dev \
    && docker-php-ext-install bcmath pdo_mysql zip \
    && a2enmod rewrite headers \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html
COPY --from=vendor /app/vendor ./vendor
COPY . .
COPY --from=infra backend/docker/apache.conf /etc/apache2/sites-enabled/000-default.conf
RUN chown -R www-data:www-data storage bootstrap/cache

EXPOSE 80
