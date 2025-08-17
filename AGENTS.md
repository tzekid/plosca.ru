# Repository Guidelines

These guidelines describe structure, runtime modes (embedded vs disk), coding conventions, middleware, security posture, and contribution workflow for the plosca.ru static site server.

## Overview

The binary is a minimal Go Fiber application that serves static assets under `static_old/`.

Key characteristics:
- Single-binary by default via Go `embed` (no external runtime asset directory needed).
- Optional disk mode (`--use-disk`) for live iteration without rebuild.
- Extensionless path resolution with `.html` and `index.html` fallbacks.
- GET and HEAD only; other HTTP methods yield 405.
- Lightweight but defense-in-depth: path sanitation, traversal prevention, security headers.

## Runtime Modes

There are two mutually exclusive modes selected at process start:

1. Embedded Mode (default)
   - Assets compiled into the binary with `//go:embed static_old/*`.
   - Immutable at runtime; reproducible deployments.
   - Lowest operational complexity (only ship the binary).

2. Disk Mode (`--use-disk`)
   - Serves from the on-disk `static_old/` directory.
   - Supports editing assets without recompilation (development convenience).
   - Traversal mitigated by `safeFile` (absolute prefix check).

Mode Selection Logic:
- If `--use-disk` provided -> Disk Mode.
- Else attempt `fs.Sub(embeddedFiles, "static_old")` -> if successful -> Embedded Mode.
- If embed sub-FS creation fails (unexpected) -> fallback to Disk Mode with a warning.

## Project Structure

- `main.go`          : Server (embedding, path resolution, middleware, graceful shutdown).
- `static_old/`      : Static assets (HTML, CSS, JS, images).
- `cmd/nob/`         : Helper build/run command with preset flags.
- `Dockerfile`       : Container build definition.
- `docker-compose.yml`: Local composition (maps port 9327, sets `PORT`).
- `go.mod`, `go.sum` : Module metadata and dependency checksums.
- `README.md`        : User-facing overview and usage.
- `AGENTS.md`        : This guideline document.

## Build, Run, and Ports

Port resolution precedence:
1. `--port` flag
2. `-p` short flag
3. `PORT` environment variable
4. Default `9327`

Commands:
- Run (embedded): `go run .`
- Run (disk): `go run . --use-disk`
- Run with helper: `go run ./cmd/nob run`
- Build debug: `go build .`
- Build release-ish: `CGO_ENABLED=0 go build -ldflags "-s -w" -o webapp .`
- Helper build: `go run ./cmd/nob build --os linux --arch amd64 --cgo 0 --output webapp`
- Docker: `docker compose up --build`


## Roadmap / TODO

Implemented:
- [x] Compression
- [x] Logging
- [x] Graceful shutdown
- [x] Embedded asset mode
- [x] ETag middleware
- [x] Path traversal safeguards
- [x] Extensionless + index resolution

Planned / Consider:
- [ ] Last-Modified & Cache-Control enhancements (immutable asset strategy)
- [ ] Richer MIME detection (`net/http.DetectContentType`)
- [ ] Prometheus metrics (request count, latency histogram, status classes)
- [ ] Automated tests (resolution, traversal, HEAD, 404)
- [ ] Recursive embedding if deeper directory hierarchy introduced
- [ ] Configurable CSP via env or flag
- [ ] Symlink handling policy clarity (`EvalSymlinks`)
- [ ] CI pipeline (lint, vet, test, build)
- [ ] Pre-compressed asset serving (.br, .gz)
- [ ] Optional directory listing JSON or sitemap generator
