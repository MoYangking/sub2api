#!/usr/bin/env bash
set -euo pipefail

if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  marker_dir="/home/user/.cloudflared"
  marker_file="${marker_dir}/service-install-token.sha256"
  token_hash="$(printf '%s' "${CLOUDFLARE_TUNNEL_TOKEN}" | sha256sum | awk '{print $1}')"
  mkdir -p "${marker_dir}"

  if [ ! -f "${marker_file}" ] || [ "$(cat "${marker_file}")" != "${token_hash}" ]; then
    cloudflared service uninstall >/dev/null 2>&1 || true
    cloudflared service install "${CLOUDFLARE_TUNNEL_TOKEN}" || true
    printf '%s\n' "${token_hash}" > "${marker_file}"
  fi

  exec cloudflared tunnel --no-autoupdate run --token "${CLOUDFLARE_TUNNEL_TOKEN}"
fi

case "${CLOUDFLARE_QUICK_TUNNEL:-0}" in
  1|true|TRUE|yes|YES)
    exec cloudflared tunnel --no-autoupdate --url "${CLOUDFLARE_TUNNEL_URL:-http://127.0.0.1:7860}"
    ;;
esac

echo "[cloudflared] CLOUDFLARE_TUNNEL_TOKEN not set; tunnel disabled"
exec sleep infinity
