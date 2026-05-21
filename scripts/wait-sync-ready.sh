#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-/}"
HIST_DIR="${HIST_DIR:-/home/user/.sync-backup}"
BRANCH="${GIT_BRANCH:-main}"

DEFAULT_TARGETS=(
  home/user/backups/sub2api/
)

TARGETS=()

log() {
  printf '[%s] [wait-sync] %s\n' "$(date '+%F %T')" "$*"
}

abs_path() {
  local rel="$1"
  if [[ "${rel}" = /* ]]; then printf '%s' "${rel}"; return; fi
  if [[ "${BASE}" = "/" ]]; then printf '/%s' "${rel}"; else printf '%s/%s' "${BASE}" "${rel}"; fi
}

load_targets() {
  local cfg="${HIST_DIR}/sync-config.json"
  if [[ -f "${cfg}" ]] && command -v jq >/dev/null 2>&1; then
    mapfile -t TARGETS < <(jq -r 'try .targets[] // empty' "${cfg}" 2>/dev/null | sed 's#^/##') || true
  fi
  if (( ${#TARGETS[@]} == 0 )); then
    TARGETS=("${DEFAULT_TARGETS[@]}")
  fi
}

targets_symlinked() {
  local ok=0
  for rel in "${TARGETS[@]}"; do
    local rel_clean="${rel%/}"
    local p
    p="$(abs_path "${rel_clean}")"
    if [[ ! -L "${p}" ]]; then
      ok=1
    fi
  done
  return "${ok}"
}

head_equals_remote() {
  git -C "${HIST_DIR}" rev-parse --git-dir >/dev/null 2>&1 || return 1
  git -C "${HIST_DIR}" rev-parse "origin/${BRANCH}" >/dev/null 2>&1 || return 1
  local h1 h2
  h1="$(git -C "${HIST_DIR}" rev-parse HEAD 2>/dev/null || echo "")"
  h2="$(git -C "${HIST_DIR}" rev-parse "origin/${BRANCH}" 2>/dev/null || echo "")"
  [[ -n "${h1}" && "${h1}" = "${h2}" ]]
}

if [ -z "${GITHUB_REPO:-}" ] || [ -z "${GITHUB_PAT:-}" ]; then
  log "GitHub sync is not configured; continuing."
  exit 0
fi

load_targets

log "Waiting for Git sync: HIST_DIR=${HIST_DIR} BRANCH=${BRANCH} targets=${#TARGETS[@]}"
until head_equals_remote; do
  sleep 1
done
log "Git HEAD is aligned with origin/${BRANCH}"

for i in {1..1000}; do
  if targets_symlinked; then
    log "Targets are symlinked."
    exit 0
  fi
  log "Target symlinks not ready yet (${i}/1000)."
  sleep 1
done

log "Target symlinks are not all ready; continuing."
exit 0
