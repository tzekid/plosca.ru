## plosca.ru — Go Fiber static server

Tiny HTTP server that serves static files from `static_old` with simple path normalization and an `.html` fallback (e.g., `/about` -> `static_old/about.html`).

### Run locally

- Recommended (nob): `go run ./cmd/nob run` (defaults to `9327`)
- Default: `go run .` (listens on `9327`)
- Optional: `PORT=9327 go run .`
- Flags: `go run . --port 9327` or `go run . -p 9327`

### Build

- Recommended (nob): `go run ./cmd/nob build --os linux --arch amd64 --cgo 0 --output webapp`
- Debug: `go build .`
- Release-ish: `CGO_ENABLED=0 go build -ldflags="-s -w" .`
  - Adjust defaults in `cmd/nob/main.go` (`defaultLdflags`, `defaultGOOS`, `defaultGOARCH`, `defaultCGO`, `defaultOutput`).

### Docker

- `docker compose up --build` then open `http://localhost:9327`
  - Compose maps `9327:9327` and sets `PORT=9327` in the container.

### Add content

- Put files in `static_old/` (e.g., `static_old/index.html`, `static_old/about.html`).
- Access `/about` (no extension) or `/about.html` — both work.

### Project structure

- `main.go`: Fiber server — GET/HEAD only, static files.
- `static_old/`: HTML/CSS/JS/assets served as-is.
- `Dockerfile`, `docker-compose.yml`: Container build/run (port `9327`).
- `go.mod`, `go.sum`: Go module and dependencies.
