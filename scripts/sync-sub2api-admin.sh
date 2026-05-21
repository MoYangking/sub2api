#!/usr/bin/env bash
set -euo pipefail

LOG_NAME="${LOG_NAME:-admin-sync}"
. /home/user/scripts/common-env.sh

wait_runtime_prepared
require_admin_env
wait_tcp "${POSTGRES_HOST}" "${POSTGRES_PORT}" PostgreSQL 120

if ! /home/user/.venv/bin/python -c 'import bcrypt' >/dev/null 2>&1; then
  fail "Python bcrypt module is not installed"
fi

password_hash="$(
  ADMIN_PASSWORD="${ADMIN_PASSWORD}" /home/user/.venv/bin/python - <<'PY'
import os
import bcrypt

password = os.environ["ADMIN_PASSWORD"].encode("utf-8")
print(bcrypt.hashpw(password, bcrypt.gensalt(rounds=12)).decode("utf-8"))
PY
)"

PGPASSWORD="${POSTGRES_PASSWORD}" psql \
  -h "${POSTGRES_HOST}" \
  -p "${POSTGRES_PORT}" \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  -v ON_ERROR_STOP=1 \
  -v admin_email="${ADMIN_EMAIL}" \
  -v password_hash="${password_hash}" <<'SQL'
CREATE TEMP TABLE _sub2api_admin_sync (
  email text NOT NULL,
  password_hash text NOT NULL
);

INSERT INTO _sub2api_admin_sync (email, password_hash)
VALUES (:'admin_email', :'password_hash');

DO $$
DECLARE
  v_email text;
  v_hash text;
  v_user_id bigint;
  v_stmt text;
BEGIN
  SELECT email, password_hash
    INTO v_email, v_hash
    FROM _sub2api_admin_sync
    LIMIT 1;

  IF to_regclass('public.users') IS NULL THEN
    RAISE NOTICE 'sub2api users table not found; skipping admin credential sync';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'deleted_at'
  ) THEN
    EXECUTE 'SELECT id FROM public.users WHERE email = $1 ORDER BY (deleted_at IS NULL) DESC, id LIMIT 1'
      INTO v_user_id
      USING v_email;
  ELSE
    EXECUTE 'SELECT id FROM public.users WHERE email = $1 ORDER BY id LIMIT 1'
      INTO v_user_id
      USING v_email;
  END IF;

  IF v_user_id IS NULL AND EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'role'
  ) THEN
    EXECUTE 'SELECT id FROM public.users WHERE role = $1 ORDER BY id LIMIT 1'
      INTO v_user_id
      USING 'admin';
  END IF;

  IF v_user_id IS NULL THEN
    v_stmt := 'INSERT INTO public.users (email, password_hash';

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'role') THEN
      v_stmt := v_stmt || ', role';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'status') THEN
      v_stmt := v_stmt || ', status';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'created_at') THEN
      v_stmt := v_stmt || ', created_at';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'updated_at') THEN
      v_stmt := v_stmt || ', updated_at';
    END IF;

    v_stmt := v_stmt || ') VALUES ($1, $2';

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'role') THEN
      v_stmt := v_stmt || ', ''admin''';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'status') THEN
      v_stmt := v_stmt || ', ''active''';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'created_at') THEN
      v_stmt := v_stmt || ', NOW()';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'updated_at') THEN
      v_stmt := v_stmt || ', NOW()';
    END IF;

    v_stmt := v_stmt || ') RETURNING id';
    EXECUTE v_stmt INTO v_user_id USING v_email, v_hash;
  ELSE
    v_stmt := 'UPDATE public.users SET email = $1, password_hash = $2';

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'role') THEN
      v_stmt := v_stmt || ', role = ''admin''';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'status') THEN
      v_stmt := v_stmt || ', status = ''active''';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'deleted_at') THEN
      v_stmt := v_stmt || ', deleted_at = NULL';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'totp_enabled') THEN
      v_stmt := v_stmt || ', totp_enabled = FALSE';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'totp_secret_encrypted') THEN
      v_stmt := v_stmt || ', totp_secret_encrypted = NULL';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'totp_enabled_at') THEN
      v_stmt := v_stmt || ', totp_enabled_at = NULL';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'updated_at') THEN
      v_stmt := v_stmt || ', updated_at = NOW()';
    END IF;

    v_stmt := v_stmt || ' WHERE id = $3';
    EXECUTE v_stmt USING v_email, v_hash, v_user_id;
  END IF;

  RAISE NOTICE 'sub2api admin credentials synced for %', v_email;
END $$;
SQL

log "sub2api admin credentials synced for ${ADMIN_EMAIL}"
