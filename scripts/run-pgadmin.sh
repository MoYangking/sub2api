#!/usr/bin/env bash
set -euo pipefail

LOG_NAME=pgadmin
. /home/user/scripts/common-env.sh

wait_runtime_prepared
wait_file "${HOME}/.sub2api-postgres-restore-complete" "PostgreSQL restore" 300

mkdir -p "${PGADMIN_DATA_DIR}" "${PGADMIN_DATA_DIR}/storage" "${PGADMIN_DATA_DIR}/sessions" "${HOME}/logs/pgadmin"

PGADMIN_PYTHON="${PGADMIN_PYTHON:-/usr/pgadmin4/venv/bin/python3}"
PGADMIN_DB="${PGADMIN_DATA_DIR}/pgadmin4.db"

export PGADMIN_SETUP_EMAIL="${ADMIN_EMAIL}"
export PGADMIN_SETUP_PASSWORD="${ADMIN_PASSWORD}"
export PGADMIN_DATA_DIR
export SCRIPT_NAME=/pgadmin4
export PGADMIN_CONFIG_SERVER_MODE=True
export PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False

cd /usr/pgadmin4/web

if [ -s "${PGADMIN_DB}" ] && ! sqlite3 "${PGADMIN_DB}" 'PRAGMA quick_check;' >/dev/null 2>&1; then
  stamp="$(date '+%Y%m%d_%H%M%S')"
  log "pgAdmin database is not valid SQLite; moving it aside"
  mv -f "${PGADMIN_DB}" "${PGADMIN_DB}.invalid.${stamp}"
fi

if [ ! -s "${PGADMIN_DB}" ]; then
  log "initializing pgAdmin database"
  "${PGADMIN_PYTHON}" setup.py setup-db
fi

if ! "${PGADMIN_PYTHON}" setup.py update-user "${ADMIN_EMAIL}" --password "${ADMIN_PASSWORD}" --admin >/dev/null 2>&1; then
  "${PGADMIN_PYTHON}" setup.py add-user "${ADMIN_EMAIL}" "${ADMIN_PASSWORD}" --admin >/dev/null 2>&1 || true
fi

servers_json="${PGADMIN_DATA_DIR}/servers.json"
jq -n \
  --arg name "Local sub2api PostgreSQL" \
  --arg host "${POSTGRES_HOST}" \
  --argjson port "${POSTGRES_PORT}" \
  --arg maintenance "postgres" \
  --arg username "${POSTGRES_USER}" \
  --arg password "${POSTGRES_PASSWORD}" \
  '{"Servers":{"1":{"Name":$name,"Group":"Servers","Host":$host,"Port":$port,"MaintenanceDB":$maintenance,"Username":$username,"Password":$password,"SavePassword":true,"SSLMode":"prefer"}}}' \
  > "${servers_json}"
"${PGADMIN_PYTHON}" setup.py load-servers "${servers_json}" --user "${ADMIN_EMAIL}" --replace >/dev/null 2>&1 || true

if ! "${PGADMIN_PYTHON}" -c 'import gunicorn.app.wsgiapp' >/dev/null 2>&1; then
  fail "pgAdmin gunicorn module is not installed in ${PGADMIN_PYTHON}"
fi

log "starting pgAdmin"
exec "${PGADMIN_PYTHON}" -m gunicorn \
  --chdir /usr/pgadmin4/web \
  --bind 127.0.0.1:5050 \
  --workers 1 \
  --threads "${PGADMIN_THREADS:-25}" \
  --timeout "${PGADMIN_TIMEOUT:-120}" \
  --access-logfile - \
  pgAdmin4:app
