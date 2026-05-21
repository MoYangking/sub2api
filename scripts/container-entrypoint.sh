#!/usr/bin/env bash
set -euo pipefail

rm -f \
  /home/user/.runtime-prepared \
  /home/user/.sub2api-postgres-restore-complete \
  /home/user/.sub2api-redis-restore-complete

rm -rf \
  /home/user/.runtime-prepare.lock \
  /home/user/.sub2api-postgres-restore.lock \
  /home/user/.sub2api-redis-restore.lock

exec "$@"
