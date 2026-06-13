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
webapp serve [--host 0.0.0.0] [--port 9327] [--static-root static]
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

### Test

```sh
zig build test
zig build
```
