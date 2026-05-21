#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/home/user}"
export DATA_ROOT="${DATA_ROOT:-/data}"
export SUB2API_DATA_DIR="${SUB2API_DATA_DIR:-/data/sub2api}"
export BACKUP_DIR="${BACKUP_DIR:-/home/user/backups/sub2api}"
export SECRETS_DIR="${SECRETS_DIR:-/home/user/secrets}"
export RUNTIME_ENV_FILE="${RUNTIME_ENV_FILE:-${SECRETS_DIR}/runtime.env}"
export RESTORE_SUB2API_ON_START="${RESTORE_SUB2API_ON_START:-always}"

export POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export POSTGRES_USER="${POSTGRES_USER:-sub2api}"
export POSTGRES_DB="${POSTGRES_DB:-sub2api}"
export PGDATA="${PGDATA:-/data/postgres}"
export REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
export REDIS_PORT="${REDIS_PORT:-6379}"
export REDIS_DB="${REDIS_DB:-0}"
export REDIS_DATA_DIR="${REDIS_DATA_DIR:-/data/redis}"
export PGADMIN_DATA_DIR="${PGADMIN_DATA_DIR:-/home/user/pgadmin-data}"
export FILEBROWSER_DATA_DIR="${FILEBROWSER_DATA_DIR:-/home/user/filebrowser-data}"

log() {
  printf '[%s] [%s] %s\n' "$(date '+%F %T')" "${LOG_NAME:-sub2api-runtime}" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

load_runtime_env() {
  if [ -f "${RUNTIME_ENV_FILE}" ]; then
    set -a
    # shellcheck disable=SC1090
    . "${RUNTIME_ENV_FILE}"
    set +a
  fi
}

validate_name() {
  local label="$1"
  local value="$2"
  if ! printf '%s' "${value}" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'; then
    fail "${label} must match ^[A-Za-z_][A-Za-z0-9_]*$"
  fi
}

require_admin_env() {
  [ -n "${ADMIN_EMAIL:-}" ] || fail "ADMIN_EMAIL is required"
  [ -n "${ADMIN_PASSWORD:-}" ] || fail "ADMIN_PASSWORD is required"
  if [ "${#ADMIN_PASSWORD}" -lt 8 ]; then
    fail "ADMIN_PASSWORD must be at least 8 characters"
  fi
}

require_github_env() {
  [ -n "${GITHUB_REPO:-}" ] || fail "GITHUB_REPO is required"
  [ -n "${GITHUB_PAT:-}" ] || fail "GITHUB_PAT is required"
}

rand_hex() {
  openssl rand -hex "${1:-32}"
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

wait_tcp() {
  local host="$1"
  local port="$2"
  local name="$3"
  local timeout="${4:-120}"
  local elapsed=0
  while [ "${elapsed}" -lt "${timeout}" ]; do
    if timeout 1 bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    elapsed="$((elapsed + 1))"
  done
  fail "${name} did not become ready at ${host}:${port}"
}

wait_file() {
  local path="$1"
  local name="$2"
  local timeout="${3:-120}"
  local elapsed=0
  while [ "${elapsed}" -lt "${timeout}" ]; do
    [ -f "${path}" ] && return 0
    sleep 1
    elapsed="$((elapsed + 1))"
  done
  fail "${name} did not create ${path}"
}

load_runtime_env
