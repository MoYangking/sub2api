#!/usr/bin/env bash
set -euo pipefail

LOG_NAME=prepare-runtime
. /home/user/scripts/common-env.sh

MARKER="${HOME}/.runtime-prepared"
LOCK_DIR="${HOME}/.runtime-prepare.lock"

if [ -f "${MARKER}" ]; then
  exit 0
fi

while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
  if [ -f "${MARKER}" ]; then
    exit 0
  fi
  sleep 1
done
trap 'rmdir "${LOCK_DIR}" 2>/dev/null || true' EXIT

if [ -f "${MARKER}" ]; then
  exit 0
fi

require_github_env
/home/user/scripts/wait-for-sync.sh

mkdir -p "${BACKUP_DIR}" "${SECRETS_DIR}" "${SUB2API_DATA_DIR}" \
  "${PGADMIN_DATA_DIR}" "${FILEBROWSER_DATA_DIR}" "${REDIS_DATA_DIR}" "${HOME}/logs"

should_restore_state=false
case "${RESTORE_SUB2API_ON_START}" in
  always) should_restore_state=true ;;
  missing)
    if [ ! -f "${RUNTIME_ENV_FILE}" ] && [ ! -f "${SUB2API_DATA_DIR}/config.yaml" ]; then
      should_restore_state=true
    fi
    ;;
  never) should_restore_state=false ;;
  *) fail "RESTORE_SUB2API_ON_START must be always, missing, or never" ;;
esac

if [ "${should_restore_state}" = true ] && [ -s "${BACKUP_DIR}/latest.state.tar.gz" ]; then
  stamp="$(date '+%Y%m%d_%H%M%S')"
  emergency_dir="${BACKUP_DIR}/emergency"
  mkdir -p "${emergency_dir}"
  if [ -e "${RUNTIME_ENV_FILE}" ] || [ -e "${SUB2API_DATA_DIR}/config.yaml" ] || \
     [ -e "${FILEBROWSER_DATA_DIR}/filebrowser.db" ] || [ -e "${PGADMIN_DATA_DIR}/pgadmin4.db" ]; then
    log "creating emergency state snapshot before restore"
    tar -czf "${emergency_dir}/pre_restore_${stamp}.state.tar.gz" \
      --ignore-failed-read \
      -C / \
      home/user/secrets \
      data/sub2api \
      home/user/filebrowser-data \
      home/user/pgadmin-data 2>/dev/null || true
  fi
  log "restoring state from ${BACKUP_DIR}/latest.state.tar.gz"
  tar -xzf "${BACKUP_DIR}/latest.state.tar.gz" -C /
else
  log "state restore skipped"
fi

mkdir -p "${SECRETS_DIR}" "${SUB2API_DATA_DIR}" "${PGADMIN_DATA_DIR}" \
  "${FILEBROWSER_DATA_DIR}" "${REDIS_DATA_DIR}" "${HOME}/logs"

touch "${RUNTIME_ENV_FILE}"
chmod 600 "${RUNTIME_ENV_FILE}"

load_runtime_env

POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(rand_hex 24)}"
REDIS_PASSWORD="${REDIS_PASSWORD:-$(rand_hex 24)}"
JWT_SECRET="${JWT_SECRET:-$(rand_hex 32)}"
TOTP_ENCRYPTION_KEY="${TOTP_ENCRYPTION_KEY:-$(rand_hex 32)}"

tmp="${RUNTIME_ENV_FILE}.tmp"
{
  printf 'POSTGRES_USER=%s\n' "$(shell_quote "${POSTGRES_USER}")"
  printf 'POSTGRES_DB=%s\n' "$(shell_quote "${POSTGRES_DB}")"
  printf 'POSTGRES_PASSWORD=%s\n' "$(shell_quote "${POSTGRES_PASSWORD}")"
  printf 'REDIS_PASSWORD=%s\n' "$(shell_quote "${REDIS_PASSWORD}")"
  printf 'JWT_SECRET=%s\n' "$(shell_quote "${JWT_SECRET}")"
  printf 'TOTP_ENCRYPTION_KEY=%s\n' "$(shell_quote "${TOTP_ENCRYPTION_KEY}")"
} > "${tmp}"
mv -f "${tmp}" "${RUNTIME_ENV_FILE}"
chmod 600 "${RUNTIME_ENV_FILE}"

load_runtime_env
validate_name POSTGRES_USER "${POSTGRES_USER}"
validate_name POSTGRES_DB "${POSTGRES_DB}"
require_admin_env

chown -R 1000:1000 "${HOME}/logs" "${BACKUP_DIR}" "${SECRETS_DIR}" \
  "${SUB2API_DATA_DIR}" "${PGADMIN_DATA_DIR}" "${FILEBROWSER_DATA_DIR}" 2>/dev/null || true

date '+%s' > "${MARKER}"
log "runtime prepared"
