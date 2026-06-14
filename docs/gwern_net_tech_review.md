# Gwern.net Tech Review And Transferable Feature Notes

Review date: 2026-06-14 UTC

Source snapshot: `gwern/gwern.net@075c69a321c44a84b582af6967f6a40a6507a6e9`

Local source clone used for this review: `/home/kid/Projects/gwern.net-source`

## Implementation Tracker

Goal started: 2026-06-14 UTC

Tracking rule: each item below is planned, implemented, verified, committed, pushed, and published before moving to the next coherent slice. "Published" means the disk-backed production site has the updated static files or, for server/build changes, the deployed binary/process has been refreshed and live-smoked.

Scope note: large Gwern.net features are implemented in a `plosca.ru`-scaled form: static-first, Zig-build-generated where possible, and minimal first-party JavaScript only where the feature needs runtime behavior. Local external-link archiving will not commit third-party page copies into this repo; the implementation should preserve link metadata and local recovery pages without importing copyrighted external content.

| Item | Scope | Status | Implementation notes | Verification | Commit / publish |
| --- | --- | --- | --- | --- | --- |
| Article metadata manifest | quick win | pending | Add a small source-of-truth page manifest for title, route, description, date, tags, and related links. | `zig build check-site`, generated output diff | pending |
| Content quality checks | quick win | pending | Extend `zig build check-site` with title/description, IDs, duplicate IDs, empty anchors, and metadata checks. | `zig build check-site` | pending |
| Heading self-links | quick win | pending | Add accessible heading permalink affordances without requiring JS. | screenshot/smoke, `zig build check-site` | pending |
| Better 404 recovery | quick win | pending | Improve 404 with route recovery links and page-specific copy. | local and deployed missing-route smoke | pending |
| Article related links | quick win | pending | Add small related/connection blocks to article pages. | `zig build check-site`, visual smoke | pending |
| Keep theme simple | quick win | pending | Preserve current session-lifetime theme implementation and document it as intentionally not Gwern-toolbar-style. | `zig build check-site`, theme smoke | pending |
| Generated backlinks | medium | pending | Generate local backlink snippets from static HTML links. | generated snippet checks | pending |
| CSS-only sidenotes | medium | pending | Add footnote/sidenote styles that degrade to normal footnotes. | visual smoke in article pages | pending |
| Native collapses | medium | pending | Add styled `<details>` support for future appendices/code output. | visual smoke and keyboard behavior | pending |
| Markdown/text alternates | medium | pending | Generate or serve text/Markdown alternates for article pages. | curl alternate files and check-site references | pending |
| Link-type markers | medium | pending | Add unobtrusive external/PDF/archive markers. | visual smoke and contrast check | pending |
| Annotation DB and previews | large | pending | Generate a small annotation database and first-party hover/focus previews. | JS/no-JS smoke, asset check | pending |
| Client-side transclusion | large | pending | Add a minimal fragment transclusion utility with no required dependency. | transclusion fragment smoke | pending |
| Similar-link generation | large | pending | Generate similar links from metadata/body terms. | deterministic generated output check | pending |
| Local external-link archive registry | large | pending | Generate local archive metadata/recovery pages without committing external page copies. | archive page/link checks | pending |

Primary live sources:

