# Testing strategy: unit tests plus Playwright/Cypress e2e

Every generated plugin ships two test layers: unit tests for logic, and an end-to-end (e2e) suite that
drives a real player built from the local bundle. Both layers are mandatory in both modes (research
§8-§10; plan §4 phase 3). This file is self-contained: it covers what to test, which runner to use in
which mode, the required lifecycle list, i18n, Trusted Types, and the exit checks that close phase 3.

## Why two layers, not one

Kaltura's own reference plugins show what happens when only one layer exists, or neither:

| Plugin | Unit tests | E2E | Research |
|---|---|---|---|
| `playkit-js-plugin-example` (template) | none shipped (mocha/chai/sinon installed, unused) | Cypress, 4 browsers, mock provider | §8 |
| `playkit-js-kaltura-cuepoints` | karma+mocha+chai | none | §10 |
| `playkit-js-transcript` | none | Cypress, 4 browsers | §10 |
| `playkit-js-aws-analytics` | none | Cypress chrome only, hits a live Kaltura partner | §9, §10 |

None of the four has both. A unit suite alone never catches a broken `addComponent` call or a CSP
violation; an e2e suite alone is slow to run for every config-validation branch and cannot easily
assert internal state transitions. Ship both.

## Unit tests

### Runner: decide once, split by mode

Research found no existing unit-test runner decision to inherit (the template ships mocha/chai/sinon
as unused devDependencies; `kaltura-cuepoints` uses karma+mocha+chai for its real suite; §8, §10). This
file sets the default, split by mode, so the skill never re-litigates it per plugin:

- **Community mode: Vitest.** TypeScript- and ESM-native, no Karma browser launcher needed for
  logic-only tests, fast watch mode. It has no dependency relationship with Playwright; the two are
  chosen independently, each for its own layer.
- **Internal mode: mocha + chai + sinon.** These are already devDependencies of the cloned
  `playkit-js-plugin-example` template (research §8) and match the pattern already proven in
  `kaltura-cuepoints` (research §10). Using them avoids adding a new test framework to a repo the
  internal reusable workflows already expect to build a certain way.

This is a default, not a discovered Kaltura requirement. State it back to the operator during Intake
(phase 0) like any other default from `reference/decision-tree.md`.

### What to unit-test

Any plugin logic that is not a straight pass-through, run against a mocked `player` and
`BasePlugin`, no real player build:

- **Config validation.** Every branch of the boundary validation described in
  `reference/config-and-validation.md`: valid config accepted, each invalid shape rejected, defaults
  applied, nested-default merge (the shallow-spread footgun, research §1) does not silently drop keys.
- **State machines.** Any internal state transitions (e.g., a threshold crossed, a panel open/closed
  toggle) tested for each transition and each invalid transition attempt.
- **Threshold math.** Boundary values (exactly at the threshold, one unit below, one above), not just
  a happy-path middle value.
- **Event mapping.** Every player event the plugin listens for maps to the correct internal action or
  outbound event/dispatch; assert the listener is registered through `this.eventManager.listen`, never
  `player.addEventListener` directly (research §4), since only the former is cleaned up by
  `destroy()`.
- **`registerPlugin` return value.** `register()` returns `false` silently on an invalid class or a
  duplicate name; it never throws (research §2). One test calls `registerPlugin(name, PluginClass)`
  and asserts the return value is `true`. This is cheap and catches a broken class hierarchy
  (`Class.prototype instanceof BasePlugin` failing) that would otherwise silently no-op in production.

### Mocking the player

Don't build a real `KalturaPlayer` instance for unit tests; that belongs to e2e. Build a minimal fake
that satisfies the surface the plugin actually calls: `dispatchEvent`, `getService`/`hasService`
(stubbed per test), `Event.Core.ERROR` (or whichever namespace the plugin dispatches on), and an
`eventManager`-shaped listen/unlisten pair if the plugin's own logic (not `BasePlugin`'s) tracks
listeners. Keep the fake in a shared test helper so every plugin test file imports one, instead of
five slightly different hand-rolled mocks.

## Required lifecycle tests (every plugin, no exceptions)

Plan §4 phase 3 names six lifecycle cases. Each one is a real behavior in `BasePlugin`/the plugin
manager (research §1-§2), and each has a concrete assertion, not a vibe:

