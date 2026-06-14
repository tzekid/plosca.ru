# Tailwind CSS Migration Plan

## Goal

Migrate the static `plosca.ru` frontend from hand-written CSS to a Tailwind v4 CLI workflow while keeping the site fully static and preserving the personal, minimal, red-accented feel. The migration should allow a measured visual refresh, but must not break routes, content, analytics, fonts, mobile navigation, article/code rendering, or the disk-backed Zig deployment model.

## Current Frontend

- Static HTML pages in `static/`, served directly by the Zig server.
- One active stylesheet at `static/style.css`; `static/pandoc.css` and `static/style.20250817.min.css` are retained historical/reference assets.
- Local WOFF2 fonts: `Quando` for logo/accent text and `Quicksand` for body/UI.
- CSS-only mobile navigation driven by a checkbox and label.
- Pandoc-like article markup for `hello_world.html` and `prose.html`.
- External JavaScript is limited to Plausible analytics.

## Migration Strategy

1. Add Tailwind v4 CLI, Playwright, and screenshot tooling.
2. Capture baseline screenshots before CSS changes.
3. Create `src/styles/input.css` as the Tailwind source and generate committed `static/style.css`.
4. Rebuild styles component-first in Tailwind layers:
   - `theme`: site tokens.
   - `base`: fonts, body, links, headings, selections.
   - `components`: nav, home, articles, about page, code blocks, TOC.
   - `utilities`: small site utilities.
5. Start without Tailwind Preflight to avoid accidental reset drift.
6. Use `@tailwindcss/typography` only if it improves article rendering without losing the current personality.
7. Capture after screenshots and compare before/after artifacts.
8. Run Node, Zig, visual, and live smoke validation before deploy/push.

## Design Tokens To Preserve

- Brand red: `#d64937`.
- Text: `#444`, with secondary text around `#555`/`#666`.
- Soft red surfaces: `#fff7f6`, `#ffe9e5`, `#ffd9d3`, `#ffe3dd`.
- Fonts: `Quando`, `Quicksand`.
- Desktop article width: about `740px`.
- About page width: about `960px`.
- Mobile navigation breakpoint: `864px`.
- Logo/up-button motif: `<{ x }>` and `<{ ⇡ }>`.

## Screenshot Workflow

- Baseline artifacts: `artifacts/css-migration/before/`.
- Post-refactor artifacts: `artifacts/css-migration/after/`.
- Diff artifacts: `artifacts/css-migration/diff/`.
- Pages:
  - `/`
  - `/about`
  - `/hello_world`
  - `/prose`
  - a missing page for `404`
  - `/` with mobile nav open
- Viewports:
  - desktop `1440x1000`
  - breakpoint-plus `865x1000`
  - breakpoint `864x1000`
  - small `640x900`
  - narrow `520x900`
  - mobile `390x844`

Screenshots are local/CI artifacts and are ignored by git. The generated `static/style.css` is committed.

## Subagent Strategy

- CSS inventory agent: identify tokens, component groups, risky selectors, and dead rules.
- Migration agent: help with isolated component conversions if needed, using disjoint file ownership.
- Visual QA agent: review screenshot diffs and call out layout, readability, mobile nav, or article regressions.
- Main agent owns integration, final CSS output, validation, deployment, commit, and push.

## Acceptance Criteria

- `npm ci` succeeds.
- `npm run css:build` regenerates `static/style.css` without uncommitted drift after commit.
- `npm run test:visual` passes.
- `zig fmt --check build.zig src/main.zig` passes.
- `zig build test` passes.
- `zig build -Doptimize=ReleaseFast` passes.
- Local asset-reference audit passes.
- Live smoke verifies all main routes, CSS, missing route, `HEAD`, and `405`.
- Before/after screenshots are captured and compared; accepted visual changes are intentional.
