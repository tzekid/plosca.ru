#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_root="/etc/caddy/conf.d/plosca-site"
release_id="$(git -C "$repo_dir" rev-parse --short=12 HEAD)"
release_dir="$release_root/releases/$release_id"
staging_dir="$release_root/.staging-$release_id-$BASHPID"
next_link="$release_root/.current-$release_id-$BASHPID"
current_link="$release_root/current"

if ! git -C "$repo_dir" diff --quiet || ! git -C "$repo_dir" diff --cached --quiet; then
  echo "tracked changes must be committed before deployment" >&2
  exit 1
fi
if [[ ! -d "$repo_dir/site" ]]; then
  echo "authored site directory is missing" >&2
  exit 1
fi
if [[ -e "$current_link" && ! -L "$current_link" ]]; then
  echo "refusing to replace non-symlink current path: $current_link" >&2
  exit 1
fi

cleanup() {
  if [[ -L "$next_link" ]]; then unlink "$next_link"; fi
  if [[ -d "$staging_dir" ]]; then
    chmod -R u+w "$staging_dir" 2>/dev/null || true
    rm -rf -- "$staging_dir"
  fi
}
trap cleanup EXIT

mkdir -p "$release_root/releases"
if [[ -d "$release_dir" ]]; then
  diff -qr "$repo_dir/site" "$release_dir"
else
  mkdir "$staging_dir"
  rsync -a "$repo_dir/site/" "$staging_dir/"
  diff -qr "$repo_dir/site" "$staging_dir"
  mv "$staging_dir" "$release_dir"
fi
find "$release_dir" -type f -exec chmod 0444 {} +
find "$release_dir" -type d -exec chmod 0555 {} +

ln -s "releases/$release_id" "$next_link"
mv -Tf "$next_link" "$current_link"

trap - EXIT
echo "deployed $release_id to $release_dir"
echo "current -> releases/$release_id"