1. **Valid load.** Construct with a valid config (or register through the plugin manager with a valid
   config) and assert the plugin activates: `isValid()` returns `true`, no error dispatched, any
   `loadMedia()`-time setup (e.g., `addComponent`) runs.
2. **Invalid config.** Construct with a config that fails validation and assert `isValid()` returns
   `false` and nothing throws. `isValid()` takes no arguments (research §1); a plugin that reads
   `this.config` inside `isValid()` and finds it malformed must return `false`, never throw. The
   plugin manager does not try/catch `isValid()` (research §2), so a throw here is not "recoverable
   error", it is a crash that reaches the player's top-level error handling.
3. **`disable: true`.** Config with `config.plugins.<name>.disable: true` (the one reserved key,
   research §2) results in the plugin manager's `register`/`load` treating the plugin as absent:
   assert no `loadMedia()`-time side effect ran (no `addComponent` call, no listener attached).
4. **Change media (`reset()` + second `loadMedia()`).** Call `reset()` then `loadMedia()` again and
   assert the plugin re-initializes cleanly: no duplicate `addComponent` calls, no duplicate
   listeners, any per-media state (e.g., an `AbortController`, a cue-point cache) is cleared and
   rebuilt. This is the case real plugins get wrong most often, because `reset()` defaults to a no-op
   in `BasePlugin` (research §1) and is easy to forget to override.
5. **`destroy()` removes listeners and UI.** Call `destroy()` and assert: `this.eventManager.destroy()`
   ran (directly or via `super.destroy()`, but see the "do not copy" note below on why it must be
   `super.destroy()`), any `addComponent` remove function was called (the API returns one, research
   §6.1), and any service registered via `player.getService`/side panel/upper-bar icon was torn down.
   For a UI plugin, assert the rendered DOM node is gone after `destroy()`, not just that a callback
   ran.
6. **Error path emits RECOVERABLE.** Force the failure condition the plugin is designed to downgrade
   (a third-party SDK load failure, a malformed response, a bad cue point) and assert the plugin
   constructs and dispatches `new Error(RECOVERABLE, <category>, <code>, data)` on
   `player.Event.Core.ERROR` (research §4), and playback is not interrupted. There is no PLUGIN or
   CUSTOM error category; use `PLAYER` unless ADS/VR/NETWORK genuinely fits (research §4). Full
   resilience rules: `reference/error-event-taxonomy.md`.

UI-branch plugins add: keyboard reachability (the interactive element is reachable via `Tab` and
operable via `Enter`/`Space`) and an `aria-label` (or equivalent accessible name) assertion on the
rendered component, per plan §4 phase 3. Use `cypress-axe` or Playwright's accessibility snapshot,
whichever the mode's runner provides; see `reference/ui-components.md` for the a11y contract this
tests against.

## i18n tests

Only when the plugin ships UI text (research §6.3: plugin translation files are never auto-loaded;
`ui.translations` is a host-page contract). Two tests, one per layer:

- **Unit: key-set parity.** For every `translations/<locale>.i18n.json` the plugin ships, assert its
  key set is exactly the `en` key set (same keys, no more, no fewer). This catches a locale file that
  drifted after an English string was added or renamed, before it ships a broken translation.
- **E2E: one non-`en` locale renders.** Start the player with `ui.locale` set to one shipped non-`en`
  locale and the matching `ui.translations` block, and assert the translated string (not the raw key,
  not the English fallback) appears in the rendered DOM. One locale is enough to prove the wiring
  works; key-set parity in the unit test already covers every other shipped locale.

If the plugin ships only `en`, skip both tests and say so in `PLAN.md`; don't manufacture a second
locale file just to satisfy this section.

## Trusted Types: enforcing CSP on every e2e and demo page

Research §6.6 found no Trusted Types sinks in playkit-js-ui or kaltura-player-js, and the one sink in
playkit-js (`player.ts` iframe title) and the one script-loading path (prebid) are both out of scope
for a mock-provider e2e page. That means a top-level (non-iframe), no-prebid page can run the player
under an **enforcing** Trusted Types CSP today. Prove it on every test and demo page, don't just claim
compatibility:

