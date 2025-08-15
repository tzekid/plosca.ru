# Repository Guidelines

## Project Structure & Module Organization
- `main.go`: Go Fiber HTTP server; serves files from `static_old/`, normalizes paths, and returns a simple static 404 if available.
- `static_old/`: Runtime HTML/CSS/assets served directly by Fiber.
- `go.mod`, `go.sum`: Module name and dependencies.
- `Dockerfile`, `docker-compose.yml`: Container build/run (service `ploscaru-web`).

## Build, Test, and Development Commands
- `go run ./cmd/nob run`: Run locally (defaults to `9327`).
- `go run ./cmd/nob build --os linux --arch amd64 --cgo 0 --output webapp`: Build with preset flags (edit defaults in `cmd/nob/main.go`).
- Or direct: `go run .` and `go build .`.
  - Flags: `PORT=9327 go run .`, `go run . --port 9327` or `-p 9327`.
  - Release-ish: `CGO_ENABLED=0 go build -ldflags "-s -w" -o webapp .`
- `go test ./...`: Run tests (none defined yet).
- Docker: `docker compose up --build` then open `http://localhost:9327` (maps `9327:9327`, sets `PORT=9327`).

## Coding Style & Naming Conventions
- Format with `go fmt ./...`; vet with `go vet ./...`.
- Filenames lowercase with underscores (e.g., `handlers.go`, `static_server.go`).
- Exported identifiers: PascalCase; unexported: camelCase. Prefer explicit types and small, focused functions.
- Keep HTTP logic minimal; static files live in `static_old/` and are served as-is.

## Testing Guidelines
- Place `_test.go` files next to the code. Prefer table-driven tests.
- Name tests by behavior, e.g., `TestResolveStaticFile`.
- Run with `go test ./...`. Coverage is optional; no tooling configured.

## Commit & Pull Request Guidelines
- Commits: imperative subject (≤72 chars), optional scope (`feat:`, `build:`), and rationale; reference issues (e.g., `Closes #123`).
- PRs: clear description, steps to verify (`go run .` or Docker), linked issues, and screenshots for UI/HTML changes. Note port or Docker changes.

## Security & Configuration Tips
- App reads `PORT` (default `9327`); Docker exposes `9327` and maps `9327:9327` in compose.
- Terminate TLS at a reverse proxy (Caddy/NGINX); keep this app HTTP-only.
- Do not commit secrets; review path handling to avoid traversal (see `safeFile`).
