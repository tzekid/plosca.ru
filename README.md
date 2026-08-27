# plosca.ru

`plosca.ru` is an authored static site. The checked-in `site/` directory is
the complete deployable website; there is no build step, template language,
application server, or generated output.

## Source layout

- `site/*.html` contains the five full-document pages.
- `site/previews/` contains the authored link-preview fragments.
- `site/archive/` contains the external-link registry and records.
- The remaining files under `site/` are the CSS, small vanilla-JavaScript
  enhancements, fonts, images, icons, PDF, and article alternates.
- `deploy/plosca.caddy` is the production Caddy site definition.
- `scripts/deploy.sh` publishes `site/` as an immutable release.

Edit files under `site/` directly. Stable asset URLs are revalidated by Caddy,
so asset hashing and generated version strings are unnecessary.

## Deployment

Deploy the committed `site/` tree with:

```sh
./scripts/deploy.sh
```

The script verifies that the deployed files exactly match `site/`, makes the
release read-only, and atomically switches the `current` symlink:

```text
/etc/caddy/conf.d/plosca-site/
  current -> releases/<commit>/
  releases/<commit>/
```

Caddy follows the symlink on each request, so content deployments do not need
a reload. Reload Caddy only after changing its configuration.
