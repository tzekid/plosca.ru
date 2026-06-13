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
- `src/main.zig`: CLI, listener, routing, static file resolution, and tests.
- `static/`: site files.
- `.github/workflows/ci.yml`: Zig format/test/build CI.

## Build, Run, and Ports

Port precedence:
1. `--port`
2. `PORT` environment variable
3. Default `9327`

Commands:
- Run: `zig build run -- serve`
- Run on another port: `zig build run -- serve --port 8080`
- Build: `zig build -Doptimize=ReleaseFast`
- Test: `zig build test`

The built binary is `zig-out/bin/webapp`.

## Routing Contract

Static routes use this candidate order:
1. exact path
2. `path.html`
3. `path/index.html`

Missing files return `static/404.html` with status `404` when available.

## Notes

There is no asset embedding, generated manifest, metrics endpoint, Docker setup, or Rust task runner in the simplified Zig version.
