## plosca.ru

Static-first personal site with a Zig generator and file server. Generated
connections are included in the initial HTML response; HTMX 4 progressively
enhances on-demand link previews.

### Run

```sh
zig build run -- serve
```

Choose a port:

```sh
zig build run -- serve --port 8080
```

Build the binary:

```sh
zig build -Doptimize=ReleaseFast
```

The installed binary is written to `zig-out/bin/webapp`.

### CLI

```sh
webapp serve [--host 0.0.0.0] [--port 9327] [--static-root static] [--hsts-max-age seconds]
```

Port precedence:

1. `--port`
2. `PORT`
3. `9327`

### Routing

The server handles `GET` and `HEAD` only. Other methods return `405`.

Static lookup stays under `static/` and tries:

1. exact path
2. `path.html`
3. `path/index.html`

Missing files return `static/404.html` with status `404` when that file exists.

### Performance

The server streams files from disk instead of reading them into heap memory per request. It also sends cache validators (`ETag`, `Last-Modified`) and serves precompressed `.br` or `.gz` siblings when they exist and the client advertises support through `Accept-Encoding`.

Benchmark locally with either:

```sh
./scripts/bench.sh
```

or manually:

```sh
oha http://127.0.0.1:9327/
wrk http://127.0.0.1:9327/style.css
```

### Frontend and generation

The production site remains static HTML, CSS, and JavaScript with no Node
runtime or CSS framework. `src/site/model.zig` defines typed page and preview
models, while `src/site/views.zig` renders escaped components for both full
pages and fragments. Author CSS in `src/styles/site.css`, then generate the
served site:

```sh
zig build css
```

`zig build css` materializes generated connections into article pages, emits
preview fragments and HTMX attributes, updates content-versioned asset
references, and regenerates committed `.br` and `.gz` siblings. HTMX is
self-hosted under `static/vendor/`; `preview-controller.js` handles input,
focus, visibility, and geometry only.

Shared HTML escaping, URL validation, asset MIME detection, cache validators,
security-header construction, the per-connection HTTP loop, and the HTMX pin
come from `web.zig`. `build.zig.zon` locks that public library to an exact Git
commit and Zig package hash. The matching source is committed under `zig-pkg/`;
CI builds with `--system zig-pkg`, which disables network fetching and proves
the repository-local copy is sufficient.

To refresh only compressed siblings after manual static-file edits:

```sh
zig build compress-assets
```

Check that generated CSS, stylesheet cache-busters, and local asset references are synchronized:

```sh
zig build check-site
```

After changing `static/resume.pdf`, regenerate the committed hover-preview image before rebuilding site metadata:

```sh
zig build pdf-previews
zig build css
```

This uses `pdftoppm` from Poppler. It is only needed when refreshing PDF preview assets; normal checks and deployment use the committed JPEG.

### Link Context

External-link popovers are generated from a committed build-time cache at `src/content/link_context.json`. Refresh it after adding or changing external links:

```sh
zig build enrich-links
zig build css
```

The enrichment step uses `curl` and the network. Normal CSS generation, site checks, tests, and deployment stay offline and use the committed cache.

### Verification

```sh
zig build css
zig build check-site
zig build test
zig build -Doptimize=ReleaseFast
./scripts/smoke.sh
```

CI runs the same generated-output, formatting, unit, release-build, and HTTP
smoke gates. The smoke suite also proves that useful article context is present
in the first HTML response without a startup HTMX request.
