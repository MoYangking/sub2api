FROM ubuntu:24.04

# Default mirrors. Override these when building in a slower network.
ARG APT_MIRROR=http://azure.archive.ubuntu.com/ubuntu
ARG PIP_INDEX_URL=https://pypi.org/simple/
ARG SUB2API_VERSION=latest

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai

RUN set -eux; \
    mirror="${APT_MIRROR%/}"; \
    if [ -f /etc/apt/sources.list ]; then \
      sed -i "s|http://archive.ubuntu.com/ubuntu|${mirror}|g; s|http://security.ubuntu.com/ubuntu|${mirror}|g" /etc/apt/sources.list; \
    fi; \
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
      sed -i "s|http://archive.ubuntu.com/ubuntu|${mirror}|g; s|http://security.ubuntu.com/ubuntu|${mirror}|g" /etc/apt/sources.list.d/ubuntu.sources; \
    fi

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release bash tar gzip \
    git jq rsync openssl procps wget sqlite3 \
    python3 python3-pip python3-venv \
    supervisor postgresql postgresql-client redis-server \
 && rm -rf /var/lib/apt/lists/*

# Install OpenResty, pgAdmin 4, and Cloudflare Tunnel from their upstream apt repositories.
RUN set -eux; \
    mkdir -p --mode=0755 /usr/share/keyrings; \
    curl -fsSL https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/openresty.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/ubuntu $(lsb_release -sc) main" \
      > /etc/apt/sources.list.d/openresty.list; \
    curl -fsSL https://www.pgadmin.org/static/packages_pgadmin_org.pub | gpg --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" \
      > /etc/apt/sources.list.d/pgadmin4.list; \
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null; \
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
      > /etc/apt/sources.list.d/cloudflared.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends openresty pgadmin4-web cloudflared; \
    rm -rf /var/lib/apt/lists/*; \
    cloudflared --version

RUN mkdir -p /home/user /data && chown -R 1000:1000 /home/user /data
ENV HOME=/home/user \
    VIRTUAL_ENV=/home/user/.venv \
    PATH=/home/user/.venv/bin:/home/user/.local/bin:/usr/local/openresty/bin:$PATH
WORKDIR /home/user

RUN python3 -m venv "$VIRTUAL_ENV" && \
    "$VIRTUAL_ENV/bin/pip" install --no-cache-dir --upgrade pip && \
    "$VIRTUAL_ENV/bin/pip" install --no-cache-dir --index-url "${PIP_INDEX_URL}" fastapi uvicorn httpx bcrypt

# pgAdmin's apt package provides the application virtualenv, but not every
# package build ships a gunicorn executable. Install the module explicitly and
# launch it with the pgAdmin Python interpreter.
RUN set -eux; \
    /usr/pgadmin4/venv/bin/python3 -m ensurepip --upgrade || true; \
    /usr/pgadmin4/venv/bin/python3 -m pip install --no-cache-dir --index-url "${PIP_INDEX_URL}" gunicorn

# Configure pgAdmin for direct gunicorn hosting behind OpenResty at /pgadmin4.
RUN set -eux; \
    { \
      printf '%s\n' 'import os'; \
      printf '%s\n' 'SERVER_MODE = True'; \
      printf '%s\n' 'DATA_DIR = os.environ.get("PGADMIN_DATA_DIR", "/home/user/pgadmin-data")'; \
      printf '%s\n' 'LOG_FILE = os.environ.get("PGADMIN_LOG_FILE", "/home/user/logs/pgadmin/pgadmin4.log")'; \
      printf '%s\n' 'SQLITE_PATH = os.path.join(DATA_DIR, "pgadmin4.db")'; \
      printf '%s\n' 'SESSION_DB_PATH = os.path.join(DATA_DIR, "sessions")'; \
      printf '%s\n' 'STORAGE_DIR = os.path.join(DATA_DIR, "storage")'; \
      printf '%s\n' 'AZURE_CREDENTIAL_CACHE_DIR = os.path.join(DATA_DIR, "azurecredentialcache")'; \
      printf '%s\n' 'KERBEROS_CCACHE_DIR = os.path.join(DATA_DIR, "kerberosccache")'; \
      printf '%s\n' 'MASTER_PASSWORD_REQUIRED = False'; \
      printf '%s\n' 'DEFAULT_SERVER = "127.0.0.1"'; \
      printf '%s\n' 'DEFAULT_SERVER_PORT = 5050'; \
      printf '%s\n' 'WTF_CSRF_SSL_STRICT = False'; \
    } > /usr/pgadmin4/web/config_local.py

# Download the requested sub2api release binary and verify it with checksums.txt.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
      amd64) sub_arch="amd64" ;; \
      arm64) sub_arch="arm64" ;; \
      *) echo "Unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    if [ "${SUB2API_VERSION}" = "latest" ]; then \
      release_json="$(curl -fsSL https://api.github.com/repos/Wei-Shaw/sub2api/releases/latest)"; \
    else \
      release_json="$(curl -fsSL "https://api.github.com/repos/Wei-Shaw/sub2api/releases/tags/${SUB2API_VERSION}")"; \
    fi; \
    tag="$(printf '%s' "${release_json}" | jq -r '.tag_name')"; \
    version="${tag#v}"; \
    asset_name="sub2api_${version}_linux_${sub_arch}.tar.gz"; \
    asset_url="$(printf '%s' "${release_json}" | jq -r --arg name "${asset_name}" '.assets[] | select(.name == $name) | .browser_download_url' | head -n 1)"; \
    sums_url="$(printf '%s' "${release_json}" | jq -r '.assets[] | select(.name == "checksums.txt") | .browser_download_url' | head -n 1)"; \
    test -n "${tag}"; \
    test -n "${asset_url}"; \
    test -n "${sums_url}"; \
    curl -fL --retry 3 --retry-delay 1 -o /tmp/sub2api.tar.gz "${asset_url}"; \
    curl -fL --retry 3 --retry-delay 1 -o /tmp/checksums.txt "${sums_url}"; \
    grep -E "[[:space:]]${asset_name}$" /tmp/checksums.txt | sed "s#${asset_name}#/tmp/sub2api.tar.gz#" | sha256sum -c -; \
    mkdir -p /tmp/sub2api-release /home/user/sub2api; \
    tar -xzf /tmp/sub2api.tar.gz -C /tmp/sub2api-release; \
    install -m 0755 /tmp/sub2api-release/sub2api /home/user/sub2api/sub2api; \
    chown -R 1000:1000 /home/user/sub2api; \
    rm -rf /tmp/sub2api-release /tmp/sub2api.tar.gz /tmp/checksums.txt

# Download and install FileBrowser.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
      amd64) fb_arch="amd64" ;; \
      arm64) fb_arch="arm64" ;; \
      *) echo "Unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    LATEST_URL="$(curl -fsSL https://api.github.com/repos/filebrowser/filebrowser/releases/latest | \
      jq -r --arg suffix "linux-${fb_arch}-filebrowser.tar.gz" '.assets[] | select(.name | endswith($suffix)) | .browser_download_url' | \
      head -n 1 | tr -d '\r')"; \
    test -n "${LATEST_URL}"; \
    curl -fL -o /tmp/filebrowser.tar.gz "${LATEST_URL}"; \
    tar -xzf /tmp/filebrowser.tar.gz -C /tmp; \
    mv /tmp/filebrowser /home/user/filebrowser; \
    chmod +x /home/user/filebrowser; \
    chown 1000:1000 /home/user/filebrowser; \
    rm -f /tmp/filebrowser.tar.gz

# Download and install GoTTY (web terminal).
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
      amd64) gotty_arch="amd64" ;; \
      arm64) gotty_arch="arm64" ;; \
      *) echo "Unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    LATEST_URL="$(curl -fsSL https://api.github.com/repos/sorenisanerd/gotty/releases/latest | \
      jq -r --arg arch "${gotty_arch}" '.assets[] | select(.name | test("gotty_v.*_linux_" + $arch + "\\.tar\\.gz$")) | .browser_download_url' | \
      head -n 1 | tr -d '\r')"; \
    test -n "${LATEST_URL}"; \
    curl -fL -o /tmp/gotty.tar.gz "${LATEST_URL}"; \
    tar -xzf /tmp/gotty.tar.gz -C /tmp; \
    mv /tmp/gotty /home/user/gotty; \
    chmod +x /home/user/gotty; \
    chown 1000:1000 /home/user/gotty; \
    rm -f /tmp/gotty.tar.gz

RUN mkdir -p \
      /home/user/logs \
      /home/user/backups/sub2api \
      /home/user/secrets \
      /home/user/filebrowser-data \
      /home/user/pgadmin-data \
      /data/sub2api \
      /data/postgres \
      /data/redis \
    && chown -R 1000:1000 /home/user /data \
    && chown -R postgres:postgres /data/postgres

COPY --chown=1000:1000 supervisor/supervisord.conf /home/user/supervisord.conf
RUN mkdir -p /home/user/nginx && chown -R 1000:1000 /home/user/nginx
COPY --chown=1000:1000 nginx/nginx.conf /home/user/nginx/nginx.conf
RUN mkdir -p \
      /home/user/nginx/tmp/body \
      /home/user/nginx/tmp/proxy \
      /home/user/nginx/tmp/fastcgi \
      /home/user/nginx/tmp/uwsgi \
      /home/user/nginx/tmp/scgi \
    && chown -R 1000:1000 /home/user/nginx

COPY --chown=1000:1000 sync /home/user/sync

RUN mkdir -p /home/user/scripts && chown -R 1000:1000 /home/user/scripts
COPY --chown=1000:1000 scripts /home/user/scripts
RUN sed -i 's/\r$//' /home/user/scripts/*.sh && chmod +x /home/user/scripts/*.sh

ENV SERVER_MODE=release \
    RUN_MODE=standard \
    SUB2API_DATA_DIR=/data/sub2api \
    PGDATA=/data/postgres \
    REDIS_DATA_DIR=/data/redis \
    BACKUP_DIR=/home/user/backups/sub2api \
    BACKUP_INTERVAL=3600 \
    BACKUP_RETENTION_DAYS=14 \
    RESTORE_SUB2API_ON_START=always \
    SYNC_TARGETS="home/user/backups/sub2api/"

EXPOSE 7860

ENTRYPOINT ["/home/user/scripts/container-entrypoint.sh"]
CMD ["supervisord", "-c", "/home/user/supervisord.conf"]
