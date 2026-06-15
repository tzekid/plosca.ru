## plosca.ru

Minimal Zig static file server for the files in `static/`.

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

### Frontend CSS

The frontend remains static HTML with no Node, npm, CSS framework, or browser-test dependency in the committed build path. Author CSS in `src/styles/site.css`, then generate the served stylesheet and update the `?v=` stylesheet query in static HTML files:

```sh
zig build css
```

`zig build css` also regenerates committed `.br` and `.gz` siblings for text static assets so the Zig server can serve precompressed responses. To refresh only compressed siblings after manual static-file edits:

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

### Test

```sh
zig build css
zig build check-site
zig build test
zig build -Doptimize=ReleaseFast
./scripts/smoke.sh
```

To smoke an existing deployment instead of starting a temporary local server:

```sh
PLOSCA_BASE_URL=https://plosca.ru ./scripts/smoke.sh
```