- [gwern.net/about](https://gwern.net/about)
- [gwern.net/design](https://gwern.net/design)
- [gwern.net/style-guide](https://gwern.net/style-guide)
- [github.com/gwern/gwern.net](https://github.com/gwern/gwern.net)

The source repo reviewed here is an infrastructure repo, not a full content dump. Its Cabal package describes itself as the internal build and maintenance tools and says it does not include the website content. Source: [`build/gwernnet.cabal`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/gwernnet.cabal#L1-L10).

## Executive Summary

Gwern.net is best understood as a long-lived research library, not a conventional blog. The live About page frames the site around stable essays that improve over time, long-term preservation, open formats, textual source, static output, git, backups, and local archives. Source: [gwern.net/about](https://gwern.net/about).

Technically, Gwern.net is a static site with a large compile-time and deploy-time toolchain. Hakyll and Pandoc compile Markdown to extensionless HTML, custom Haskell passes rewrite links and metadata, PHP assembles versioned CSS and JS bundles, shell scripts run a broad lint/build/sync pipeline, and nginx handles serving, redirects, server-side includes, cache policy, custom MIME types, Markdown negotiation, and 404 handling. Sources: [`build/app/hakyll.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/app/hakyll.hs#L69-L214), [`build/build_unified_assets.php`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/build_unified_assets.php#L11-L130), [`build/sync.sh`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/sync.sh#L1-L30), [`nginx/gwern.net.conf`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/nginx/gwern.net.conf#L64-L235).

The front end is vanilla JavaScript, but not simple JavaScript. It implements a client-side reading environment: annotated link popups and mobile popovers, transclusion, collapsible blocks, sidenotes, image focus and slideshow behavior, reader mode, dark mode, tablesorting, local page/source previews, and a 404 URL suggester. The live About page explicitly warns that these features require JavaScript. Sources: [gwern.net/about](https://gwern.net/about), [gwern.net/design](https://gwern.net/design), [`js/popups.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/popups.js#L12-L180), [`js/transclude.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/transclude.js#L8-L80), [`js/sidenotes.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/sidenotes.js#L1-L72).

For `plosca.ru`, the right lesson is not to clone Gwern.net. The right lesson is to borrow a few small, static-first affordances: better metadata, related/backlink snippets for the small number of pages, a stronger 404, stricter content checks, optional heading self-links, and restrained link previews if the site accumulates more writing. The larger systems are impressive, but their maintenance burden is tuned for a decades-old research corpus rather than a compact personal site.

## Source Snapshot And Methodology

Source clone command target:

```text
/home/kid/Projects/gwern.net-source
```

Source commit:

```text
075c69a321c44a84b582af6967f6a40a6507a6e9
```

Review method:

- Live pages were used for intent, public feature descriptions, and no-JS behavior: [About](https://gwern.net/about), [Design](https://gwern.net/design), and [Manual of Style](https://gwern.net/style-guide).
- The public source repo was used for implementation claims. The main source directories reviewed were `build/`, `js/`, `css/`, `template/`, `include/`, and `nginx/`.
- The unofficial documentation repo was not used as an authority for claims in this file. The claims below are backed by live pages or the source repo snapshot.

## Architecture Map

### Content And Compilation

Gwern.net compiles Markdown with Hakyll and Pandoc. The Hakyll entrypoint reads annotation metadata and archive metadata, writes missing annotation fragments, runs tests in slow mode, writes an ID-to-URL database, compiles Markdown targets, routes pages extensionlessly, validates YAML metadata, applies a Pandoc transform, renders through `static/template/default.html`, and adds image dimensions after template rendering. Source: [`build/app/hakyll.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/app/hakyll.hs#L69-L128).

The Hakyll writer uses section divs, a generated table of contents, TOC depth 4, 130-column writer output, MathJax direct output, and a custom template that inserts the TOC and wraps the body in `#markdownBody`. Source: [`build/app/hakyll.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/app/hakyll.hs#L190-L208).

The build package exposes a broad set of modules for annotations, archiving, backlinks, link icons, similar links, typography, tags, image processing, inflation adjustment, and metadata checks. It also defines maintenance executables such as `generateBacklinks`, `generateSimilarLinks`, `checkMetadata`, `linkTitler`, `redirectGuesser`, `linkSuggester`, and `linkExtractor`. Source: [`build/gwernnet.cabal`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/gwernnet.cabal#L71-L190).

### Templates And Page Shell

The default HTML template includes inlined head content through server-side includes, emits generator and repository metadata, defines canonical and Markdown alternate links, places page metadata such as tags, description, author, dates, status, confidence, importance, backlinks, similar links, and bibliography links near the page head, and includes lazy footer links to backlink, similar, and bibliography snippets. Source: [`template/default.html`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/template/default.html#L7-L184).

The template has a no-JS warning path and no-JS footer path. This matches the live About page warning that core reading features require JavaScript while the core document content remains HTML. Sources: [`template/default.html`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/template/default.html#L89-L158), [gwern.net/about](https://gwern.net/about).

### Asset Pipeline

CSS and JS are assembled in two stages: an initial head bundle and a main page bundle. `build_unified_assets.php` concatenates initial CSS, initial JS, main CSS, main JS, and transclusion templates into generated files. Source: [`build/build_unified_assets.php`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/build_unified_assets.php#L11-L130).

The head include builder inlines light and dark color CSS, links the generated head CSS/JS, and preloads the icon sprite. Source: [`build/build_head_includes.php`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/build_head_includes.php#L31-L89).

Asset versions are generated from file mtimes and written into a JS lookup or versioned CSS outputs. Sources: [`build/build_asset_versions.php`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/build_asset_versions.php#L10-L50), [`build/version_asset_links.php`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/version_asset_links.php#L18-L32).

### Runtime JavaScript

The runtime code is vanilla JS, organized as modules in `js/` and later concatenated. The main runtime bundle includes popups, popovers, annotations, content loading, transclusion, extract options and loaders, typography, hyphenation loader, rewrite logic, collapses, sidenotes, image focus, dark mode, and reader mode. Source: [`build/build_unified_assets.php`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/build_unified_assets.php#L40-L61).

The runtime is event-heavy. Modules communicate through global objects and a notification center pattern. For example, popups fire setup and cleanup events, extracts choose Popups or Popovers based on viewport/mobile conditions, and content loaders fire load success/failure events. Sources: [`js/popups.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/popups.js#L58-L141), [`js/extracts.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/extracts.js#L176-L220), [`js/content.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/content.js#L101-L176).

### Server And Deployment

Gwern.net serves with nginx. The config handles wildcard host redirects, canonical host enforcement, extensionless content, a custom Markdown response path when clients ask for Markdown and a sibling `.md` exists, custom MIME types, UTF-8 charset policy, long immutable caching, server-side includes, local archive handling, redirect rewrites, and noindex headers for metadata/archive paths. Source: [`nginx/gwern.net.conf`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/nginx/gwern.net.conf#L14-L235).

The nginx config explicitly documents a deliberate decision not to add the standard security header kit because the site has no login, no cookie-backed sessions, no state-changing actions, and wants to remain embeddable for some reading workflows. This is a different threat model from many modern web apps. Source: [`nginx/gwern.net.conf`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/nginx/gwern.net.conf#L121-L133).

The deploy script checks a large dependency list, cleans generated state, applies content rewrite cleanups, compiles the Hakyll binary, runs metadata and link checks, generates artifacts, uploads, and performs cache expiration. Source: [`build/sync.sh`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/sync.sh#L1-L30), [`build/sync.sh`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/sync.sh#L111-L220).

## Feature Catalog

### Long-Form Content Model

Gwern.net optimizes for durable, revisable essays rather than a chronological feed. The About page emphasizes long-lived essays, preservation, staticness, open standards, textual human readability, git, backups, and archived external links. Source: [gwern.net/about](https://gwern.net/about).

Transfer value for `plosca.ru`: quick win. A tiny metadata block per article plus a small index of modified dates would fit the current site without changing the server.

### Writing And Linting Process

The public About page describes a writing checklist and Markdown checker workflow. The source includes `markdown-lint.sh`, which checks URL hygiene, syntax mistakes, metadata length, missing metadata, syntax highlighting classes, footnote length, rendered HTML output, duplicate links, and special syntax leakage. Sources: [gwern.net/about](https://gwern.net/about), [`build/markdown-lint.sh`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/markdown-lint.sh#L1-L132).

Transfer value for `plosca.ru`: quick win. A small Zig or shell content checker for local links, titles, descriptions, heading IDs, and CSS references would be much cheaper than copying the full Gwern lint matrix.

### Annotation Popups And Popovers

Gwern.net marks annotated links and loads annotation fragments from `/metadata/annotation/...`. Desktop uses popup frames; mobile and constrained screens use popovers. The extraction layer chooses the provider based on mobile and viewport conditions, then attaches targets, indicator hooks, and annotation/content load events. Sources: [`js/annotations.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/annotations.js#L1-L105), [`js/extracts.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/extracts.js#L106-L220), [`js/popups.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/popups.js#L12-L180).

Transfer value for `plosca.ru`: medium for simple internal previews; large for full Gwern-style annotations. For this site, a static internal page preview for local article links would be enough if more articles appear.

### Local Page, PDF, And Source Previews

The live Design page lists local pages, PDFs, and source code previews as part of the popup/popover system. The source supports cached content loading by content type and JS-driven content fetches for links. Sources: [gwern.net/design](https://gwern.net/design), [`js/content.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/content.js#L1-L176).

Transfer value for `plosca.ru`: avoid for now. The current site has too few documents for a preview subsystem to pay for itself.

### Client-Side Transclusion

Gwern.net supports include links that replace themselves with content from another document or a fragment of another document. It has options for annotation transclusion, strict or lazy loading, collapsed-block behavior, unwrapping, block context, localization of headings and footnotes, and spinners. Source: [`js/transclude.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/transclude.js#L8-L220).

Transfer value for `plosca.ru`: avoid unless the site becomes a dense notebook. Static includes at build time would be simpler and more robust.

### Collapsible Sections

Collapsible blocks are managed by a JS subsystem that tracks hover behavior, saved interaction counts, nested collapses, reveal-on-target behavior, and change events. Source: [`js/collapse.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/collapse.js#L1-L180).

Transfer value for `plosca.ru`: medium. Native `<details>` blocks with custom CSS would capture most of the value without the JS subsystem.

### Sidenotes And Margin Notes

Gwern.net converts Pandoc-style footnotes into dynamically positioned sidenotes at wide viewports. The JS handles margin columns, viewport breakpoints, overlapping full-width media, margin note constraints, targeted note highlighting, and resize/reflow behavior. Source: [`js/sidenotes.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/sidenotes.js#L1-L180).

Transfer value for `plosca.ru`: medium. A CSS-only footnote/sidenote treatment could be attractive for essays, but the full dynamic collision-avoidance system is too much.

### Backlinks, Similar Links, And Bibliography Snippets

Backlinks are generated from forward links and written as metadata snippets. Similar links use embedding-like lookup and seriation logic. The default template exposes backlink, similar, and bibliography links in page metadata and lazy footer sections. Sources: [`build/LinkBacklink.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/LinkBacklink.hs#L1-L118), [`build/GenerateSimilar.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/GenerateSimilar.hs#L5-L220), [`template/default.html`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/template/default.html#L119-L158).

Transfer value for `plosca.ru`: quick win for hand-authored related links; medium for generated backlinks once there are enough pages.

### Reader Mode

Reader mode can be automatic, forced on, or forced off. It masks links in paragraphs, adjusts popup delay, injects a toolbar selector, stores preference in localStorage, and can deactivate near specific sections such as appendices/navigation/footer. Source: [`js/reader-mode.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/reader-mode.js#L1-L220).

Transfer value for `plosca.ru`: avoid for now. The current editorial design is already sparse; adding reader mode would duplicate the default reading experience.

### Dark Mode

Dark mode has an early script to avoid flashes, uses media attribute switching for dark-mode CSS and dark favicons, supports auto/light/dark selection, persists user selection in localStorage, and can be controlled by a toolbar widget. Images are handled specially through classes such as `.invert-auto` and `.invert`. Sources: [`js/dark-mode-initial.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/dark-mode-initial.js#L1-L137), [`js/dark-mode.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/dark-mode.js#L1-L287).

Transfer value for `plosca.ru`: already borrowed in simpler form. The current `plosca.ru` session-lifetime toggle is much more appropriate than Gwern.net's full toolbar selector.

### Image Focus, Zoom, And Slideshows

Image focus creates an overlay, adds keyboard and click controls, marks focusable and gallery images, preloads full-size images on hover, shows captions, and supports a slideshow-style navigation UI. Source: [`js/image-focus.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/image-focus.js#L1-L220).

Transfer value for `plosca.ru`: avoid until the site has image-heavy pages.

### Tablesorting And Wide Tables

The live Design page lists sortable tables and full-width table handling. CSS sections in `default.css` dedicate substantial styling to tables, and runtime bundling includes `tablesorter.js` through generated assets. Sources: [gwern.net/design](https://gwern.net/design), [`css/default.css`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/css/default.css#L1839-L2117), [`build/build_unified_assets.php`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/build_unified_assets.php#L40-L61).

Transfer value for `plosca.ru`: avoid for now.

### Inflation And Bitcoin Adjustments

Gwern.net can rewrite dollar and Bitcoin values during Pandoc transforms, using inflation and BTC exchange data. Source: [`build/Inflation.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/Inflation.hs#L10-L43), [`build/Inflation.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/Inflation.hs#L115-L200).

Transfer value for `plosca.ru`: avoid. It is a great fit for research writing with historical money values, not for a small profile/blog site.

### Link Icons And Link Indicators

Gwern.net uses CSS and generated link metadata to show compact indicators for annotated links and icons for file types, domains, source types, and other inferred link properties. The links CSS documents the reasoning: icons add compact context without interrupting prose. Sources: [`css/links.css`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/css/links.css#L1-L118), [`css/links.css`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/css/links.css#L128-L220).

Transfer value for `plosca.ru`: medium. A tiny PDF/external-link marker could be useful, but a domain icon library is not worth it.

### Admonitions, Dropcaps, Typography, And Syntax Highlighting

The live Design page lists admonitions, dropcaps, syntax highlighting, and LaTeX handling as part of the feature set. The source CSS has dedicated sections for admonitions, code blocks, dropcaps, sidenotes, popframes, popups, and reader mode, while the Hakyll writer settings show MathJax output for math where the generated page needs it. Sources: [gwern.net/design](https://gwern.net/design), [`css/default.css`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/css/default.css#L1734-L1838), [`css/default.css`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/css/default.css#L2118-L2577), [`css/default.css`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/css/default.css#L2578-L3040), [`build/app/hakyll.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/app/hakyll.hs#L190-L199).

Transfer value for `plosca.ru`: quick win for simple callout/admonition CSS if articles need it; avoid dropcaps unless the site moves toward long essays.

### Local Archives And Link-Rot Defense

Gwern.net can preemptively mirror many external links and rewrite them to local archived copies while preserving the original URL in metadata. The implementation walks the Pandoc AST, uses archive metadata, applies whitelists and delays, stores archives under `/doc/www/`, marks them to reduce indexing, and integrates with popup metadata. Source: [`build/LinkArchive.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/LinkArchive.hs#L1-L100).

Transfer value for `plosca.ru`: avoid. This is one of Gwern.net's most valuable systems for Gwern.net, but it is disproportionate for this repo.

### 404 URL Suggestions

Gwern.net's 404 script fetches the sitemap, calculates bounded Levenshtein distances against URL paths, and injects up to 10 suggested URLs. The script documents the bandwidth and performance tradeoff for a large sitemap. Source: [`js/404-guesser.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/404-guesser.js#L1-L74), [`js/404-guesser.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/404-guesser.js#L76-L220).

Transfer value for `plosca.ru`: quick win in a simpler form. A static list of known routes with a tiny JS-free 404 recovery section is enough; URL suggestions can wait until there are many pages.

### Markdown Negotiation For Agents

The nginx config can serve Markdown when the client asks for Markdown and a sibling `.md` file exists. The config comments frame this as useful for LLM browsers because Markdown can be more compact and semantic than compiled HTML. Source: [`nginx/gwern.net.conf`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/nginx/gwern.net.conf#L14-L34), [`nginx/gwern.net.conf`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/nginx/gwern.net.conf#L95-L108).

Transfer value for `plosca.ru`: medium. This would require keeping Markdown sources or generated text equivalents in `static/`; it is attractive if the site starts publishing essays.

## Progressive Enhancement Behavior

Without JavaScript, Gwern.net still serves static HTML content, canonical metadata, and links. The site also emits a no-JS warning because annotation popups/popovers, transclusions, collapses, backlinks UI, tablesorting, image zooming, and sidenotes require JS. Sources: [gwern.net/about](https://gwern.net/about), [`template/default.html`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/template/default.html#L89-L158).

The enhancement layer is not cosmetic only. Some features are reading infrastructure: popups expose annotation metadata, transclusion inserts remote fragments, collapses reveal hidden blocks, sidenotes reposition footnotes, and reader mode changes link visibility. Sources: [`js/annotations.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/annotations.js#L142-L185), [`js/transclude.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/transclude.js#L8-L80), [`js/collapse.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/collapse.js#L46-L107), [`js/sidenotes.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/sidenotes.js#L59-L83), [`js/reader-mode.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/reader-mode.js#L60-L133).

For `plosca.ru`, the better default is stricter: content should read cleanly with no JS, and JS should remain optional for small conveniences such as the current theme toggle.

## Performance And Accessibility Tradeoffs

Strengths:

- Static HTML output and immutable assets are fast to serve. Sources: [`build/app/hakyll.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/app/hakyll.hs#L129-L188), [`nginx/gwern.net.conf`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/nginx/gwern.net.conf#L213-L235).
- Early dark-mode handling reduces theme flash by applying saved media behavior before the rest of the dark-mode UI. Source: [`js/dark-mode-initial.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/dark-mode-initial.js#L1-L137).
- Content remains linkable and stable through extensionless routes, generated anchors, and metadata sections. Sources: [`build/app/hakyll.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/app/hakyll.hs#L112-L128), [`template/default.html`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/template/default.html#L119-L158).
- The lint and sync pipeline catches many quality issues before publishing. Sources: [`build/markdown-lint.sh`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/markdown-lint.sh#L17-L132), [`build/sync.sh`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/sync.sh#L111-L220).

Costs:

- The static build has many runtime dependencies and build steps. The sync script lists tools across Haskell, PHP, Node, image/video/PDF processing, browser automation, and link checking. Source: [`build/sync.sh`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/sync.sh#L14-L30).
- The JS runtime is large because it implements a document reader, not just decorations. Source: [`build/build_unified_assets.php`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/build_unified_assets.php#L40-L61).
- Some feature value requires JavaScript. Gwern.net is transparent about this through a no-JS warning. Sources: [gwern.net/about](https://gwern.net/about), [`template/default.html`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/template/default.html#L89-L104).
- Local archives and generated metadata are maintenance multipliers. They are valuable for a large research site but create operational and legal/social surface area. Source: [`build/LinkArchive.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/LinkArchive.hs#L50-L100).

## Transferable Ideas For `plosca.ru`

### Quick Wins

- `quick win`: Add optional article metadata fields to the static HTML or a small source manifest: title, date, description, tags, updated date, and related links. This borrows the useful page metadata idea without Hakyll. Sources: [`template/default.html`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/template/default.html#L119-L158), [gwern.net/about](https://gwern.net/about).
- `quick win`: Extend `zig build check-site` with content checks for title length, description presence, heading IDs, duplicate local links, missing images, and stale CSS/script references. Source inspiration: [`build/markdown-lint.sh`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/markdown-lint.sh#L17-L132).
- `quick win`: Add heading self-links that appear on hover/focus. Gwern.net uses heading affordances to support stable section links. Source: [`css/default.css`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/css/default.css#L110-L180).
- `quick win`: Improve the 404 page with better copy, a home/about/article link set, and maybe a static route list. Source inspiration: [`js/404-guesser.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/404-guesser.js#L1-L74).
- `quick win`: Add a small "related" block at the end of article pages. Hand-authored is enough today; generated backlinks can wait. Source inspiration: [`template/default.html`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/template/default.html#L137-L158).
- `quick win`: Keep the current theme implementation simple. Gwern.net's early dark-mode script confirms the value of reducing flash, but `plosca.ru` does not need a full toolbar selector. Sources: [`js/dark-mode-initial.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/dark-mode-initial.js#L1-L137), [`js/dark-mode.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/dark-mode.js#L87-L171).

### Medium Scope

- `medium`: Generate backlinks from local HTML links once there are enough pages. A simple Zig scanner can build `docs` or `static` snippets without a Haskell graph system. Source inspiration: [`build/LinkBacklink.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/LinkBacklink.hs#L1-L118).
- `medium`: Add CSS-only or near-CSS-only sidenotes for essays with footnotes. Avoid dynamic collision logic until the content proves the need. Source inspiration: [`js/sidenotes.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/sidenotes.js#L1-L72).
- `medium`: Add native `<details>`-based collapses for long article appendices or code output. This preserves progressive enhancement better than a custom collapse state machine. Source inspiration: [`js/collapse.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/collapse.js#L46-L107).
- `medium`: Serve Markdown/text alternates for article pages if the writing source becomes Markdown. This is useful for agents and text readers, but it requires a source-content flow. Source inspiration: [`nginx/gwern.net.conf`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/nginx/gwern.net.conf#L14-L34).
- `medium`: Add very small link-type markers for PDFs or external links. Avoid maintaining a large icon taxonomy. Source inspiration: [`css/links.css`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/css/links.css#L82-L118).

### Large Scope

- `large`: Build a full annotated-link database with generated fragments and hover previews. This requires metadata ingestion, URL classification, generated HTML snippets, JS loaders, cache behavior, and design work. Sources: [`build/LinkMetadata.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/LinkMetadata.hs#L1-L114), [`js/annotations.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/annotations.js#L96-L185).
- `large`: Add client-side transclusion. This needs fragment addressing, fetch/caching, rewrite hooks, footnote/heading localization, loading states, and error behavior. Source: [`js/transclude.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/transclude.js#L8-L220).
- `large`: Add automatic similar-link generation. Gwern.net uses a dedicated similarity and seriation pipeline; a small site would need enough content to make this useful. Source: [`build/GenerateSimilar.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/GenerateSimilar.hs#L5-L220).
- `large`: Add local external-link archiving. This is a preservation system, not a cosmetic feature. Source: [`build/LinkArchive.hs`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/LinkArchive.hs#L1-L100).

### Avoid

- `avoid`: Rebuilding `plosca.ru` around Hakyll/Pandoc just to match Gwern.net. The current Zig-only workflow is deliberately small, and Gwern.net's toolchain is scaled to a large research corpus. Sources: [`build/gwernnet.cabal`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/gwernnet.cabal#L18-L65), [`build/sync.sh`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/sync.sh#L14-L30).
- `avoid`: Copying Gwern.net's popup/transclusion stack wholesale. It is carefully engineered, but it is also many modules and CSS sections. Sources: [`build/build_unified_assets.php`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/build/build_unified_assets.php#L40-L61), [`css/default.css`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/css/default.css#L4019-L4412).
- `avoid`: Adding reader mode. The current design already behaves like a reader mode. Source: [`js/reader-mode.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/reader-mode.js#L1-L133).
- `avoid`: Adding image zoom/slideshows before there are image-heavy pages. Source: [`js/image-focus.js`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/js/image-focus.js#L67-L220).
- `avoid`: Copying the nginx security-header posture. Gwern.net's rationale is specific to a cookie-free, login-free, embeddable document site. `plosca.ru` already has a simpler server and can keep conservative headers unless they break a real feature. Source: [`nginx/gwern.net.conf`](https://github.com/gwern/gwern.net/blob/075c69a321c44a84b582af6967f6a40a6507a6e9/nginx/gwern.net.conf#L121-L133).

## Suggested `plosca.ru` Roadmap

1. Add a `zig build check-content` or extend `zig build check-site`.
   Scope: local links, required titles/descriptions, heading IDs, missing assets, duplicate IDs, bad empty anchors, and article metadata.
   Category: `quick win`.

2. Improve `404.html`.
   Scope: short explanation, home/about/resume/article links, and a visible recovery block.
   Category: `quick win`.

3. Add article metadata and related links.
   Scope: small front-matter-like JSON/Zig manifest or hand-authored HTML blocks, then render consistently in article pages.
   Category: `quick win`.

4. Add heading self-link affordances.
   Scope: CSS hover/focus pilcrow or hash link, no runtime JS required.
   Category: `quick win`.

5. Add generated backlinks only after the page count grows.
   Scope: scan static HTML for internal links and write a small `backlinks.json` or generated HTML snippet.
   Category: `medium`.

6. Consider CSS-only sidenotes if future writing needs footnotes.
   Scope: first pass should be static and responsive; do not implement Gwern.net's dynamic collision system.
   Category: `medium`.

## Appendix: Source File Map

Build and content pipeline:

- `build/app/hakyll.hs`: Hakyll/Pandoc compile entrypoint, route handling, metadata checks, template application, image dimension pass.
- `build/gwernnet.cabal`: Haskell package manifest, dependencies, modules, and maintenance executables.
- `build/LinkMetadata.hs`: annotation metadata processing and link annotation generation.
- `build/LinkBacklink.hs`: backlink, similar-link, and link-bibliography snippet naming and generation helpers.
- `build/GenerateSimilar.hs`: similar-link lookup and seriation.
- `build/LinkArchive.hs`: local external-link archive/mirror pipeline.
- `build/Inflation.hs`: inflation and BTC adjustment transform.
- `build/markdown-lint.sh`: Markdown and rendered-output content lint.
- `build/sync.sh`: full build, check, and deploy script.
- `build/build_unified_assets.php`: generated CSS/JS bundle assembly.
- `build/build_head_includes.php`: inline head include generation.
- `build/build_asset_versions.php` and `build/version_asset_links.php`: generated asset version data.

Runtime:

- `js/popups.js`: desktop popup frame engine.
- `js/popovers.js`: mobile/constrained popover engine.
- `js/extracts.js`, `js/extracts-annotations.js`, `js/extracts-content.js`, `js/extracts-options.js`, `js/extracts-load.js`: link target classification and popup/popover orchestration.
- `js/annotations.js`: annotation fragment fetching and caching.
- `js/content.js`: link content loading, parsing, and cache.
- `js/transclude.js`: client-side transclusion.
- `js/collapse.js`: collapsible block behavior.
- `js/sidenotes.js`: dynamic sidenote layout.
- `js/image-focus.js`: image zoom and slideshow overlay.
- `js/dark-mode-initial.js` and `js/dark-mode.js`: theme switching and early dark-mode behavior.
- `js/reader-mode.js`: reader mode UI and activation logic.
- `js/404-guesser.js`: sitemap-backed 404 suggestions.

CSS and templates:

- `template/default.html`: page shell, metadata fields, no-JS warning, lazy backlink/similar/bibliography includes.
- `css/default.css`: main layout, admonitions, tables, code blocks, dropcaps, sidenotes, popframes, popups, reader mode.
- `css/links.css`: annotation indicators and link icon styling.
- `css/initial.css`, `css/reader-mode-initial.css`, `css/dark-mode-adjustments.css`: early layout and mode support.

Serving:

- `nginx/gwern.net.conf`: canonical host behavior, Markdown negotiation, custom MIME types, redirects, immutable caching, SSI, noindex headers, error handling.

## Appendix: Feature Coverage Checklist

- Annotation popups/popovers: covered.
- Local pages, PDF, and source code previews: covered.
- Client-side transclusion: covered.
- Collapsible sections: covered.
- Local archives and mirrors: covered.
- Sidenotes and margin notes: covered.
- Backlinks and similar links: covered.
- Reader mode: covered.
- Syntax highlighting: covered.
- LaTeX and math handling: covered at feature level from Design and Hakyll writer settings.
- Dark mode: covered.
- Image zoom, slideshows, wide images, and wide tables: covered.
- Sortable tables: covered.
- Inflation and BTC adjustment: covered.
- Link icons: covered.
- Admonitions: covered.
- Dropcaps: covered.
- 404/search affordances: covered.
- Markdown negotiation for agents: covered.
