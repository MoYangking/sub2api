#!/usr/bin/env bash
set -euo pipefail

LOG_NAME=filebrowser
. /home/user/scripts/common-env.sh

wait_runtime_prepared

db="${FILEBROWSER_DATA_DIR}/filebrowser.db"
mkdir -p "${FILEBROWSER_DATA_DIR}"

configure_filebrowser() {
  /home/user/filebrowser --database "${db}" config init >/dev/null 2>&1 || true
  /home/user/filebrowser --database "${db}" config set \
    --address 0.0.0.0 \
    --port 8888 \
    --baseURL /filebrowser \
    --root / >/dev/null
}

if ! configure_filebrowser; then
  stamp="$(date '+%Y%m%d_%H%M%S')"
  log "FileBrowser database is missing config resources; moving it aside"
  mv -f "${db}" "${db}.invalid.${stamp}" 2>/dev/null || true
  configure_filebrowser
fi

ensure_filebrowser_user() {
  local username="$1"

  if /home/user/filebrowser --database "${db}" users update "${username}" \
    --password "${ADMIN_PASSWORD}" \
    --scope / \
    --perm.admin >/dev/null 2>&1; then
    return 0
  fi

  /home/user/filebrowser --database "${db}" users add "${username}" "${ADMIN_PASSWORD}" \
    --scope / \
    --perm.admin >/dev/null
}

if ! ensure_filebrowser_user "${ADMIN_EMAIL}"; then
  stamp="$(date '+%Y%m%d_%H%M%S')"
  log "FileBrowser user database is not usable; moving it aside"
  mv -f "${db}" "${db}.invalid.${stamp}" 2>/dev/null || true
  configure_filebrowser
  ensure_filebrowser_user "${ADMIN_EMAIL}"
fi

exec /home/user/filebrowser \
  --address 0.0.0.0 \
  --port 8888 \
  --root / \
  --baseURL /filebrowser \
  --database "${db}"
