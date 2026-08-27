#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_root="${PLOSCA_RELEASE_ROOT:-/etc/caddy/conf.d/plosca-site}"
release_id="${1:-$(git -C "$repo_dir" rev-parse --short=12 HEAD)}"

if [[ ! "$release_id" =~ ^[0-9A-Za-z._-]+$ ]]; then
  echo "invalid release id: $release_id" >&2
  exit 1
fi
if [[ -z "$release_root" || "$release_root" == "/" ]]; then
  echo "refusing unsafe release root: $release_root" >&2
  exit 1
fi
if ! git -C "$repo_dir" diff --quiet || ! git -C "$repo_dir" diff --cached --quiet; then
  echo "tracked changes must be committed before deployment" >&2
  exit 1
fi

cd "$repo_dir"
zig build -Doptimize=ReleaseFast
zig-out/bin/sitec build
zig-out/bin/sitec check

releases_dir="$release_root/releases"
release_dir="$releases_dir/$release_id"
staging_dir="$release_root/.staging-$release_id-$BASHPID"
next_link="$release_root/.current-$release_id-$BASHPID"
current_link="$release_root/current"
previous_target=""
switched=0
complete=0

mkdir -p "$releases_dir"
if [[ -e "$current_link" && ! -L "$current_link" ]]; then
  echo "refusing to replace non-symlink current path: $current_link" >&2
  exit 1
fi
if [[ -L "$current_link" ]]; then previous_target="$(readlink "$current_link")"; fi

cleanup() {
  if [[ -L "$next_link" ]]; then unlink "$next_link"; fi
  if [[ -d "$staging_dir" ]]; then rm -rf -- "$staging_dir"; fi
  if [[ "$switched" == "1" && "$complete" != "1" ]]; then
    if [[ -n "$previous_target" ]]; then
      ln -s "$previous_target" "$next_link"
      mv -Tf "$next_link" "$current_link"
    elif [[ -L "$current_link" ]]; then
      unlink "$current_link"
    fi
  fi
}
trap cleanup EXIT

if [[ -L "$release_dir" || ( -e "$release_dir" && ! -d "$release_dir" ) ]]; then
  echo "invalid immutable release path: $release_dir" >&2
  exit 1
fi
if [[ -d "$release_dir" ]]; then
  diff -qr dist "$release_dir"
else
  mkdir "$staging_dir"
  rsync -a dist/ "$staging_dir/"
  diff -qr dist "$staging_dir"
  mv "$staging_dir" "$release_dir"
fi
find "$release_dir" -type f -exec chmod 0444 {} +
find "$release_dir" -type d -exec chmod 0555 {} +

ln -s "releases/$release_id" "$next_link"
mv -Tf "$next_link" "$current_link"
switched=1

if [[ "${PLOSCA_RELOAD_CADDY:-0}" == "1" ]]; then
  caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
  caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile --force
fi

complete=1
trap - EXIT
echo "deployed $release_id to $release_dir"
echo "current -> releases/$release_id"
