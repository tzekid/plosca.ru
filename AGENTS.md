# Repository Guidelines

This repository builds a minimal Zig static file server for `plosca.ru`.

## Overview

The production binary is `webapp`.

Key characteristics:
- Zig-based HTTP server using the standard library.
- Serves files from on-disk `static/`.
- Extensionless path resolution with `.html` and `index.html` fallbacks.
- `GET` and `HEAD` only; other methods return `405`.
- Traversal outside `static/` is rejected.

## Project Structure

- `build.zig`: Zig build, run, and test steps.
- `src/main.zig`: CLI, listener, routing, streaming static file responses, cache validators, and tests.
- `src/styles/site.css`: plain source stylesheet.
- `static/`: site files.
- `static/style.css`: generated stylesheet committed for deployment.
- `.github/workflows/ci.yml`: Zig format/test/build CI.

## Build, Run, and Ports

Port precedence:
1. `--port`
2. `PORT` environment variable
3. Default `9327`

Commands:
- Run: `zig build run -- serve`
- Run on another port: `zig build run -- serve --port 8080`
- Run with HSTS: `zig build run -- serve --hsts-max-age 31536000`
- Build: `zig build -Doptimize=ReleaseFast`
- Test: `zig build test`
- Build CSS and update HTML stylesheet cache-busters: `zig build css`
- Check CSS/hash sync and local asset references: `zig build check-site`
- Smoke local site: `./scripts/smoke.sh`
- Smoke deployed site: `PLOSCA_BASE_URL=https://plosca.ru ./scripts/smoke.sh`

The built binary is `zig-out/bin/webapp`.

## Routing Contract

Static routes use this candidate order:
1. exact path
2. `path.html`
3. `path/index.html`

Missing files return `static/404.html` with status `404` when available.

## Notes

There is no asset embedding, generated manifest, metrics endpoint, Docker setup, Rust task runner, Node workflow, Tailwind build, or Playwright suite. The server streams from disk, emits cache validators, and can serve `.br`/`.gz` siblings when present. Plausible is the only intentional runtime script; do not add frontend runtime dependencies unless the site actually needs client-side behavior.
