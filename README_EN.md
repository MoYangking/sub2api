# sub2api Single-Port Gateway

This image runs [Wei-Shaw/sub2api](https://github.com/Wei-Shaw/sub2api) in a single-container, single-public-port layout. `supervisord` manages sub2api, PostgreSQL, Redis, pgAdmin, FileBrowser, GoTTY, GitHub Sync, and cloudflared. OpenResty exposes only port `7860`.

## Components

- sub2api on `127.0.0.1:8080`
- PostgreSQL 15+ on `127.0.0.1:5432`
- Redis 7+ on `127.0.0.1:6379`
- pgAdmin 4 at `/pgadmin4/`
- FileBrowser at `/filebrowser/`
- GoTTY web terminal at `/t/`
- GitHub Sync at `/sync/`

pgAdmin, FileBrowser, and GoTTY use `ADMIN_EMAIL` / `ADMIN_PASSWORD` for login.

## Required Environment

```env
GITHUB_REPO=<owner>/<repo>
GITHUB_PAT=<token>
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=<strong-password>
```

Use a private GitHub repository because backups include database snapshots, configuration, and recovery secrets.

## Optional Environment

```env
SUB2API_VERSION=latest
GIT_BRANCH=main
BACKUP_INTERVAL=3600
BACKUP_RETENTION_DAYS=14
RESTORE_SUB2API_ON_START=always
CLOUDFLARE_TUNNEL_TOKEN=
```

`RESTORE_SUB2API_ON_START` supports:

- `always`: default. Restore from GitHub `latest` snapshots on every start when available.
- `missing`: restore only when local data is missing.
- `never`: disable automatic restore.

## Routes

- `/`: sub2api UI and API
- `/health`: sub2api health check
- `/pgadmin4/`: PostgreSQL admin UI
- `/filebrowser/`: file manager
- `/t/`: web terminal
- `/sync/`: GitHub Sync UI

## Backup And Restore

Live data directories:

- `/data/postgres`
- `/data/redis`
- `/data/sub2api`
- `/home/user/pgadmin-data`
- `/home/user/filebrowser-data`
- `/home/user/secrets/runtime.env`

GitHub Sync only syncs consistent snapshots, not live database directories. The default sync target is:

```text
home/user/backups/sub2api/
```

Latest snapshot files:

- `latest.pg.dump`: PostgreSQL custom-format dump
- `latest.redis.rdb`: Redis RDB snapshot
- `latest.state.tar.gz`: sub2api config, runtime secrets, pgAdmin/FileBrowser state
- `latest.json`: backup manifest

Manual backup:

```bash
docker exec -e BACKUP_INTERVAL=0 sub2api-gateway /home/user/scripts/backup-sub2api.sh
```

Manual PostgreSQL restore phase:

```bash
docker exec -e RESTORE_SUB2API_ON_START=always sub2api-gateway /home/user/scripts/restore-sub2api-backup.sh
```

For a full state plus Redis plus PostgreSQL restore, restart the container and let the startup sequence run.

## Local Docker

```bash
docker build -t sub2api-gateway:latest .
docker run -d \
  -p 7860:7860 \
  -e GITHUB_REPO="<owner>/<repo>" \
  -e GITHUB_PAT="<token>" \
  -e ADMIN_EMAIL="admin@example.com" \
  -e ADMIN_PASSWORD="<strong-password>" \
  --name sub2api-gateway \
  sub2api-gateway:latest
```

Open `http://localhost:7860/`.

## Cloudflare Tunnel

Create a Cloudflare Tunnel and point the Public Hostname service to:

```text
http://localhost:7860
```

Then pass `CLOUDFLARE_TUNNEL_TOKEN` when starting the container. For temporary testing, set `CLOUDFLARE_QUICK_TUNNEL=1`.
