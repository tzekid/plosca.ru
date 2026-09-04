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

The script captures one full commit ID and exports its `site/` tree with Git.
Tracked changes must be committed; untracked and ignored files are excluded.
It compares any existing release before reuse, makes files read-only, and
serializes publishers with `.deploy.lock`. Promotion atomically switches
`current`; `previous` retains the prior distinct release. An identical redeploy
preserves that rollback target.

```text
/etc/caddy/conf.d/plosca-site/
  current -> releases/<full-commit>/
  previous -> releases/<prior-commit>/
  releases/<full-commit>/
```

Run as an account that can write the release root. To rehearse elsewhere, set
`PLOSCA_RELEASE_ROOT=/absolute/disposable/path`. The focused regression journey
runs entirely in temporary directories:

```sh
python3 tests/deploy.py
```

To roll back, use the same publication lock and atomically select `previous`:

```sh
root=/etc/caddy/conf.d/plosca-site
(
  flock 9
  test -d "$root/previous" || exit 1
  next=$(mktemp -d "$root/.rollback-XXXXXXXX")
  trap 'rm -rf -- "$next"' EXIT
  ln -s "$(readlink "$root/previous")" "$next/current"
  mv -Tf "$next/current" "$root/current"
) 9>"$root/.deploy.lock"
```

This selects the saved release without deleting either release. Caddy follows
`current` on each request, so content deployments do not need a reload. Reload
Caddy only after changing its configuration. Script/documentation changes alone
do not require republishing unchanged site content.
