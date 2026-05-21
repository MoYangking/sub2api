#!/usr/bin/env bash
set -euo pipefail

LOG_NAME=backup
. /home/user/scripts/common-env.sh

wait_runtime_prepared

BACKUP_INTERVAL="${BACKUP_INTERVAL:-3600}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"

backup_once() {
  wait_file "${HOME}/.sub2api-postgres-restore-complete" "PostgreSQL restore" 300
  wait_tcp "${POSTGRES_HOST}" "${POSTGRES_PORT}" PostgreSQL 120
  wait_tcp "${REDIS_HOST}" "${REDIS_PORT}" Redis 120

  mkdir -p "${BACKUP_DIR}"
  stamp="$(date '+%Y%m%d_%H%M%S')"
  pg_tmp="${BACKUP_DIR}/sub2api_${stamp}.pg.dump.tmp"
  pg_out="${BACKUP_DIR}/sub2api_${stamp}.pg.dump"
  redis_tmp="${BACKUP_DIR}/sub2api_${stamp}.redis.rdb.tmp"
  redis_out="${BACKUP_DIR}/sub2api_${stamp}.redis.rdb"
  state_tmp="${BACKUP_DIR}/sub2api_${stamp}.state.tar.gz.tmp"
  state_out="${BACKUP_DIR}/sub2api_${stamp}.state.tar.gz"
  manifest_tmp="${BACKUP_DIR}/sub2api_${stamp}.json.tmp"
  manifest_out="${BACKUP_DIR}/sub2api_${stamp}.json"

  log "creating PostgreSQL snapshot"
  PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
    -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    -Fc -Z 9 --no-owner --no-privileges -f "${pg_tmp}"
  mv -f "${pg_tmp}" "${pg_out}"

  log "creating Redis snapshot"
  REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" --rdb "${redis_tmp}" >/dev/null
  mv -f "${redis_tmp}" "${redis_out}"

  log "creating state snapshot"
  state_stage="$(mktemp -d)"
  trap 'rm -rf "${state_stage}"' RETURN
  mkdir -p \
    "${state_stage}/home/user/secrets" \
    "${state_stage}/data/sub2api" \
    "${state_stage}/home/user/filebrowser-data" \
    "${state_stage}/home/user/pgadmin-data"

  rsync -a "${SECRETS_DIR}/" "${state_stage}/home/user/secrets/" 2>/dev/null || true
  rsync -a "${SUB2API_DATA_DIR}/" "${state_stage}/data/sub2api/" 2>/dev/null || true
  rsync -a --exclude 'filebrowser.db*' "${FILEBROWSER_DATA_DIR}/" "${state_stage}/home/user/filebrowser-data/" 2>/dev/null || true
  rsync -a --exclude 'pgadmin4.db*' "${PGADMIN_DATA_DIR}/" "${state_stage}/home/user/pgadmin-data/" 2>/dev/null || true

  if [ -s "${FILEBROWSER_DATA_DIR}/filebrowser.db" ]; then
    sqlite3 "${FILEBROWSER_DATA_DIR}/filebrowser.db" ".backup '${state_stage}/home/user/filebrowser-data/filebrowser.db'"
  fi
  if [ -s "${PGADMIN_DATA_DIR}/pgadmin4.db" ]; then
    sqlite3 "${PGADMIN_DATA_DIR}/pgadmin4.db" ".backup '${state_stage}/home/user/pgadmin-data/pgadmin4.db'"
  fi

  tar -czf "${state_tmp}" -C "${state_stage}" home data
  rm -rf "${state_stage}"
  trap - RETURN
  mv -f "${state_tmp}" "${state_out}"

  jq -n \
    --arg created_at "$(date -Iseconds)" \
    --arg postgres "$(basename "${pg_out}")" \
    --arg redis "$(basename "${redis_out}")" \
    --arg state "$(basename "${state_out}")" \
    '{created_at:$created_at, postgres:$postgres, redis:$redis, state:$state}' > "${manifest_tmp}"
  mv -f "${manifest_tmp}" "${manifest_out}"

  cp -f "${pg_out}" "${BACKUP_DIR}/latest.pg.dump"
  cp -f "${redis_out}" "${BACKUP_DIR}/latest.redis.rdb"
  cp -f "${state_out}" "${BACKUP_DIR}/latest.state.tar.gz"
  cp -f "${manifest_out}" "${BACKUP_DIR}/latest.json"

  if [ "${BACKUP_RETENTION_DAYS}" -gt 0 ] 2>/dev/null; then
    find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'sub2api_*.pg.dump' -mtime +"${BACKUP_RETENTION_DAYS}" -delete
    find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'sub2api_*.redis.rdb' -mtime +"${BACKUP_RETENTION_DAYS}" -delete
    find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'sub2api_*.state.tar.gz' -mtime +"${BACKUP_RETENTION_DAYS}" -delete
    find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'sub2api_*.json' -mtime +"${BACKUP_RETENTION_DAYS}" -delete
  fi

  log "backup completed: ${manifest_out}"
}

if [ "${BACKUP_INTERVAL}" = "0" ]; then
  backup_once
  exit 0
fi

while true; do
  backup_once || true
  sleep "${BACKUP_INTERVAL}"
done
