# plosca.ru

`plosca.ru` is authored as complete HTML documents plus static assets and a
small typed Zig manifest. One offline Zig compiler produces an immutable
`dist/`; Caddy serves that directory directly.

There is no production application server, HTMX runtime, client framework,
template language, or Node runtime.

## Build

The repository pins Zig in `.zigversion`.

```sh
zig build -Doptimize=ReleaseFast
zig-out/bin/sitec build
zig-out/bin/sitec check
```

The installed executable is `zig-out/bin/sitec` and intentionally exposes only
two commands:

```text
sitec build
sitec check
```

`sitec build` reads only repository files. It builds and validates
`dist.tmp/`, then atomically publishes the completed tree as `dist/`. A failed
build leaves the prior `dist/` untouched.

## Source layout

- `content/pages/` contains the five authored full-document HTML pages.
- `content/manifest.zig` contains page/site data using types from
  `src/manifest.zig`.
- `content/link-context.json` is the committed offline source for external-link
  previews.
- `assets/` contains the authoritative CSS, small vanilla-JS enhancements,
  fonts, images, icons, PDF, alternates, metadata files, and archive records.
- `src/` contains the product-specific compiler passes: graph, previews,
  assets, rendering, and validation.
- `tests/baseline/` freezes the pre-migration HTML, asset hashes, route
  behavior, and desktop/mobile screenshots.
- `dist/` is generated and ignored; never edit it manually.

The only HTML substitutions are explicit asset markers such as
`{{asset:style.css}}` and the named generated-connections region. The compiler
does not implement a general template language.

## Verification

```sh
zig build test
zig build deterministic-build -Doptimize=ReleaseFast
zig build check-site -Doptimize=ReleaseFast
```

The focused browser acceptance test uses the system Caddy and Chromium. Its
Node/Playwright dependency is test-only and is not used by a normal build or in
production:

```sh
./tests/setup-browser-e2e.sh
zig build browser-smoke -Doptimize=ReleaseFast
```

The browser gate covers theme persistence, the About timeline, native
navigation with JavaScript disabled, PDF/404 behavior, preview intent timing,
cache reuse, keyboard access, stale-request cancellation, and CSP behavior.

## Deployment

`deploy/plosca.caddy` is the production Caddy site definition. Releases are
immutable directories and `current` is an atomic symlink:

```text
/etc/caddy/conf.d/plosca-site/
  current -> releases/<commit>/
  releases/<commit>/
```

Deploy a committed revision with:

```sh
./scripts/deploy.sh
```

Set `PLOSCA_RELEASE_ROOT` to use a different Caddy-readable release root. Set
`PLOSCA_RELOAD_CADDY=1` when the installed Caddy configuration should be
validated and reloaded after the symlink switch.
