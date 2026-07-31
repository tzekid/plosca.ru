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
  zig build --system zig-pkg run -- serve --host 127.0.0.1 --port "$port" >"$tmp_dir/server.log" 2>&1 &
  server_pid="$!"

  for _ in {1..100}; do
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

request() {
  local method="$1"
  local path="$2"
  shift 2
  curl -sS -X "$method" -D "$tmp_dir/headers" -o "$tmp_dir/body" \
    -w "%{http_code}" "$@" "$base$path"
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

expect_status "/" 200
home_html="$(cat "$tmp_dir/body")"
expect_status "/about" 200
expect_status "/hello_world" 200
article_html="$(cat "$tmp_dir/body")"
expect_status "/prose" 200
expect_status "/missing-page" 404
expect_status "/resume.pdf" 200
expect_status "/site.webmanifest" 200
expect_status "/preview-controller.js" 200
expect_status "/vendor/htmx.min.js" 200
expect_status "/metadata/connections/hello_world.html" 200
expect_status "/metadata/previews/3979d6c13901b2e1.html" 200

if ! grep -q 'generated-connections' <<<"$article_html"; then
  echo "article first response is missing generated connections" >&2
  exit 1
fi
if grep -q 'hx-trigger="load"' <<<"$article_html"; then
  echo "article first response performs a prohibited startup HTMX request" >&2
  exit 1
fi
if ! grep -q '<a href="/about"' <<<"$home_html"; then
  echo "home first response is missing native navigation" >&2
  exit 1
fi

style_path="$(grep -Eo '/style\.css\?v=[0-9a-f]{16}' <<<"$home_html" | head -n 1 || true)"
if [[ -z "$style_path" ]]; then
  echo "home page does not reference a versioned stylesheet" >&2
  exit 1
fi
expect_status "$style_path" 200

status="$(request GET "/style.css" -H "Accept-Encoding: br")"
[[ "$status" == "200" ]]
grep -qi '^content-encoding: br' "$tmp_dir/headers"

status="$(request GET "/hello_world")"
[[ "$status" == "200" ]]
etag="$(sed -n 's/^etag: \(.*\)\r$/\1/ip' "$tmp_dir/headers" | head -n 1)"
if [[ -z "$etag" ]]; then
  echo "article response is missing an ETag" >&2
  exit 1
fi
status="$(request GET "/hello_world" -H "If-None-Match: W/$etag")"
[[ "$status" == "304" ]]

status="$(request GET "/metadata/previews/3979d6c13901b2e1.html" \
  -H "HX-Request: true" -H "HX-Request-Type: partial")"
[[ "$status" == "200" ]]
grep -q 'id="link-preview"' "$tmp_dir/body"

status="$(request POST "/about")"
[[ "$status" == "405" ]]
grep -qi '^allow: GET, HEAD' "$tmp_dir/headers"

status="$(request GET "/%2e%2e/etc/passwd")"
[[ "$status" == "404" ]]

status="$(request GET "/")"
[[ "$status" == "200" ]]
grep -qi '^content-security-policy:' "$tmp_dir/headers"
grep -qi '^x-content-type-options: nosniff' "$tmp_dir/headers"
if grep -Eqi "content-security-policy:.*unsafe-(inline|eval)" "$tmp_dir/headers"; then
  echo "CSP unexpectedly permits unsafe script execution" >&2
  exit 1
fi

for directive in script-src connect-src img-src; do
  if ! grep -Eqi "^content-security-policy:.*${directive}[^;]*https://analytico\.plosca\.ru([;[:space:]]|$)" "$tmp_dir/headers"; then
    echo "CSP ${directive} does not allow https://analytico.plosca.ru" >&2
    exit 1
  fi
done

echo "smoke checks passed for $base"
