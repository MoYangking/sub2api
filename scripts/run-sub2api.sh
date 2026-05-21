#!/usr/bin/env bash
set -euo pipefail

LOG_NAME=sub2api
. /home/user/scripts/common-env.sh

/home/user/scripts/prepare-runtime.sh
. /home/user/scripts/common-env.sh
wait_file "${HOME}/.sub2api-postgres-restore-complete" "PostgreSQL restore" 300
wait_tcp "${REDIS_HOST}" "${REDIS_PORT}" Redis 120

export DATA_DIR="${SUB2API_DATA_DIR}"
export AUTO_SETUP=true
export SERVER_HOST=127.0.0.1
export SERVER_PORT=8080
export SERVER_MODE="${SERVER_MODE:-release}"
export RUN_MODE="${RUN_MODE:-standard}"
export TZ="${TZ:-Asia/Shanghai}"

export DATABASE_HOST="${POSTGRES_HOST}"
export DATABASE_PORT="${POSTGRES_PORT}"
export DATABASE_USER="${POSTGRES_USER}"
export DATABASE_PASSWORD="${POSTGRES_PASSWORD}"
export DATABASE_DBNAME="${POSTGRES_DB}"
export DATABASE_SSLMODE=disable
export DATABASE_MAX_OPEN_CONNS="${DATABASE_MAX_OPEN_CONNS:-50}"
export DATABASE_MAX_IDLE_CONNS="${DATABASE_MAX_IDLE_CONNS:-10}"

export REDIS_HOST="${REDIS_HOST}"
export REDIS_PORT="${REDIS_PORT}"
export REDIS_PASSWORD="${REDIS_PASSWORD}"
export REDIS_DB="${REDIS_DB}"
export REDIS_ENABLE_TLS=false

export ADMIN_EMAIL="${ADMIN_EMAIL}"
export ADMIN_PASSWORD="${ADMIN_PASSWORD}"
export JWT_SECRET="${JWT_SECRET}"
export TOTP_ENCRYPTION_KEY="${TOTP_ENCRYPTION_KEY}"

mkdir -p "${SUB2API_DATA_DIR}" "${HOME}/logs/sub2api"
chown -R 1000:1000 "${SUB2API_DATA_DIR}" "${HOME}/logs/sub2api" 2>/dev/null || true

log "starting sub2api"
exec /home/user/sub2api/sub2api
