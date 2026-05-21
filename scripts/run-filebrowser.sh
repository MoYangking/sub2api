#!/usr/bin/env bash
set -euo pipefail

LOG_NAME=filebrowser
. /home/user/scripts/common-env.sh

wait_runtime_prepared

db="${FILEBROWSER_DATA_DIR}/filebrowser.db"
mkdir -p "${FILEBROWSER_DATA_DIR}"

/home/user/filebrowser --database "${db}" config init >/dev/null 2>&1 || true
/home/user/filebrowser --database "${db}" config set \
  --address 0.0.0.0 \
  --port 8888 \
  --baseURL /filebrowser \
  --root / >/dev/null

if ! /home/user/filebrowser --database "${db}" users add "${ADMIN_EMAIL}" "${ADMIN_PASSWORD}" \
  --scope / \
  --perm.admin >/dev/null 2>&1; then
  /home/user/filebrowser --database "${db}" users update "${ADMIN_EMAIL}" \
    --password "${ADMIN_PASSWORD}" \
    --scope / \
    --perm.admin >/dev/null
fi

exec /home/user/filebrowser \
  --address 0.0.0.0 \
  --port 8888 \
  --root / \
  --baseURL /filebrowser \
  --database "${db}"
