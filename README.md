## plosca.ru — embedded static site server

This repo builds a single self-contained Rust/Axum binary that serves the site from compile-time embedded assets in `static/`.

### Quick Start

Run locally:
- `cargo run --release --bin webapp -- serve`

Choose a different port:
- `cargo run --release --bin webapp -- serve --port 8080`

### Runtime Model

- Production path is embedded-only. There is no disk asset mode.
- Assets are compiled into a generated manifest with:
  - content type
  - cache policy
  - strong ETags
  - Brotli and gzip variants for compressible files
  - hashed immutable subresource URLs for CSS, manifest, and image assets
- Static catch-all uses extensionless fallback:
  - exact path
  - `path.html`
  - `path/index.html`

### HTTP Surface

- Site routes: `GET` and `HEAD` only
- Operational endpoints:
  - `/healthz`
  - `/readyz`
- `/metrics`
- Missing pages return the embedded `404.html` page with status `404`
- Conditional requests use `ETag` / `If-None-Match`
- Metrics are opt-in at runtime via `--enable-metrics`

### Security Headers

- `Content-Security-Policy`
- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy`
- `Cross-Origin-Resource-Policy: same-origin`
- Optional `Strict-Transport-Security` via `--hsts-max-age`

### CLI (`webapp`)

Use the explicit `serve` command:
- `webapp serve --port 9327`
- `webapp serve --host 0.0.0.0`
- `webapp serve --shutdown-timeout-seconds 5`
- `webapp serve --hsts-max-age 31536000`
- `webapp serve --enable-metrics`

Port precedence:
1. `--port`
2. `PORT`
3. `9327`

### `nob` Workflow

Use the root wrapper:
- `./nob check`
- `./nob run --port 9327`
- `./nob build`
- `./nob package`
- `./nob daemon restart --build --port 9327`
- `./nob daemon status`
- `./nob daemon logs --follow`
- `./nob service restart --service tzekid_website.service`
- `./nob service status --service tzekid_website.service`
- `./nob service logs --service tzekid_website.service --follow`
- `./nob print-unit --service tzekid_website.service`

Production deploy on the Linux VPS checkout:
- `./nob daemon restart --build --port 9327`

That flow builds the Linux binary on-host, restarts the background process, and runs a smoke check against `/healthz` and `/`. Do not copy locally built binaries from macOS into production.

### CI

CI runs:
- `cargo fmt --check`
- `cargo clippy --all-targets -- -D warnings`
- `cargo test`
- `cargo build --release --bin webapp`
