#!/usr/bin/env bash
set -euo pipefail

LOG_NAME=pgadmin
. /home/user/scripts/common-env.sh

/home/user/scripts/prepare-runtime.sh
. /home/user/scripts/common-env.sh
wait_file "${HOME}/.sub2api-postgres-restore-complete" "PostgreSQL restore" 300

mkdir -p "${PGADMIN_DATA_DIR}" "${PGADMIN_DATA_DIR}/storage" "${PGADMIN_DATA_DIR}/sessions" "${HOME}/logs/pgadmin"

export PGADMIN_SETUP_EMAIL="${ADMIN_EMAIL}"
export PGADMIN_SETUP_PASSWORD="${ADMIN_PASSWORD}"
export PGADMIN_DATA_DIR
export SCRIPT_NAME=/pgadmin4
export PGADMIN_CONFIG_SERVER_MODE=True
export PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False

cd /usr/pgadmin4/web

if [ ! -s "${PGADMIN_DATA_DIR}/pgadmin4.db" ]; then
  log "initializing pgAdmin database"
  /usr/pgadmin4/venv/bin/python3 setup.py setup-db
fi

if ! /usr/pgadmin4/venv/bin/python3 setup.py update-user "${ADMIN_EMAIL}" --password "${ADMIN_PASSWORD}" --admin >/dev/null 2>&1; then
  /usr/pgadmin4/venv/bin/python3 setup.py add-user "${ADMIN_EMAIL}" "${ADMIN_PASSWORD}" --admin >/dev/null 2>&1 || true
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
/usr/pgadmin4/venv/bin/python3 setup.py load-servers "${servers_json}" --user "${ADMIN_EMAIL}" --replace >/dev/null 2>&1 || true

log "starting pgAdmin"
exec /usr/pgadmin4/venv/bin/gunicorn \
  --chdir /usr/pgadmin4/web \
  --bind 127.0.0.1:5050 \
  --workers 1 \
  --threads "${PGADMIN_THREADS:-25}" \
  --timeout "${PGADMIN_TIMEOUT:-120}" \
  --access-logfile - \
  run_pgadmin:app
