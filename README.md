## plosca.ru — axum static site server

Rust/Axum rewrite of the personal site server.

### Quick Start

Run with embedded assets (default):
- `cargo run --release --bin webapp`

Run in disk mode (live-edit `static_old/`):
- `cargo run --release --bin webapp -- --assets disk`
- `cargo run --release --bin webapp -- --use-disk`

Stats endpoint:
- `curl -sS localhost:9327/stats | jq`

### CLI (`webapp`)

`webapp serve` is the explicit subcommand; running without a subcommand uses `serve` defaults.

Flags:
- `--port <u16>`: precedence is `--port`, then `PORT`, then `9327`.
- `--host <host>`: bind host, default `0.0.0.0`.
- `--assets <embedded|disk>`: default `embedded`.
- `--use-disk`: shorthand for `--assets disk`.
- `--static-dir <path>`: default `static_old`.
- `--shutdown-timeout-seconds <u64>`: default `5`.

### HTTP Behavior

- `GET /stats` and `HEAD /stats`
- Static catch-all uses extensionless fallback:
  - exact path
  - `path.html`
  - `path/index.html`
- `GET`/`HEAD` only on static and `/stats`; others return `405`
- 404 negotiation:
  - HTML accept (`text/html` / `application/xhtml+xml`) -> `404.html`
  - JSON/ambiguous accept (`application/json`, `*/*`) -> `{"error":"not_found"}`

### `/stats` JSON Schema

```json
{
  "runtime": "rust/axum",
  "memory": {
    "rss": "12.34 MB",
    "heap_used": "1.23 MB",
    "heap_total": "4.56 MB"
  }
}
```

### Cache Policy

- Images/fonts/css: `public, max-age=31536000, immutable`
- JS: `public, max-age=86400`
- HTML: `public, max-age=0, must-revalidate, stale-while-revalidate=30`
- `/stats`: `no-store`

### Security Headers (minimal baseline)

- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: no-referrer-when-downgrade`

### `nob` Task Runner

Use the root wrapper:
- `./nob run --port 9327`
- `./nob build --output webapp`
- `./nob restart-nohup --pull --log webapp.log`
- `./nob pbr --service tzekid_website.service`
- `./nob docker --repo tzekid/plosca.ru --tag latest`
- `./nob self-build --output nob.bin`

### Docker

```bash
docker compose up --build
```

Then open: <http://localhost:9327>
