#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module_dir="$repo_dir/.zig-cache/browser-e2e"

mkdir -p "$module_dir"
npm install \
  --prefix "$module_dir" \
  --no-save \
  --no-package-lock \
  --ignore-scripts \
  playwright-core@1.62.0

node -e "require('$module_dir/node_modules/playwright-core')"
echo "browser E2E dependency ready"
