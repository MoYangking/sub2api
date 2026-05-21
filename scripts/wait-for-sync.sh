#!/usr/bin/env bash
set -euo pipefail

if [ -z "${GITHUB_REPO:-}" ] || [ -z "${GITHUB_PAT:-}" ]; then
  echo "[wait-for-sync] GitHub sync is not configured; continuing."
  exit 0
fi

SYNC_COMPLETE="${HIST_DIR:-/home/user/.sync-backup}/.sync-complete"
SYNC_PROGRESS="${HIST_DIR:-/home/user/.sync-backup}/.sync-progress.json"
MAX_WAIT="${SYNC_WAIT_TIMEOUT:-1800}"
ELAPSED=0
CHECK_INTERVAL=5

if [ "${MAX_WAIT}" = "0" ]; then
  echo "[wait-for-sync] SYNC_WAIT_TIMEOUT=0; continuing."
  exit 0
fi

echo "[wait-for-sync] Waiting for sync to complete..."
echo "[wait-for-sync] Timeout: ${MAX_WAIT} seconds"

while [ "${ELAPSED}" -lt "${MAX_WAIT}" ]; do
  if [ -f "${SYNC_COMPLETE}" ]; then
    FILE_AGE="$(($(date +%s) - $(stat -c %Y "${SYNC_COMPLETE}" 2>/dev/null || echo 0)))"
    if [ "${FILE_AGE}" -lt 600 ]; then
      echo "[wait-for-sync] Sync completed. Starting service..."
      exit 0
    fi
    echo "[wait-for-sync] Sync marker is old (${FILE_AGE}s); waiting for fresh sync..."
  fi

  if [ -f "${SYNC_PROGRESS}" ]; then
    STAGE="$(jq -r '.stage // ""' "${SYNC_PROGRESS}" 2>/dev/null || true)"
    PROGRESS="$(jq -r '.progress // ""' "${SYNC_PROGRESS}" 2>/dev/null || true)"
    CURRENT="$(jq -r '.current // ""' "${SYNC_PROGRESS}" 2>/dev/null || true)"
    TOTAL="$(jq -r '.total // ""' "${SYNC_PROGRESS}" 2>/dev/null || true)"
    if [ -n "${PROGRESS}" ] && [ "${PROGRESS}" != "null" ]; then
      if [ -n "${CURRENT}" ] && [ "${CURRENT}" != "null" ] && [ -n "${TOTAL}" ] && [ "${TOTAL}" != "null" ] && [ "${TOTAL}" -gt 0 ] 2>/dev/null; then
        echo "[wait-for-sync] Progress: ${PROGRESS}% (stage: ${STAGE}, ${CURRENT}/${TOTAL} files)"
      else
        echo "[wait-for-sync] Progress: ${PROGRESS}% (stage: ${STAGE})"
      fi
    else
      echo "[wait-for-sync] Waiting... (${ELAPSED}s elapsed)"
    fi
  else
    echo "[wait-for-sync] Waiting for sync to start... (${ELAPSED}s elapsed)"
  fi

  sleep "${CHECK_INTERVAL}"
  ELAPSED="$((ELAPSED + CHECK_INTERVAL))"
done

echo "[wait-for-sync] Timeout after ${MAX_WAIT} seconds; starting service anyway."
exit 0
