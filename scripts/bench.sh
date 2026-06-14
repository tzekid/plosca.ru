#!/usr/bin/env sh
set -eu

base="${1:-http://127.0.0.1:9327}"
paths="/ /about /style.css /resume.pdf /does-not-exist"

if command -v oha >/dev/null 2>&1; then
    for path in $paths; do
        printf '\n== oha %s%s ==\n' "$base" "$path"
        oha -z 10s "$base$path"
    done
elif command -v wrk >/dev/null 2>&1; then
    for path in $paths; do
        printf '\n== wrk %s%s ==\n' "$base" "$path"
        wrk -t2 -c32 -d10s "$base$path"
    done
else
    printf '%s\n' "Install oha or wrk to run benchmarks."
    exit 1
fi
