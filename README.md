## plosca.ru — Go Fiber + templ

Lightweight HTTP server that serves static files from `static_old`, with simple path normalization and a minimal `templ`-based 404 page.

### Run locally

- Default: `go run .` (listens on `9327`)
- Env override: `PORT=3000 go run .`
- Flag override: `go run . --port 3000`

### Build

- Debug: `go build .`
- Release-ish: `CGO_ENABLED=0 go build -ldflags="-s -w" .`

### Docker

- `docker compose up --build` then open `http://localhost:9327`
  - Compose maps `9327:9327` and sets `PORT=9327` inside the container.

### Notes

- Only static file serving is enabled for now. `templ` is wired for the 404 page as a minimal baseline; dynamic pages can be added incrementally.
