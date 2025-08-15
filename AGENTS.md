# Repository Guidelines

## Project Structure & Module Organization
- `src/main.zig`: Zap-based HTTP server. Serves files from `static_old`, normalizes paths, and 404s on missing files.
- `static_old/`: Source of runtime HTML/CSS/assets (served directly).
- `markdown/`: Content drafts in Markdown (pipeline currently disabled).
- `public/`: Generated HTML experiments (not served by the app).
- `build.zig`, `build.zig.zon`: Build graph and deps (`zap` enabled; TLS off). Markdown rendering is currently disabled; add `zigdown` later if needed.
- `zig-out/`: Build artifacts.

## Build, Test, and Development Commands
- `zig build`: Compile and install to `zig-out/bin/tzekid_website`.
- `zig build run -- [args]`: Run locally; default port `9327`.
  - Override: `PORT=3000 zig build run` or `zig build run -- --port 3000`.
- `zig build -Doptimize=ReleaseFast`: Release build.
- `zig build test`: Run Zig unit tests (none defined yet).
- Docker: `docker compose up --build` and open `http://localhost:3001`.
  - Compose maps `3001:3000` and sets `PORT=3000` in the container.

## Coding Style & Naming Conventions
- Zig formatting: `zig fmt src` (4-space indent, no tabs).
- Files: `snake_case.zig` in `src/`; HTML/CSS with kebab-case filenames.
- Prefer explicit types, descriptive `const` names, and small functions.

## Testing Guidelines
- Place `test` blocks near the code under test (in the same `.zig` file).
- Name tests clearly, e.g., `test "path normalization" { ... }`.
- Run with `zig build test`. No coverage tooling is configured.

## Commit & Pull Request Guidelines
- Commits: Imperative subject (≤72 chars), optional scope (e.g., `feat:`, `build:`), and rationale in body. Reference issues (`Closes #123`).
- PRs: Clear description, steps to verify (`zig build run`), linked issues, and screenshots for UI/HTML changes. Note port or Docker adjustments.

## Security & Configuration Tips (Optional)
- TLS is disabled (`openssl = false`). Run behind Caddy/NGINX for TLS/HTTP2; on host, keep app on `9327` and let the proxy terminate TLS and forward.
- Keep secrets out of `static_old`, `public`, and repo.
- If enabling Markdown rendering, add `zigdown` as a dependency and review file path handling.
