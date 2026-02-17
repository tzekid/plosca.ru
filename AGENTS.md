# Repository Guidelines

These guidelines describe structure, runtime modes, routing behavior, security posture, and contribution workflow for the `plosca.ru` Rust/Axum static site server.

## Overview

The production binary is `webapp`, built from this Rust crate.

Key characteristics:
- Axum-based HTTP server.
- Embedded static assets by default via `include_dir!`.
- Optional disk mode (`--assets disk` or `--use-disk`) for live iteration.
- Extensionless path resolution with `.html` and `index.html` fallbacks.
- `GET` and `HEAD` only for routed endpoints; other methods return `405`.
- Minimal security headers (`nosniff`, `Referrer-Policy`) and explicit cache policy by file type.
- Accept-aware 404 responses:
  - HTML accept -> `404.html`
  - JSON or ambiguous (`*/*`) -> `{"error":"not_found"}`

## Runtime Modes

Two mutually exclusive modes are selected at startup:

1. Embedded Mode (default)
   - Uses compile-time embedded `static_old/` assets.
   - No runtime asset directory dependency.

2. Disk Mode (`--assets disk` / `--use-disk`)
   - Serves from on-disk `static_old/`.
   - Canonical-path guard prevents traversal outside static root.

## Project Structure

- `Cargo.toml`, `Cargo.lock`: Rust crate + dependency lock.
- `src/main.rs`: `webapp` binary entrypoint.
- `src/lib.rs`: shared modules and global allocator instrumentation.
- `src/config.rs`: CLI and runtime config resolution.
- `src/server.rs`: listener setup and graceful shutdown.
- `src/routes.rs`: route registration and response behavior.
- `src/static_files.rs`: embedded/disk static resolution + cache/content-type.
- `src/stats.rs`: runtime memory stats payload (endpoint currently disabled).
- `src/error_response.rs`: 404 negotiation helpers.
- `src/bin/nob.rs`: Rust task runner.
- `nob`: root launcher wrapper for `target/release/nob`.
- `tests/server.rs`: integration tests.
- `static_old/`: static assets.
- `Dockerfile`, `docker-compose.yml`: container build/run.

## Build, Run, and Ports

Port precedence:
1. `--port`
2. `PORT` environment variable
3. Default `9327`

Commands:
- Run (embedded): `cargo run --release --bin webapp`
- Run (disk): `cargo run --release --bin webapp -- --use-disk`
- Build app: `cargo build --release --bin webapp`
- Build task runner: `cargo build --release --bin nob`
- Test: `cargo test`
- Docker: `docker compose up --build`

Task-runner commands:
- `./nob run --port 9327`
- `./nob build --output webapp`
- `./nob restart-nohup --pull --log webapp.log`
- `./nob pbr --service tzekid_website.service`
- `./nob docker --repo tzekid/plosca.ru --tag latest`

## Routing + API Contract

- `/stats` is currently disabled (code retained for later re-enable).
- Static routes: `GET`/`HEAD` catch-all with candidate order:
  1. exact path
  2. `path.html` (if extensionless)
  3. `path/index.html` (if extensionless)
- `/stats` schema:
  - `runtime: "rust/axum"`
  - `memory.rss`, `memory.heap_used`, `memory.heap_total` as `"N.NN MB"`

## Cache Policy

- Images/fonts/css: `public, max-age=31536000, immutable`
- JS: `public, max-age=86400`
- HTML: `public, max-age=0, must-revalidate, stale-while-revalidate=30`
- `/stats`: `no-store` (when enabled)

## Security Headers

- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: no-referrer-when-downgrade`

## Roadmap / Consider

- Stronger cache validators (`ETag`/`Last-Modified`) if needed.
- Optional configurable CSP policy.
- Prometheus metrics.
- CI pipeline (`fmt`, `clippy`, `test`, release build).
- Optional pre-compressed static asset serving.
