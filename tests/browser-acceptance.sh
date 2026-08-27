#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${PLOSCA_BROWSER_TEST_PORT:-19328}"
base="http://127.0.0.1:${port}"
tmp_dir="$(mktemp -d)"
caddy_pid=""

cleanup() {
  if [[ -n "$caddy_pid" ]] && kill -0 "$caddy_pid" 2>/dev/null; then
    kill "$caddy_pid" 2>/dev/null || true
    wait "$caddy_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if [[ ! -d "$repo_dir/.cache/browser-e2e/node_modules/playwright-core" ]]; then
  echo "run tests/setup-browser-e2e.sh before the browser acceptance test" >&2
  exit 1
fi
if ! command -v caddy >/dev/null 2>&1; then
  echo "caddy is required for the browser acceptance test" >&2
  exit 1
fi

cat >"$tmp_dir/Caddyfile" <<EOF
{
  admin off
  auto_https off
}

http://127.0.0.1:${port} {
  root * ${repo_dir}/site
  route {
    @archive_slash path /archive/
    error @archive_slash 404
    try_files {path}.html {path}/index.html {path}
    file_server
  }

  header {
    Content-Security-Policy "default-src 'self'; base-uri 'none'; font-src 'self'; img-src 'self' data: https://analytico.plosca.ru; script-src 'self' https://analytico.plosca.ru; style-src 'self'; connect-src 'self' https://analytico.plosca.ru; object-src 'none'; frame-ancestors 'none'; form-action 'self'; manifest-src 'self'"
    Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"
    Referrer-Policy "no-referrer"
    X-Content-Type-Options "nosniff"
    X-Frame-Options "DENY"
    Cross-Origin-Resource-Policy "same-origin"
  }

  handle_errors {
    rewrite * /404.html
    file_server
  }
}
EOF

caddy run --config "$tmp_dir/Caddyfile" --adapter caddyfile >"$tmp_dir/caddy.log" 2>&1 &
caddy_pid="$!"

for _ in {1..100}; do
  if curl -fsS "$base/" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$caddy_pid" 2>/dev/null; then
    cat "$tmp_dir/caddy.log" >&2 || true
    echo "caddy exited before browser checks could run" >&2
    exit 1
  fi
  sleep 0.1
done

node "$repo_dir/tests/browser-acceptance.cjs" "$base"
