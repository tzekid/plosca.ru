## plosca.ru — tiny Go Fiber static site server

A minimal HTTP server that serves static files from `static_old/` with smart path resolution and an embedded (single-binary) default. Designed for simplicity, portability, and safe static delivery.

### Key Features

- Embedded assets (`go:embed`) by default — single self-contained binary.
- Optional disk mode (`--use-disk`) for live editing without rebuilds.
- Clean path resolution:
  - `/` → `index.html`
  - `/about` → `about`, `about.html`, or `about/index.html` (first that exists)
- GET and HEAD only (others rejected with 405).
- Middleware: panic recovery, structured logging, compression, ETag.
- Security headers (CSP, COOP, CORP, Referrer-Policy, nosniff, Permissions-Policy).
- Custom `404.html` fallback if present.
- Graceful shutdown on SIGINT/SIGTERM.
- Simple, safe file handling (`safeFile` guards traversal).

### How It Works

1. At build time, all `static_old/*` files are embedded.
2. On startup:
   - If `--use-disk` is NOT provided, the server attempts to serve from the embedded filesystem.
   - If `--use-disk` is provided (or embedding unexpectedly fails) it serves directly from the on-disk `static_old/` directory.
3. For each request:
   - The path is normalized (leading slash ensured, cleaned).
   - A candidate list is built: exact, plus `.html`, plus `index.html` under the same path if no extension was present.
   - The first candidate that exists is served.
   - If none match, a `404.html` (if present) is served with 404; otherwise a plain 404 status.

Embedded mode is immutable at runtime; disk mode lets you tweak files without rebuilding.

### Path Examples

Request -> Resolution attempts (in order):
- `/` → `index.html`
- `/about` → `about`, `about.html`, `about/index.html`
- `/blog/2024/entry` → `blog/2024/entry`, `blog/2024/entry.html`, `blog/2024/entry/index.html`

(Only the first existing non-directory file is returned.)

### Run Locally

Fast path:
- `go run .`
- `PORT=8080 go run .`
- `go run . --port 8080`
- `go run . -p 8080`
- Disk mode (skip embedding): `go run . --use-disk`

With helper (nob):
- `go run ./cmd/nob run` (defaults to port `9327`)

Open: http://localhost:9327

### Flags & Environment

Precedence for port:
1. `--port` / `-p`
2. `PORT` environment variable
3. Default `9327`

Other flags:
- `--use-disk` (bool): serve from the real filesystem instead of embedded assets.

### Build

Basic:
- `go build .`

Release-ish (smaller binary):
- `CGO_ENABLED=0 go build -ldflags "-s -w" -o webapp .`

With nob helper:
- `go run ./cmd/nob build --os linux --arch amd64 --cgo 0 --output webapp`

Adjust defaults in `cmd/nob/main.go`.

### Docker

```
docker compose up --build
```

Then visit: http://localhost:9327

Compose maps `9327:9327` and sets `PORT=9327`.

### Development: Embedded vs Disk Mode

- Default (embedded): reproducible single artifact; changes to files require rebuild.
- Disk mode (`--use-disk`): ideal for iterative frontend edits; skip rebuilds.
- To regenerate embedded assets, rebuild the binary.

### Middleware Stack

Order (as configured):
1. Recover (panic safety)
2. Logger (time / ip / method / path / status / latency)
3. Compression (Content-Encoding negotiation)
4. ETag (basic caching hint)
5. Security headers (CSP, COOP, CORP, etc.)
6. Static resolution handler (GET/HEAD)

### Security Notes

- `safeFile` prevents directory traversal when serving from disk (absolute path prefix check).
- Embedded mode inherently restricts to known-at-build files.
- CSP is conservative; expand if you need external scripts or styles.
- TLS termination should occur at an upstream reverse proxy (Caddy, NGINX, etc.).
- No secrets should live in `static_old/`.

### Custom 404

Place a `static_old/404.html` to control not-found responses. If omitted, a bare 404 is returned.

### Project Structure

- `main.go` — server logic (embedding, middleware, graceful shutdown).
- `static_old/` — static assets root (HTML, CSS, JS, images).
- `cmd/nob/` — helper command to simplify run/build.
- `Dockerfile`, `docker-compose.yml` — container tooling.
- `go.mod`, `go.sum` — module metadata.
- `README.md`, `AGENTS.md` — docs and guidelines.

### HEAD Support

Routes are explicitly registered for GET and HEAD. Fiber suppresses the body automatically for HEAD while still letting handlers set headers (content type, ETag, etc.).

### MIME Handling

- If a file has an extension, `mime.TypeByExtension` sets `Content-Type`.
- If no extension, a small heuristic attempts to classify HTML; otherwise defaults to `application/octet-stream`.
- (Future improvement: use `net/http.DetectContentType` for richer detection, especially for binary or SVG files without extensions.)

### Extending

Possible enhancements:
- Add cache-control strategies (e.g., hash-based immutable filenames).
- Pre-compress and serve `.br` / `.gz` variants.
- Add metrics (Prometheus).
- Implement directory-level redirect rules or sitemap generation.
- Add tests for path resolution and security invariants.

### Current TODO / Roadmap

Checked items are already implemented (formerly in earlier TODO list).

Implemented:
- [x] Compression middleware
- [x] Logging middleware
- [x] Graceful shutdown on signals
- [x] Embedded asset mode (default)
- [x] ETag support
- [x] Safe path handling

Still planned / optional:
- [ ] Add Last-Modified / stronger cache headers
- [ ] Switch to `net/http.DetectContentType` for richer sniffing
- [ ] Add Prometheus metrics (status counts, latency histograms)
- [ ] Add automated tests (path traversal, candidate resolution, 404 fallback, HEAD behavior)
- [ ] Support recursive embed pattern if deeper subdirectories are added
- [ ] Optional directory-level index JSON or sitemap generator
- [ ] Configurable CSP (env or flag)
- [ ] Symlink policy review (replace with `EvalSymlinks` if needed in disk mode)
- [ ] Add CI workflow (lint + build + test)

### Quick Start Summary

1. Put `index.html` into `static_old/`.
2. Run `go run .`
3. Open the port shown in logs (default 9327).
4. Add more pages (e.g., `about.html`) and access `/about`.
