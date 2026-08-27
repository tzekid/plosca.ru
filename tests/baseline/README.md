# Pre-compiler baseline

This directory freezes the committed site at tag
`static-compiler-baseline-2026-08-27` (`7c560e49989c44a69a28b1074b091b62605f379b`).

## Scope

- `routes.tsv` records navigable pages, public alternate representations,
  downloads, metadata documents, and first-party assets. Internal generated
  HTMX fragment URLs are represented by the HTML fixtures but are not stable
  public routes; the static compiler replaces them with `/previews/*`.
- `html/` is a byte-for-byte copy of every uncompressed HTML response source
  under the former `static/` tree, including generated connection and preview
  fragments.
- `preserved-assets.sha256` records the authored or preserved inputs that must
  survive the migration.
- `html.sha256` and `screenshots.sha256` make fixture drift explicit.
- `screenshots/` contains full-page light-theme captures at 1440x900 and
  390x844. It covers the five authored pages, the archive index, and all nine
  archived-link pages.

Compressed `.br` and `.gz` siblings are deliberately excluded. They were
generated deployment artifacts, not source material.

## Recorded behavior

The baseline was exercised locally with the repository-pinned Zig
`0.17.0-dev.1509+bb296ab9b` and Chromium:

- `zig build check-site`, `zig build test`, and an optimized build passed;
- light is selected when the system preference is light, the toggle switches
  to dark, and the choice survives a same-session reload;
- the first About experience item starts open, and opening the second closes
  the first (`[true,false,false,false,false]` to
  `[false,true,false,false,false]`);
- pointer previews honor the intent delay, remain open while hovered, close
  after the grace period, switch without stale content, and dismiss on outside
  click;
- keyboard focus opens previews, while JavaScript-disabled navigation remains
  usable;
- `/resume.pdf` returns a non-empty `application/pdf` response and its About
  link retains the `download` attribute;
- an unknown route returns the authored 404 document with status 404;
- the historical server edge `/archive` returns the archive index with status
  200, while `/archive/` returns the authored 404 with status 404.

The capture deliberately blocked the external analytics origin; analytics has
no visible effect on these fixtures.
