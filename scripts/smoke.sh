#!/usr/bin/env bash
set -euo pipefail

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

if [[ -n "${PLOSCA_BASE_URL:-}" ]]; then
  base="${PLOSCA_BASE_URL%/}"
else
  port="${PLOSCA_TEST_PORT:-19327}"
  base="http://127.0.0.1:${port}"
  zig build run -- serve --host 127.0.0.1 --port "$port" >"$tmp_dir/server.log" 2>&1 &
  server_pid="$!"

  for _ in {1..80}; do
    if curl -fsS "$base/" >/dev/null 2>&1; then
      break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
      cat "$tmp_dir/server.log" >&2 || true
      echo "server exited before smoke checks could run" >&2
      exit 1
    fi
    sleep 0.1
  done
fi

curl_common=(-sS)
if [[ "$base" == https://* ]]; then
  curl_common+=("--proto" "=https")
fi

request() {
  local method="$1"
  local path="$2"
  local body="$tmp_dir/body"
  local headers="$tmp_dir/headers"
  local status

  status="$(curl "${curl_common[@]}" -X "$method" -D "$headers" -o "$body" -w "%{http_code}" "$base$path")"
  printf '%s\n' "$status"
}

expect_status() {
  local path="$1"
  local expected="$2"
  local status
  status="$(request GET "$path")"
  if [[ "$status" != "$expected" ]]; then
    echo "GET $path returned $status, expected $expected" >&2
    cat "$tmp_dir/body" >&2 || true
    exit 1
  fi
}

expect_head_status() {
  local path="$1"
  local expected="$2"
  local status
  status="$(curl "${curl_common[@]}" -I -o "$tmp_dir/head" -w "%{http_code}" "$base$path")"
  if [[ "$status" != "$expected" ]]; then
    echo "HEAD $path returned $status, expected $expected" >&2
    cat "$tmp_dir/head" >&2 || true
    exit 1
  fi
}

expect_status "/" 200
home_html="$(cat "$tmp_dir/body")"
expect_status "/about" 200
expect_status "/hello_world" 200
expect_status "/prose" 200
expect_status "/missing-page" 404
expect_status "/resume.pdf" 200
expect_status "/site.webmanifest" 200

style_path="$(printf '%s' "$home_html" | grep -Eo '/style\.css\?v=[0-9a-f]{16}' | head -n 1 || true)"
if [[ -z "$style_path" ]]; then
  echo "home page does not reference a versioned /style.css asset" >&2
  exit 1
fi
expect_status "$style_path" 200

expect_head_status "/about" 200

post_status="$(curl "${curl_common[@]}" -X POST -o "$tmp_dir/post-body" -w "%{http_code}" "$base/about")"
if [[ "$post_status" != "405" ]]; then
  echo "POST /about returned $post_status, expected 405" >&2
  cat "$tmp_dir/post-body" >&2 || true
  exit 1
fi

echo "smoke checks passed for $base"
