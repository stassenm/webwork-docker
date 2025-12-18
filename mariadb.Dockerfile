ARG DB_VERSION=10.11
FROM mariadb:${DB_VERSION} AS db

COPY config/db /etc/mysql/
COPY config/security /etc/security/

VOLUME /var/lib/mysql
