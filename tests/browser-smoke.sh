#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bin="${1:-$repo_dir/zig-out/bin/webapp}"
port="${PLOSCA_BROWSER_TEST_PORT:-19328}"
base="http://127.0.0.1:${port}"
tmp_dir="$(mktemp -d)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if [[ ! -x "$app_bin" ]]; then
  echo "webapp executable not found: $app_bin" >&2
  exit 1
fi
if [[ ! -d "$repo_dir/.zig-cache/browser-e2e/node_modules/playwright-core" ]]; then
  echo "run tests/setup-browser-e2e.sh before the browser smoke test" >&2
  exit 1
fi

cd "$repo_dir"
"$app_bin" serve --host 127.0.0.1 --port "$port" >"$tmp_dir/server.log" 2>&1 &
server_pid="$!"

for _ in {1..100}; do
  if curl -fsS "$base/" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    cat "$tmp_dir/server.log" >&2 || true
    echo "server exited before browser checks could run" >&2
    exit 1
  fi
  sleep 0.1
done

node tests/browser-smoke.cjs "$base"
