# sub2api 单容器网关

这个镜像把 [Wei-Shaw/sub2api](https://github.com/Wei-Shaw/sub2api) 接入单容器、单端口结构：容器内由 `supervisord` 托管 sub2api、PostgreSQL、Redis、pgAdmin、FileBrowser、GoTTY、GitHub Sync 和 cloudflared，对外只暴露 `7860`，由 OpenResty 统一反代。

## 组件

- sub2api：主服务，内部监听 `127.0.0.1:8080`
- PostgreSQL 15+：内部监听 `127.0.0.1:5432`
- Redis 7+：内部监听 `127.0.0.1:6379`
- pgAdmin 4：入口 `/pgadmin4/`
- FileBrowser：入口 `/filebrowser/`
- GoTTY Web Terminal：入口 `/t/`
- GitHub Sync：入口 `/sync/`

## 路由

- `/`：sub2api Web UI 和 API
- `/health`：sub2api 健康检查
- `/pgadmin4/`：PostgreSQL 可视化管理
- `/filebrowser/`：文件管理
- `/t/`：Web 终端
- `/sync/`：GitHub 同步状态与管理

pgAdmin、FileBrowser、GoTTY 都使用 `ADMIN_EMAIL` / `ADMIN_PASSWORD` 初始化或更新登录凭据。

## 必填配置

```env
GITHUB_REPO=<owner>/<repo>
GITHUB_PAT=<token>
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=<strong-password>
```

建议使用私有 GitHub 仓库，因为备份包含数据库快照、配置和恢复所需密钥。

## 可选配置

```env
SUB2API_VERSION=latest
GIT_BRANCH=main
BACKUP_INTERVAL=3600
BACKUP_RETENTION_DAYS=14
RESTORE_SUB2API_ON_START=always
CLOUDFLARE_TUNNEL_TOKEN=
```

`RESTORE_SUB2API_ON_START` 可选值：

- `always`：默认值。每次启动只要存在 `latest` 备份，就按 GitHub 备份覆盖恢复本地状态。
- `missing`：仅本地数据缺失时恢复。
- `never`：不自动恢复。

## 数据与备份

运行数据目录：

- `/data/postgres`
- `/data/redis`
- `/data/sub2api`
- `/home/user/pgadmin-data`
- `/home/user/filebrowser-data`
- `/home/user/secrets/runtime.env`

默认只同步一致快照，不同步活跃数据库目录。GitHub Sync 默认目标：

```text
home/user/backups/sub2api/
```

备份目录中的 `latest` 文件：

- `latest.pg.dump`：PostgreSQL custom-format dump
- `latest.redis.rdb`：Redis RDB 快照
- `latest.state.tar.gz`：sub2api 配置、运行密钥、pgAdmin/FileBrowser 状态
- `latest.json`：备份 manifest

启动时默认会先等待 GitHub Sync 拉取备份，再恢复 state、Redis 和 PostgreSQL，最后启动 sub2api。若恢复前本地已有数据，会先在 `home/user/backups/sub2api/emergency/` 下生成 emergency 快照。

## 本地运行

构建：

```bash
docker build -t sub2api-gateway:latest .
```

启动：

```bash
docker run -d \
  -p 7860:7860 \
  -e GITHUB_REPO="<owner>/<repo>" \
  -e GITHUB_PAT="<token>" \
  -e ADMIN_EMAIL="admin@example.com" \
  -e ADMIN_PASSWORD="<strong-password>" \
  --name sub2api-gateway \
  sub2api-gateway:latest
```

访问 `http://localhost:7860/`。

## 手动备份与恢复

手动触发一次备份：

```bash
docker exec -e BACKUP_INTERVAL=0 sub2api-gateway /home/user/scripts/backup-sub2api.sh
```

手动执行恢复阶段：

```bash
docker exec -e RESTORE_SUB2API_ON_START=always sub2api-gateway /home/user/scripts/restore-sub2api-backup.sh
```

Redis 和 state 的启动前恢复由 `prepare-runtime.sh` 与 `run-redis.sh` 处理；完整恢复路径建议通过重启容器完成。

## Cloudflare Tunnel

镜像通过 Cloudflare 官方 apt 源安装 `cloudflared`。在 Cloudflare Zero Trust 创建 Tunnel 后，将 Public Hostname 的 Service 指向：

```text
http://localhost:7860
```

启动容器时传入：

```bash
docker run -d \
  -p 7860:7860 \
  -e GITHUB_REPO="<owner>/<repo>" \
  -e GITHUB_PAT="<token>" \
  -e ADMIN_EMAIL="admin@example.com" \
  -e ADMIN_PASSWORD="<strong-password>" \
  -e CLOUDFLARE_TUNNEL_TOKEN="<cloudflare tunnel token>" \
  --name sub2api-gateway \
  sub2api-gateway:latest
```

临时测试可设置 `CLOUDFLARE_QUICK_TUNNEL=1`。

## 排障

- sub2api 未启动：先看 `docker logs sub2api-gateway` 中 `prepare-runtime`、`restore`、`sub2api` 的日志。
- pgAdmin 登录：使用 `ADMIN_EMAIL` / `ADMIN_PASSWORD`，入口是 `/pgadmin4/`。
- GitHub 备份没有更新：确认 `GITHUB_REPO`、`GITHUB_PAT`、`GIT_BRANCH` 和仓库权限。
- 默认恢复覆盖了本地数据：这是 `RESTORE_SUB2API_ON_START=always` 的预期行为，可改为 `missing` 或 `never`。
