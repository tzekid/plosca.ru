#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sitec_bin="${1:-$repo_dir/zig-out/bin/sitec}"

if [[ ! -x "$sitec_bin" ]]; then
  echo "sitec executable not found: $sitec_bin" >&2
  exit 1
fi

tree_hash() {
  find dist -type f -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum \
    | sha256sum \
    | cut -d' ' -f1
}

cd "$repo_dir"
"$sitec_bin" build
first_hash="$(tree_hash)"
"$sitec_bin" build
second_hash="$(tree_hash)"

if [[ "$first_hash" != "$second_hash" ]]; then
  echo "non-deterministic dist: $first_hash != $second_hash" >&2
  exit 1
fi
if [[ -e dist.tmp || -e dist.previous ]]; then
  echo "sitec leaked a temporary publish directory" >&2
  exit 1
fi

echo "deterministic build passed: $first_hash"
