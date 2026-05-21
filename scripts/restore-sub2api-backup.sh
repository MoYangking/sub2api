#!/usr/bin/env bash
set -euo pipefail

LOG_NAME=restore
. /home/user/scripts/common-env.sh

wait_runtime_prepared

MARKER="${HOME}/.sub2api-postgres-restore-complete"
LOCK_DIR="${HOME}/.sub2api-postgres-restore.lock"

if [ -f "${MARKER}" ]; then
  exit 0
fi

while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
  [ -f "${MARKER}" ] && exit 0
  sleep 1
done
trap 'rmdir "${LOCK_DIR}" 2>/dev/null || true' EXIT

wait_tcp "${POSTGRES_HOST}" "${POSTGRES_PORT}" PostgreSQL 180

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

psql_super() {
  runuser -u postgres -- psql -v ON_ERROR_STOP=1 --dbname=postgres -q -c "$1"
}

role_pw="$(sql_escape "${POSTGRES_PASSWORD}")"
psql_super "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${POSTGRES_USER}') THEN CREATE ROLE ${POSTGRES_USER} LOGIN PASSWORD '${role_pw}'; ELSE ALTER ROLE ${POSTGRES_USER} WITH LOGIN PASSWORD '${role_pw}'; END IF; END \$\$;"

db_exists() {
  runuser -u postgres -- psql --dbname=postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB}'" | grep -q 1
}

db_has_data() {
  if ! db_exists; then
    return 1
  fi
  PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public')" \
    2>/dev/null | grep -q t
}

ensure_database() {
  if ! db_exists; then
    runuser -u postgres -- createdb -O "${POSTGRES_USER}" "${POSTGRES_DB}"
  fi
}

should_restore_pg=false
case "${RESTORE_SUB2API_ON_START}" in
  always) should_restore_pg=true ;;
  missing)
    if ! db_has_data; then
      should_restore_pg=true
    fi
    ;;
  never) should_restore_pg=false ;;
  *) fail "RESTORE_SUB2API_ON_START must be always, missing, or never" ;;
esac

if [ "${should_restore_pg}" = true ] && [ -s "${BACKUP_DIR}/latest.pg.dump" ]; then
  stamp="$(date '+%Y%m%d_%H%M%S')"
  mkdir -p "${BACKUP_DIR}/emergency"
  if db_has_data; then
    log "creating emergency PostgreSQL snapshot before restore"
    PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
      -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
      -Fc -Z 9 --no-owner --no-privileges \
      -f "${BACKUP_DIR}/emergency/pre_restore_${stamp}.pg.dump" || true
  fi

  log "restoring PostgreSQL from ${BACKUP_DIR}/latest.pg.dump"
  runuser -u postgres -- dropdb --if-exists --force "${POSTGRES_DB}"
  runuser -u postgres -- createdb -O "${POSTGRES_USER}" "${POSTGRES_DB}"
  PGPASSWORD="${POSTGRES_PASSWORD}" pg_restore \
    -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    --no-owner --role="${POSTGRES_USER}" "${BACKUP_DIR}/latest.pg.dump"
else
  ensure_database
  log "PostgreSQL restore skipped"
fi

/home/user/scripts/sync-sub2api-admin.sh

date '+%s' > "${MARKER}"
log "PostgreSQL restore phase complete"
