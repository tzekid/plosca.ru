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

### Project Structure

- `main.go` — server logic (embedding, middleware, graceful shutdown).
- `static_old/` — static assets root (HTML, CSS, JS, images).
- `cmd/nob/` — helper command to simplify run/build.
- `Dockerfile`, `docker-compose.yml` — container tooling.
- `go.mod`, `go.sum` — module metadata.
- `README.md`, `AGENTS.md` — docs and guidelines.

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
- [ ] Add (Prometheus) metrics (status counts, latency histograms)
- [ ] Add automated tests (path traversal, candidate resolution, 404 fallback, HEAD behavior)
- [ ] Support recursive embed pattern if deeper subdirectories are added
- [ ] Optional directory-level index JSON or sitemap generator
- [ ] Configurable CSP (env or flag)
- [ ] Symlink policy review (replace with `EvalSymlinks` if needed in disk mode)
- [ ] Add CI workflow (lint + build + test)