- Serve the e2e test page with `Content-Security-Policy: require-trusted-types-for 'script'` as a
  response header from the dev server. Use a `<meta http-equiv="Content-Security-Policy" ...>` tag as
  a fallback only when the runner cannot set a header (some static file servers can't).
- Register a `securitypolicyviolation` listener on the page before the player loads. On the **first**
  violation, fail the test and report `event.sourceFile` and `event.sample` in the failure message, so
  a violation is diagnosable from CI logs alone, not a manual repro.
- The mock provider serves a local `media/video.mp4` through the native adapter, so hls.js/dash.js/
  shaka are never loaded on this page and are correctly out of scope (research §6.6, §14). If a
  generated plugin later switches the demo or e2e page to an HLS/DASH source, re-grep those engines
  for Trusted Types sinks first; that check has not been done (research §14).
- The same enforcing CSP applies to the demo page (`reference/docs-and-demo.md`), and to the plugin's
  own ESLint config, which bans the sink list (`innerHTML`, `outerHTML`, `insertAdjacentHTML`,
  `document.write`, `eval`, `new Function`, `script.src`) in `src/`. See
  `reference/security-checklist.md`. Testing and linting cover the same rule from two directions: lint
  catches the sink at write time, the e2e CSP check catches anything lint missed (a sink introduced by
  a dependency, or written through a computed property lint can't trace).
- The Unisphere consumer branch is the one exception: its loader uses a dynamic `import()` of a URL,
  and whether that survives an enforcing CSP is unverified (research §14, §16.8). Keep that page's
  Trusted Types check **informational** (log, don't fail) until that gap is closed. See
  `reference/unisphere-integration.md` for the Unisphere e2e recipe in full.

## E2E: Playwright (community) / Cypress (internal)

Plan §6 recommendation 9 is the one recommendation that splits by mode, because Cypress's WebKit
support is still experimental and Safari matters for a video plugin (research §13):

| | Community mode | Internal mode |
|---|---|---|
| Runner | Playwright | Cypress (matches the template and the internal reusable workflow) |
| Browsers | chrome required; firefox/edge/webkit when the runner supports them | chrome/firefox/edge/webkit per the template's `experimentalWebKitSupport` config (research §8) |
| CI retries | CI-only, trace on first retry | per the internal reusable workflow's own settings |

Shared rules, both runners:

- **Default to the mock provider.** Copy the template's shape (research §8): `partnerId: -1`, mock
  `env: {cdnUrl, serviceUrl}`, a local `media/video.mp4`. This needs no Kaltura network and is not
  flaky. A live-partner smoke test is opt-in, separately marked flaky-tolerant (retries allowed,
  non-blocking on transient network failure), and never the default CI path. This is the corrected
  version of what `aws-analytics` does unconditionally (research §9, §10): its `cy.wait(3000)` against
  a live partner (6492412) is a flakiness source to route around, not a pattern to copy wholesale.
- **Pin the player version.** The test page loads `@playkit-js/kaltura-player-js` at an exact pinned
  version, resolved once via `npm view @playkit-js/kaltura-player-js version` (research: intro,
  version-source-of-truth note) and written into the test HTML. Never `@latest` in CI: a silent
  upstream player release should not make an unrelated plugin's CI go red without a diff to point at.
- **Package name check.** Assert (grep or an actual `npm ls`) that the plugin's own `package.json`
  depends on `@playkit-js/kaltura-player-js`, never the bare `kaltura-player-js`. The bare name has a
  known-malicious published version (OSV MAL-2025-41390, research §13); this is a hard fail, covered
  in full in `reference/security-checklist.md`.
- **Explicit browser-install CI step.** npm 12 default-denies install scripts (research §13), so
  Playwright/Cypress browser binaries do not download as a side effect of `npm ci`. CI must run
  `npx playwright install --with-deps` (community) or `npx cypress install` (internal) as its own
  step, not rely on a postinstall hook. `reference/ci-cd-modes.md` has the full workflow skeleton.

## Unisphere consumer branch: stubbed-service unit test, gated e2e

When the plugin is on the Unisphere consumer branch (`reference/unisphere-integration.md`), test at
both layers, but the e2e layer is conditional:

- **Unit.** Stub `player.getService('unisphereService')` to return a fake
  `{pluginManager, eventService}` and assert: `pluginManager.getWorkspace()` is called,
  `loadRuntime` receives the correct widget id, runtime name, flavor (if any), and settings,
  `initRuntime` receives the layout object shaped per `reference/unisphere-integration.md`, storage
  pushes go out with only the keys the runtime's settings schema declares, and event subscriptions
  are registered on the expected `unisphere.event.player.*` names. Also assert **inert behavior**:
  when `getService('unisphereService')` returns `undefined`, the plugin logs once and does nothing
  else (no throw, no retry loop).
- **E2E.** Load the real `@playkit-js/unisphere-service` bundle alongside the plugin, with
  `provider.unisphereLoaderUrl` read from an environment variable the operator sets (name it in the
  plugin's own CI docs, not in a tracked file). When that variable is unset, **skip the test and print
  the skip reason**. Do not fail the build. A production loader URL for self-hosted players is not
  publicly documented (research §14), so most CI runs will legitimately not have one.
- Trusted Types on this specific e2e page stays informational, per the Trusted Types section above.

## A11y checks (UI branch)

For any plugin that renders a UI component (`addComponent` branch or services/side-panel branch),
run an automated accessibility check against the rendered component: `cypress-axe` in internal mode,
Playwright's built-in accessibility snapshot or an axe-core integration in community mode. This is in
addition to, not instead of, the manual keyboard/`aria-label` assertions in lifecycle test 6 above.
Axe catches contrast and structural issues a manual assertion won't, but it can't verify keyboard
reachability by itself.

## Do not copy from the reference plugins

Every plugin research examined has at least one testing anti-pattern (research §8-§10, §16.6). Do not
reproduce these in a generated plugin:

- `npm test` that is a literal `echo 'TODO'` (all four Unisphere plugins, research §16.6).
  A CI step that exits 0 without running anything is worse than no test step, because it looks green.
- Cypress specs that are unmodified template boilerplate testing the *template's* placeholder
  component, not the plugin's actual behavior (`unisphere-summary`, `unisphere-genie`, research §16.6).
- `destroy()` that calls `this.eventManager.destroy()` directly instead of `super.destroy()`
  (`aws-analytics`, research §9). It happens to work today because `BasePlugin.destroy()` does exactly
  that, but it silently stops working the moment `BasePlugin.destroy()` does anything else in a future
  player version. Lifecycle test 5 should assert `super.destroy()` was called (spy on the prototype
  method), not just that listeners are gone, so this regression is caught even if it doesn't change
  today's observable behavior.
- A live-network e2e test as the only e2e test (`aws-analytics`, research §9, §10): it is flaky by
  design and gives no signal on a network outage day. Mock provider first, live test opt-in only.
- Coverage numbers with no shipped tests behind them, i.e., installing mocha/chai/sinon and never
  writing a test file (template, research §8). A devDependency is not a test.

## Exit checks (phase 3, plan §4)

Run these before calling phase 3 done. All must pass; none is a self-rating.

```bash
# Unit and e2e suites both green
npm test
npm run test:e2e

# CI has an explicit browser-install step (grep the workflow file)
grep -n "playwright install\|cypress install" .github/workflows/*.yml

# Package name hard fail check
grep -n '"kaltura-player-js"' package.json && echo "FAIL: bare package name" || echo "OK"
grep -n '"@playkit-js/kaltura-player-js"' package.json

# Lifecycle tests exist (the scaffold's convention is a top-level test/ dir, not src/**/*.test.*;
# adjust the glob if a plugin's layout genuinely differs)
grep -l "disable" test/**/*.test.* test/**/*.spec.* 2>/dev/null
grep -rln "destroy" test/**/*.test.* test/**/*.spec.* 2>/dev/null

# i18n key-set parity test exists, only when translations/ has more than one locale
test -d translations && ls translations/*.i18n.json | wc -l

# Trusted Types: the e2e page's CSP header/meta and violation listener both present
grep -rn "require-trusted-types-for" cypress/public/index.html e2e/*.html 2>/dev/null
grep -rn "securitypolicyviolation" cypress/ e2e/ 2>/dev/null

# Unisphere branch only: stubbed-service unit test present, e2e skip path present
grep -rn "getService('unisphereService')" test/**/*.test.* 2>/dev/null
grep -rn "UNISPHERE_LOADER_URL\|unisphereLoaderUrl" e2e/ cypress/ 2>/dev/null
```

`npm test` and `npm run test:e2e` exiting 0 is necessary but not sufficient: also confirm the six
lifecycle cases, the i18n pair (when applicable), and the Trusted Types violation check actually exist
as test cases, not just that the suite as a whole is green. A suite with zero assertions also exits 0.
