# Server-first reliability milestone

Status: complete

## Outcome

Turn the existing Analytico/CSP and HTMX preview behavior into an executable
browser contract. The site already follows the desired delegated-listener and
server-first architecture; this milestone protects it from regression.

## Candidates

| Candidate | Benefit | Cost |
| --- | --- | --- |
| Keep header/string smoke checks only | Fast and dependency-free | Cannot observe CSP-blocked scripts or post-swap browser behavior |
| Add one focused headless-browser smoke gate | Proves the integration users actually receive | Test-only Node module and browser executable |
| Add a general frontend test framework | Broad future surface | Unnecessary framework and maintenance cost |

## Decision

Add one dependency-light browser script using an exactly pinned test-only
Playwright Core module and an externally supplied Chromium executable. Keep the
existing shell and Zig tests as the fast default checks.

## Work

1. Assert that the rendered tracker origin is allowed by `script-src`,
   `connect-src`, and `img-src` rather than checking only that CSP exists.
2. In Chromium, intercept the external tracker with a deterministic fixture,
   prove it loads without a CSP console error, and prove the JavaScript-disabled
   pixel is requested.
3. Exercise two distinct preview links and then the first again, asserting each
   swapped preview belongs to the selected link.
4. Keep all production markup, appearance, navigation, and preview semantics
   unchanged.

## Definition of done

- [x] HTTP smoke checks require the exact Analytico origin in every necessary
      CSP directive.
- [x] JavaScript-enabled Chromium loads the tracker fixture and records no CSP,
      console, or page errors.
- [x] JavaScript-disabled Chromium requests the Analytico pixel and retains all
      native navigation.
- [x] Preview A -> B -> A succeeds through real HTMX swaps and delegated event
      handling.
- [x] The enhanced first view performs no same-origin startup data request.
- [x] Generated-output, formatting, Debug, ReleaseSafe, and HTTP smoke gates
      pass.

## Explicitly deferred

- Navigation boosting, SPA state, a component framework, visual changes, or a
  second analytics client.
- Downloading browsers during normal builds or adding a runtime Node
  dependency.
