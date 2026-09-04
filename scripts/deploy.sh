#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_root="${PLOSCA_RELEASE_ROOT:-/etc/caddy/conf.d/plosca-site}"
revision="$(git -C "$repo_dir" rev-parse --verify HEAD^{commit})"
release_id="$revision"

if ! git -C "$repo_dir" diff --quiet || ! git -C "$repo_dir" diff --cached --quiet; then
  echo "tracked changes must be committed before deployment" >&2
  exit 1
fi

mkdir -p "$release_root/releases"
# Publication and rollback use the same root-specific lock.
exec 9>"$release_root/.deploy.lock"
flock 9
current_link="$release_root/current"
previous_link="$release_root/previous"
release_dir="$release_root/releases/$release_id"
for link in "$current_link" "$previous_link"; do
  if [[ -e "$link" && ! -L "$link" ]]; then
    echo "refusing to replace non-symlink path: $link" >&2
    exit 1
  fi
  if [[ -L "$link" && ! -d "$link" ]]; then
    echo "release link must resolve to a directory: $link" >&2
    exit 1
  fi
done
prior_current="$(readlink "$current_link" || true)"
prior_previous="$(readlink "$previous_link" || true)"
work_dir="$(mktemp -d "$release_root/.deploy-XXXXXXXX")"
previous_changed=false
promoted=false
cleanup() {
  # Restore rollback metadata if promotion failed after recording the old current.
  if $previous_changed && ! $promoted; then
    if [[ -n "$prior_previous" ]]; then
      ln -s "$prior_previous" "$work_dir/restore-previous"
      mv -Tf "$work_dir/restore-previous" "$previous_link"
    else
      unlink "$previous_link"
    fi
  fi
  chmod -R u+w "$work_dir"
  rm -rf -- "$work_dir"
}
trap cleanup EXIT

mkdir "$work_dir/site"
git -C "$repo_dir" archive "$revision:site" | tar -x -C "$work_dir/site"
if [[ -e "$release_dir" || -L "$release_dir" ]]; then
  if [[ ! -d "$release_dir" || -L "$release_dir" ]]; then
    echo "release path must be a real directory: $release_dir" >&2
    exit 1
  fi
  diff --no-dereference -qr "$work_dir/site" "$release_dir"
else
  mv -T "$work_dir/site" "$release_dir"
fi
find "$release_dir" -type f -exec chmod 0444 {} +
find "$release_dir" -type d -exec chmod 0555 {} +

if [[ "$prior_current" != "releases/$release_id" ]]; then
  ln -s "releases/$release_id" "$work_dir/current"
  if [[ -n "$prior_current" ]]; then
    ln -s "$prior_current" "$work_dir/previous"
    mv -Tf "$work_dir/previous" "$previous_link"
    previous_changed=true
  fi
  mv -Tf "$work_dir/current" "$current_link"
  promoted=true
fi
echo "deployed $revision to $release_dir"
echo "current -> releases/$release_id"
