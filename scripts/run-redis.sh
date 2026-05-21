#!/usr/bin/env bash
set -euo pipefail

LOG_NAME=redis
. /home/user/scripts/common-env.sh

wait_runtime_prepared

mkdir -p "${REDIS_DATA_DIR}"

MARKER="${HOME}/.sub2api-redis-restore-complete"
LOCK_DIR="${HOME}/.sub2api-redis-restore.lock"

if [ ! -f "${MARKER}" ]; then
  while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
    [ -f "${MARKER}" ] && break
    sleep 1
  done
  trap 'rmdir "${LOCK_DIR}" 2>/dev/null || true' EXIT
fi

should_restore_redis=false
if [ ! -f "${MARKER}" ]; then
  case "${RESTORE_SUB2API_ON_START}" in
    always) should_restore_redis=true ;;
    missing)
      if [ ! -s "${REDIS_DATA_DIR}/dump.rdb" ] && [ ! -d "${REDIS_DATA_DIR}/appendonlydir" ]; then
        should_restore_redis=true
      fi
      ;;
    never) should_restore_redis=false ;;
    *) fail "RESTORE_SUB2API_ON_START must be always, missing, or never" ;;
  esac
fi

if [ "${should_restore_redis}" = true ] && [ -s "${BACKUP_DIR}/latest.redis.rdb" ]; then
  stamp="$(date '+%Y%m%d_%H%M%S')"
  mkdir -p "${BACKUP_DIR}/emergency"
  if [ -s "${REDIS_DATA_DIR}/dump.rdb" ]; then
    cp -f "${REDIS_DATA_DIR}/dump.rdb" "${BACKUP_DIR}/emergency/pre_restore_${stamp}.redis.rdb"
  fi
  log "restoring Redis RDB from ${BACKUP_DIR}/latest.redis.rdb"
  rm -rf "${REDIS_DATA_DIR}/appendonlydir" "${REDIS_DATA_DIR}"/appendonly.aof*
  cp -f "${BACKUP_DIR}/latest.redis.rdb" "${REDIS_DATA_DIR}/dump.rdb"
fi

date '+%s' > "${MARKER}"

exec redis-server \
  --bind "${REDIS_HOST}" \
  --port "${REDIS_PORT}" \
  --dir "${REDIS_DATA_DIR}" \
  --dbfilename dump.rdb \
  --save 60 1 \
  --appendonly yes \
  --appendfsync everysec \
  --requirepass "${REDIS_PASSWORD}"
