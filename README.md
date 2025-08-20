## plosca.ru — tiny Go Fiber static site server

Minimal static site server + a tiny Go-native task runner (`nob`) for repeatable run / build / deploy workflows.

---
### 🚀 Quick Start (with `nob`)

Run (serves embedded assets on default port 9327):
- `go run ./cmd/nob run`

Choose a different port:
- `go run ./cmd/nob run --port 8080`

Build portable binary (current OS/arch):
- `go run ./cmd/nob build`

Cross-compile (example linux/amd64, static-ish):
- `go run ./cmd/nob build --os linux --arch amd64 --cgo 0 --output webapp`

One-shot pull + build + systemd restart (server side):
- `go run ./cmd/nob --pull-build-restart --service mysite.service`

Defaults (see `cmd/nob/main.go`):
- Port: 9327
- Output: `webapp`
- LDFLAGS: `-s -w`
- Service: `tzekid_website.service`

Then open: http://localhost:9327

---
### 🧪 Direct (without nob)

Run:
- `go run .`
- `PORT=8080 go run .`
- `go run . --port 8080` (or `-p 8080`)

Disk (non-embedded) mode while editing:
- `go run . --use-disk`

Build (debug):
- `go build .`

Build (smaller):
- `CGO_ENABLED=0 go build -ldflags "-s -w" -o webapp .`

---
### 🔧 Flags & Environment

Port precedence:
1. `--port` / `-p`
2. `PORT` env var
3. Default `9327`

Other flags:
- `--use-disk` — serve from filesystem instead of embedded bundle.

---
### ✨ Key Features

- Embedded assets (`go:embed`) by default (single self-contained binary)
- Optional disk mode (`--use-disk`) for live editing w/o rebuilds
- Smart path resolution:
  - `/` → `index.html`
  - `/about` → tries `about`, `about.html`, `about/index.html`
- GET & HEAD only (others 405)
- Middleware: panic recovery, structured logging, compression, ETag
- Security headers (CSP, COOP, CORP, Referrer-Policy, nosniff, Permissions-Policy)
- Custom `404.html` fallback
- Graceful shutdown on SIGINT/SIGTERM
- Traversal-safe file handling (`safeFile`)

---
### 🏗️ Project Structure

- `main.go` — server logic (embedding, middleware, graceful shutdown)
- `static_old/` — static assets root (HTML, CSS, images, etc.)
- `cmd/nob/` — helper task runner
- `Dockerfile`, `docker-compose.yml` — container tooling
- `go.mod`, `go.sum` — module metadata
- `README.md`, `AGENTS.md` — docs & notes

---
### 🐳 Docker

```
docker compose up --build
```

Then visit: http://localhost:9327

Compose maps `9327:9327` and sets `PORT=9327`.

---
### 🗺️ Roadmap / TODO

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
