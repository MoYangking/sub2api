#!/usr/bin/env bash
set -euo pipefail

LOG_NAME=postgres
. /home/user/scripts/common-env.sh

wait_runtime_prepared

PG_MAJOR="$(ls /usr/lib/postgresql | sort -V | tail -n 1)"
PG_BIN="/usr/lib/postgresql/${PG_MAJOR}/bin"
PG_RUN_DIR="/var/run/postgresql"

mkdir -p "${PGDATA}" "${PG_RUN_DIR}" "${HOME}/logs/postgres"
chown -R postgres:postgres "${PGDATA}" "${PG_RUN_DIR}" "${HOME}/logs/postgres"
chmod 2775 "${PG_RUN_DIR}"

if [ ! -s "${PGDATA}/PG_VERSION" ]; then
  log "initializing PostgreSQL data directory"
  runuser -u postgres -- "${PG_BIN}/initdb" -D "${PGDATA}" --encoding=UTF8 --locale=C.UTF-8
fi

cat > "${PGDATA}/postgresql.auto.conf" <<EOF
listen_addresses = '127.0.0.1'
port = ${POSTGRES_PORT}
unix_socket_directories = '${PG_RUN_DIR}'
password_encryption = 'scram-sha-256'
max_connections = ${POSTGRES_MAX_CONNECTIONS:-200}
shared_buffers = '${POSTGRES_SHARED_BUFFERS:-256MB}'
EOF

cat > "${PGDATA}/pg_hba.conf" <<EOF
local   all             all                                     trust
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
EOF

chown postgres:postgres "${PGDATA}/postgresql.auto.conf" "${PGDATA}/pg_hba.conf"

log "starting PostgreSQL ${PG_MAJOR}"
exec runuser -u postgres -- "${PG_BIN}/postgres" -D "${PGDATA}"
