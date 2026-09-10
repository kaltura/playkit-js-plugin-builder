# Research: building a Kaltura PlayKit-JS plugin, grounded in verified sources

Status: **verified 2026-09-09** against default branches. The first draft of this file (same date, earlier) had nine factual errors. They are listed in §15 so nobody re-introduces them.

Pinned SHAs used throughout:

| Repo | SHA | Version |
|---|---|---|
| kaltura/kaltura-player-js | `a55edf511fbeed951004e421d1c740c19604919d` | 3.17.97 |
| kaltura/playkit-js | `04ec036080130001698635f6f2059859655744d6` | 0.84.50 |
| kaltura/playkit-js-ui | `497114d` | default branch |
| kaltura/playkit-js-plugin-example | `9509fbb` | 1.0.0 |
| kaltura/playkit-js-kaltura-cuepoints | `d12ffae` | default branch |
| kaltura/playkit-js-transcript | `fd0fea4` | default branch |
| kaltura/playkit-js-aws-analytics | `4e226ff` | 1.2.0 |
| kaltura/playkit-js-unisphere-service (internal visibility) | `b40c58d` | 0.0.27 |
| kaltura/playkit-js-unisphere-summary (internal visibility) | `1e9a233` | 1.1.6 |
| kaltura/playkit-js-unisphere-genie (internal visibility) | `93d30e6` | 0.0.29 |
| kaltura/playkit-js-unisphere (internal visibility, legacy) | `8b16c53` | 0.0.30 |
| kaltura/playkit-js-providers | `2b40f86` | default branch |
| kaltura/unisphere-core (internal visibility) | `3397dc3` | `@unisphere/core` 1.100.0 on npm |
| kaltura/unisphere-documentations (internal visibility) | `194490c` | default branch |
| kaltura/unisphere-video-summary (internal visibility) | `9b9149b` | default branch |
| kaltura/unisphere-player (internal visibility) | `89d545a` | empty scaffold |

Rule for this repo: if a claim below is not enough, read the cited file at the pinned SHA. Do not fill gaps from memory.

Version source of truth for kaltura-player-js: git tags and the npm registry, not the GitHub Releases
page. Kaltura stopped creating GitHub Release objects in January 2024, so the Releases page shows
`v3.17.8-SUP-41102` (a support-branch patch, 2024-01-28) as "Latest". Tags continue to `v3.17.97`, master
`package.json` is `@playkit-js/kaltura-player-js` 3.17.97, and npm `latest` is 3.17.97 (published
2026-08-28; dist-tags also `canary` and `patch`). Checked 2026-09-09. Agents must resolve the current
version from `npm view @playkit-js/kaltura-player-js version`, never from the Releases badge.

## 1. `BasePlugin` (kaltura-player-js `src/common/plugins/base-plugin.ts`)

Every plugin extends `BasePlugin`. Full surface:

| Member | Visibility | Default behaviour | Notes for generated plugins |
|---|---|---|---|
| `constructor(name, player, config)` | public | sets `name`, `player`, `logger = getLogger(capitalize(name))`, `eventManager = new EventManager()`, `config = {...defaultConfig, ...config}` | Called by the plugin manager. Never call it yourself. |
| `name` | public | set by ctor | |
| `displayName!`, `symbol!: {svgUrl, viewBox}` | public | uninitialised | Set them if a UI host lists plugins. |
| `logger`, `config`, `player`, `eventManager` | protected | set by ctor | |
| `static defaultConfig` | protected static | `{}` | Override. |
| `static isValid(): boolean` | public static | **throws** `Error(CRITICAL, PLAYER, RUNTIME_ERROR_METHOD_NOT_IMPLEMENTED)` | **Takes no arguments.** Must override. Return `false` to block activation. |
| `getConfig(attr?)` | public | `Utils.Object.copyDeep` | Never returns a live reference. |
| `updateConfig(update)` | public | `Utils.Object.mergeDeep` into live config | Deep merge. |
| `get ready()` | **protected** getter | `Promise.resolve()` | Override to delay `load`/`play` on an async dependency. |
| `loadMedia()` | public | no-op | Fires on `CHANGE_SOURCE_STARTED`, not "media loaded". |
| `reset()` | public | no-op | Called before `setMedia()`/`loadMedia()` on an existing player. |
| `destroy()` | public | `this.eventManager.destroy()` | Subclasses **must call `super.destroy()`** (or destroy the event manager themselves). |
| `open()` | public | **throws** RUNTIME_ERROR_METHOD_NOT_IMPLEMENTED | For overlay plugins opened by a UI host. No core caller. |
| `getName()` | public | returns `name` | |
| `dispatchEvent(name, payload?)` | public | debug log, then `player.dispatchEvent(new FakeEvent(name, payload))` | Use for custom plugin events. |

**Config merge footgun.** Construction merge is a **shallow spread** (`base-plugin.ts:87`). A nested default like `{thresholds: {a: 1, b: 2}}` is replaced wholesale when the host passes `{thresholds: {a: 5}}`. `updateConfig` deep-merges (`base-plugin.ts:118-120`). Generated plugins that need nested defaults must merge them explicitly in the constructor.

## 2. Plugin manager and registration (`src/common/plugins/plugin-manager.ts`)

- Register with the free function: `registerPlugin('myPlugin', MyPlugin)`. Import it from `@playkit-js/kaltura-player-js` (modular) or use `KalturaPlayer.core.registerPlugin` (global). Both exist; `src/index.ts` patches `BasePlugin` and `registerPlugin` onto the re-exported `core` object.
- `register(name, Class)` validates `Class.prototype instanceof BasePlugin` and **returns `false` silently** on an invalid class or a duplicate name. No throw. Generated code should assert the return value in tests.
- `load()`: `isValid()` is **not** try/caught. A throw propagates and `kaltura-player.ts:1064-1071` dispatches it as an error event. A constructor throw is caught and rethrown as `Error(RECOVERABLE, PLAYER, PLUGIN_LOAD_FAILED)`. `isValid() === false` or `config.disable === true` returns `false` silently.
- `disable` is cached per plugin name and only re-read when `typeof config.disable === 'boolean'`.
- `loadMedia()`, `reset()`, `destroy()` fan out to every plugin; `destroy()` removes each from the map.
- Config reaches the plugin as `config.plugins.<name>`; `config.plugins.<name>.disable: boolean` is the only reserved key (`docs/configuration.md:163-204`).

## 3. Duck-typed hooks (probed in `kaltura-player.ts:1078-1097`, not declared on `BasePlugin`)

| Hook | Effect | Upstream doc |
|---|---|---|
| `getMiddlewareImpl()` | pushed onto `_localPlayer.playbackMiddleware` (unshifted for the plugin named `bumper`) | none |
| `getUIComponents()` | each returned item passed to `_uiWrapper.addComponent()` | `docs/writing-a-plugin.md`, wrongly described |
| `getEngineDecorator()` | `registerEngineDecoratorProvider(new EngineDecoratorProvider(plugin))`; registered on method existence | none |
| `ready` | read by `PluginReadinessMiddleware` on `load`/`play`. **Rejection is swallowed** (debug log, playback continues). Only a slow resolve delays playback. | partial |

Design rule: a plugin that must block playback on failure cannot rely on a rejected `ready`. It has to dispatch a CRITICAL error itself.

### 3.1 `getEngineDecorator()` as the path to the real engine / `hls.js` instance (added post-v1, live-verified)

No public `Player`-level getter exposes the engine or a raw `hls.js` instance (`Player._engine` is
`private`, `src/player.ts`; no `getEngine`/`getAdapter`/`getHls` method exists in
`@playkit-js/kaltura-player-js` or `@playkit-js/playkit-js`, checked at `0.84.33`/`0.84.50` and
`kaltura-player-js@3.17.97`). The verified path: `getEngineDecorator(engine)` receives the live `Html5`
engine object; `Html5.mediaSourceAdapter` is a **public** getter (`playkit-js/src/engines/html5/html5.ts:275-277`)
returning the active adapter; `HlsAdapter` stores the real instance as `private _hls!: Hls;`
(`playkit-js-hls/src/hls-adapter.ts:77` — TS-private only, absent from any published `.d.ts`, readable
at runtime via a local structural type). Confirmed working end-to-end in a real generated plugin
(`playkit-js-captionhub-plugin`, `CaptionHubTimbraPlugin.ts`, wrapping `@captionhub/timbra.js`'s
`Timbra.HLSJSPlugin`, which requires the live `Hls` instance in its constructor). Separately,
hls.js-derived *events* (not the instance) are already forwarded to the public player: `player.ts`'s
`_eventManager.listen(this._engine, CustomEventType.X, (event) => this.dispatchEvent(event))` forwards
`FRAG_LOADED`, `TIMED_METADATA_ADDED`, `MANIFEST_LOADED`, and others (confirmed by reading the
forwarding list directly) — those reach `player.addEventListener(player.Event.Core.X, ...)` with no
engine decorator needed. Full pattern and code: `reference/base-plugin-api.md` §7b.

## 4. Error and event taxonomy (playkit-js `src/error/*`, kaltura-player-js `kaltura-player.ts:840-851`)

- Constructor: `new Error(severity, category, code, data = {}, errorDetails?)`. Five arguments. Constructing an Error **always logs**, even if never dispatched.
- Severity: `RECOVERABLE = 1` (log only), `CRITICAL = 2` (player shows the error overlay).
- Category: NETWORK 1, TEXT 2, MEDIA 3, MANIFEST 4, STREAMING 5, DRM 6, PLAYER 7, ADS 8, STORAGE 9, CAST 10, VR 11, MEDIA_NOT_READY 12, GEO_LOCATION 13, MEDIA_UNAVAILABLE 14, IP_RESTRICTED 15, SITE_RESTRICTED 16, SCHEDULED_RESTRICTED 17, ACCESS_CONTROL_BLOCKED 18, DELETED_ENTRY 19. **There is no PLUGIN or CUSTOM category.** Plugins use `PLAYER` unless ADS/VR/NETWORK fit better.
- PLAYER codes (7xxx): LOAD_INTERRUPTED 7000, BITRATE_SWITCH_ISSUE 7001, LOAD_FAILED 7002, RUNTIME_ERROR_NOT_REGISTERED_PLUGIN 7003, RUNTIME_ERROR_METHOD_NOT_IMPLEMENTED 7004, RUNTIME_ERROR_NOT_VALID_HANDLER 7005, NO_SOURCE_PROVIDED 7006, NO_ENGINE_FOUND_TO_PLAY_THE_SOURCE 7007, ENTER_PICTURE_IN_PICTURE_FAILED 7008, EXIT_PICTURE_IN_PICTURE_FAILED 7009, PLUGIN_LOAD_FAILED 7010. No generic custom-plugin code. Put plugin-specific detail in `data`.
- Dispatch: `this.player.dispatchEvent(new FakeEvent(this.player.Event.Core.ERROR, err))`. The upstream `docs/errors.md:37-49` example uses `player.Event.Error`, **which does not exist**.
- Event namespaces on `player.Event`: `Core`, `UI`, `Cast`, `Playlist`, plus flat `VISIBILITY_CHANGE`, `REGISTERED_PLUGINS_LIST_EVENT`, and every `CoreEventType` key spread flat for back-compat. `docs/events.md` documents only Core and UI.
- Custom plugin events: `this.dispatchEvent(name, payload)`. For cross-framework bridges, `playkit-js-aws-analytics` also emits `CustomEvent` on `document`.
- Listener discipline: register everything through `this.eventManager.listen(...)`, never `player.addEventListener`, so `destroy()` cleanup reaches it.

## 5. Coding guidelines (kaltura-player-js `docs/coding-guidlines.md`, misspelled filename is the real one)

- `functionNamesLikeThis`, `variableNamesLikeThis`, `ClassNamesLikeThis`, `EnumNamesLikeThis`, `CONSTANT_VALUES_LIKE_THIS`, PascalCase type names.
- Trailing underscore on private members (`_foo`). Upstream is inconsistent: `base-plugin.ts` uses TS `protected` with no underscore, `plugin-manager.ts` uses `private _x`. Treat it as a convention for generated code, not a lint failure.
- Single quotes. JSDoc `@param`/`@returns` above every function. Arrow functions over `.bind(this)`. Braces on every control structure. 2-space indent.
- Enforced tooling in the official template: ESLint `@typescript-eslint/recommended` + prettier, `max-len: 150`, `no-console: 'error'`, `explicit-member-accessibility`; Prettier `printWidth: 150`, `singleQuote`, no trailing commas.

## 6. UI components (playkit-js-ui)

### 6.1 Contract
- `this.player.ui.addComponent(options)` where `KPUIAddComponent = {label, presets, area, container? (deprecated), beforeComponent?, afterComponent?, replaceComponent?, get: (() => any) | string, props?}` (`src/types/ui-component-options.ts`, `ui-component.ts`).
- `addComponent` **returns a remove function** (`src/ui-manager.tsx:101-103`). Store it and call it in `reset()`/`destroy()`.
- `get: 'remove'` removes a built-in component from the named area/presets.
- The official template calls `addComponent` in `loadMedia()`.
- `docs/ui-components.md` still says **BETA**. Its area list is incomplete; use the source enums below.

### 6.2 Enums (`src/reducers/shell.ts:45-75`, source of truth)
- `ReservedPresetNames`: Playback, Live, Ads, Error, Idle, Img, Document, MiniAudioUI.
- `ReservedPresetAreas`: PlayerArea, PresetArea, InteractiveArea, VideoArea, GuiArea, TopBar, BottomBar, PresetFloating, TopBarLeftControls, TopBarRightControls, BottomBarLeftControls, BottomBarRightControls, SidePanelTop, SidePanelLeft, SidePanelRight, SidePanelBottom, SeekBar, LoadingSpinner.

### 6.3 i18n: plugin translation files are NOT auto-loaded
`IntlProvider` wraps `<Shell>` with playkit-js-ui's own `translations/en.i18n.json` merged with `config.ui.translations` per locale (`ui-manager.tsx:148-162`). Nothing reads a plugin's `translations/*.i18n.json`. The template's `demo/index.html:20-27` re-declares the keys under `ui.translations` by hand. A generated plugin that uses `withText` must do one of: document the required `ui.translations` block for the host page, merge its own dictionary at runtime, or give every `withText` key a fallback string.

Multi-language, verified at `497114d` `ui-manager.tsx:57-64,148-162,199`:
- `_setLocaleTranslations` runs once, from the constructor. Each `config.ui.translations[locale]` is deep-merged over the built-in `en` so missing keys fall back to English. `config.ui.locale` is lower-cased and used only if a dictionary for it exists; otherwise the locale stays `en`.
- There is no public method to add a dictionary or switch locale after construction. `_translations` and `_locale` are private. A plugin cannot inject its own dictionaries at runtime without touching private state.
- Consequence: multi-language support is a host-page contract. The plugin ships `translations/<locale>.i18n.json`, generates the matching `ui.translations` block for every locale it ships, and the host sets `ui.locale`. Every `withText`/`<Text>` key keeps an English fallback so an unsupported locale degrades to English, not to raw keys.

### 6.4 Runtime surface (`src/index.ts`)
`h`, `createPortal`, `preact`, `redux`, `preacti18n`, `preactHooks`, `EventType`/`Event`, `getOverlayPortalElement`, `getDurationAsText`, `style`, `Reducers`, `Presets`, `Components` (about 50, incl. Tooltip, Icon, SidePanel, SmartContainer, keyboard HOCs), `Utils` (`withKeyboardA11y`, `focusElement`, `KeyMap`/`KeyCode`, `getLogger`), `UIManager`, `SidePanelPositions`, `SidePanelModes`, `ReservedPresetNames`, `ReservedPresetAreas`, `VERSION`, `NAME`.

### 6.5 Accessibility
No ARIA or focus-management doc exists upstream. Only `docs/with-keyboard-event.md`. `Utils.withKeyboardA11y` and `focusElement` exist in source, undocumented. Any a11y guidance in this skill is synthesized from WAI-ARIA practice plus these two utilities, and must say so.

### 6.6 Trusted Types sinks in the player stack (grep at pinned SHAs, 2026-09-09)
`require-trusted-types-for 'script'` blocks string assignment to `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `script.src`, `script.text`, `eval`, `new Function`. Hits in the stack:
- playkit-js-ui `src/`: none.
- kaltura-player-js `src/`: none (`thumbnail-manager.ts:46` is `img.src`, not a Trusted Types sink).
- playkit-js `src/`: `player.ts:2116` `title.innerHTML = metadata.name` runs only when embedded in an iframe (`_addTitleOnIframe`); `utils/jsonp.ts:62` and `utils/util.ts:458` assign `script.src`, reached only via `loadScriptAsync`, whose only caller is `ads/prebid-manager.ts:67`.
- So a top-level (non-iframe) page with no prebid can run the player under an enforcing Trusted Types CSP. Engines (hls.js, dash.js, shaka) were not grepped; the mock-provider e2e page uses a local mp4 through the native adapter, so they are not loaded there.

## 7. Services registry and `@playkit-js/ui-managers` (third architecture pattern)

- `KalturaPlayer.registerService(name, svc)`, `getService(name)`, `hasService(name)` (`kaltura-player.ts:1214-1233`). Player-level, string-keyed, undocumented in `writing-a-plugin.md`.
- Observed services: `sidePanelsManager`, `upperBarManager`, `kalturaCuepoints`, `AudioPluginsManager`.
- `playkit-js-kaltura-cuepoints` registers `kalturaCuepoints` in its constructor. `playkit-js-transcript` consumes `sidePanelsManager` and `upperBarManager` via `getService`, **does not use `ui.addComponent`**, and bundles `@playkit-js/ui-managers` as a devDependency (not externalized).
- This is how Kaltura's own UI-heavy plugins are built today. The skill's decision tree needs three branches: event-bridge (no UI), `addComponent` UI (template pattern), and ui-managers side panel / upper bar (transcript pattern).
- A fourth service, `unisphereService`, is registered by `@playkit-js/unisphere-service` and gives thin plugins a ready Unisphere workspace, side panel, upper-bar icon, pub/sub and storage. See §16. It adds a fourth branch: **Unisphere consumer**.

## 8. Official scaffold (playkit-js-plugin-example @ `9509fbb`)

| Area | Fact |
|---|---|
| Package | `@playkit-js/plugin-example` 1.0.0, AGPL-3.0 |
| Internal gate | `preinstall` runs a Kaltura-internal registry/tooling check that fails to install for anyone without Kaltura-internal registry access. |
| Stack | TypeScript strict, Preact (`jsxFactory: h`, react→preact/compat aliases), scss modules, webpack 5 + **babel-loader**, api-extractor dtsRollup → `dist/index.d.ts`, ESLint + Prettier (§5), standard-version |
| Plugin class | `defaultConfig`, `isValid(): boolean { return true; }`, `loadMedia()` calls `addComponent({label, area: InteractiveArea, presets: [Playback, Live], get: () => <C/>})`, `reset()`, `destroy()` calls `super.destroy()` |
| Externals | `@playkit-js/kaltura-player-js → root KalturaPlayer`, `@playkit-js/playkit-js-ui → root KalturaPlayer.ui`, `@playkit-js/playkit-js → root KalturaPlayer.core`, `preact → root KalturaPlayer.ui.preact`, `preact-i18n → root KalturaPlayer.ui.preacti18n`, `preact/hooks → root KalturaPlayer.ui.preactHooks` |
| Output | UMD `['KalturaPlayer','plugins','pluginExample']`, file `playkit-plugin-example.js`; `dist/` gitignored |
| Tests | Cypress 14 across chrome/firefox/edge/webkit (`experimentalWebKitSupport`, `chromeWebSecurity: false`, `fileServerFolder: 'cypress/public'`). `cypress/public/index.html` loads the player from jsDelivr `@latest` plus the local bundle, uses a **mock provider** (`partnerId: -1`, `env: {cdnUrl: 'http://mock-cdn', serviceUrl: 'http://mock-api'}`) and a local `media/video.mp4`. **No Kaltura network in tests.** Mocha/chai/sinon are installed but **no unit tests ship**. |
| CI | Kaltura-internal reusable GitHub Actions workflows for test, canary, and prod-deploy stages, gated behind internal secrets. **Kaltura-employee-only.** |
| Bundled skill | `.claude/skills/rename-plugin/SKILL.md`: 7 phases (validate clean template → prompt name → branch → replace `playkit-plugin-example`/`PluginExample`/`pluginExample`/`plugin-example` in that order → `git mv` → type-check + build → optional commit). Rename only. |
| Stale README | Documents `npm run dev`, `lint:check`, `prettier:fix`, `types:check`, Mocha/Karma. None exist in `package.json`. Never copy template README prose. |
| Missing | CHANGELOG.md, `.versionrc`, CLAUDE.md/AGENTS.md, unit tests, a11y notes |

## 9. Community reference (playkit-js-aws-analytics @ `4e226ff`)

Built without Kaltura-internal access. Corrected facts:

| Area | Fact |
|---|---|
| Package | `@playkit-js/playkit-js-aws-analytics` 1.2.0, AGPL-3.0, `@playkit-js/kaltura-player-js ^3.17.97`, cypress ^16, standard-version. `.nvmrc` 24, `.npmrc` public registry only. |
| Build | **webpack 5 + babel-loader** (not tsc-only), `@playkit-js/webpack-common`, same three core externals as §8, UMD `['KalturaPlayer','plugins','awsAnalytics']`, `DefinePlugin` `__VERSION__`/`__NAME__` |
| Plugin class | `isValid(): true`; `destroy()` calls `this.eventManager.destroy()` **directly, not `super.destroy()`** (works, but the skill should mandate `super.destroy()`); all listeners via `eventManager.listen`; `reset()` delegates to `loadMedia()` |
| CI (`ci.yaml`) | `actions/checkout@v7`, `setup-node@v7` node 24, `npm ci`, build, type-check, lint, `npm audit --omit=dev --audit-level=high`; e2e via `cypress-io/github-action@v7` (`build: npm run test:prepare`, `command: npm run cy:run:chrome`); Pages deploy gated to push on main with `contents: read`, `pages: write`, `id-token: write`, `configure-pages@v5`, `upload-pages-artifact@v3` path `docs`, `deploy-pages@v4`. **Actions are tag-pinned, not SHA-pinned.** |
| Dependabot | npm weekly, grouped minor/patch, majors ignored; github-actions weekly |
| Release | `scripts/release.sh`: clean-tree check, `npx standard-version --skip.commit --skip.tag`, build, `git add -f dist package.json package-lock.json CHANGELOG.md`, commit `chore(release): vX`, tag. `dist/` committed **only at release** so jsDelivr can serve `cdn.jsdelivr.net/gh/kaltura/<repo>@<tag>/dist/...`. |
| Tests | Cypress chrome only. `cypress/e2e/utils/setup.ts` hits a **live Kaltura partner** (6492412, uiConf 57956092, entry `1_t56a4qrt`) with `cy.wait(3000)`, reaches the plugin via `win.__kalturaPlayer._pluginManager.get('awsAnalytics')`. Network-dependent and flaky by design; the template's mock-provider approach (§8) is the better default. |
| Docs | GitHub Pages from `docs/`: Diátaxis HTML guide, PDF via weasyprint, live demo |
| Process | Never merge until Copilot's PR review has posted and been addressed. CI-green is necessary, not sufficient. |

## 10. Real plugins compared

| | plugin-example | kaltura-cuepoints | transcript | aws-analytics |
|---|---|---|---|---|
| preinstall gate | active | active | disabled | none |
| Bundler | webpack5 + babel | webpack4 + ts-loader | webpack5 + ts-loader | webpack5 + babel |
| Unit tests | none | karma+mocha+chai | none | none |
| E2E | Cypress, 4 browsers, mock provider | none | Cypress, 4 browsers | Cypress chrome, live network |
| `dist/` committed | no | no | no | yes (at release) |
| CI | internal reusable | internal | internal | plain public Actions |
| Distribution | npm (internal) | npm | npm | jsDelivr from GitHub tag |
| Base class import | modular | `KalturaPlayer.core.BasePlugin` global | global | modular |
| UI mechanism | `ui.addComponent` | none | `ui-managers` services | none |
| `kaltura` pkg field | none | `{"name":"kalturaCuepoints"}` | name + `dependencies` | none |

- `kaltura` package.json field is an internal convention for kaltura-tools/canary. Do not copy into community scaffolds.
- Prefer the modular import for type checking.
- The three Unisphere plugins (`unisphere-service`, `unisphere-summary`, `unisphere-genie`) are covered in §16.6. Copy their service-consumer pattern, not their tests or i18n.

### 10.1 Other real plugins cited in `reference/decision-tree.md` (live-checked 2026-09-09)

These five repos are referenced as concrete examples in the decision tree but were not otherwise
covered in this research pass. Verified live via `gh api`/`gh repo view` during the reference-file
verification workflow, 2026-09-09:

| Repo | Fact used | How verified |
|---|---|---|
| `playkit-js-kava` | Kaltura's own analytics bridge plugin | matches the repo's own GitHub description |
| `playkit-js-hotspots` | overlay UI rendered over the video area | `position: 'VideoArea'` in source |
| `playkit-js-detect-ad-block` | small, dependency-free plugin shape | `package.json` has no runtime `dependencies` key |
| `playkit-js-ima` | Flow-era plugin, predates the current TypeScript convention | `// @flow` pragma in source |
| `playkit-js-youbora` | Flow-era plugin, predates the current TypeScript convention | `flow-bin` devDependency in `package.json` |

## 11. Claude Code packaging (verified against code.claude.com, Claude Code 2.1.266)

Decisions this repo takes from that verification pass:

- `plugin.json`: only `name` is required; `displayName`, `version`, `license`, `keywords`, `homepage`, `repository`, `author` are real. `skills` adds to the default `skills/` scan; `commands` replaces `commands/`. Unknown fields are ignored unless `--strict`.
- `commands/` is legacy ("Use `skills/` for new plugins"). A skill is user-invocable by default and supports `argument-hint`, `arguments`, `$ARGUMENTS`, `disable-model-invocation`. Shipping `commands/build-plugin.md` and a skill creates two namespaced entries. **Drop the command; ship one skill.**
- SKILL.md frontmatter: `description` + `when_to_use` share a 1,536-char cap in Claude Code. `when_to_use` is a Claude Code extension and a **hard error** on portable paths (claude.ai upload, Skills API). Portable set is exactly `name, description, license, compatibility, metadata, allowed-tools`. Portable `description` cap is 1,024 chars, third person, what + when.
- Keep SKILL.md under 500 lines, references one level deep, longer reference files get a table of contents, scripts solve rather than defer, no magic constants, list runtime dependencies and check them.
- `claude plugin validate --strict .` passes only when there is no `CLAUDE.md` at the plugin root (it is not loaded as plugin context). Verified locally: moving it to `.claude/CLAUDE.md` clears the warning. `./.claude/CLAUDE.md` is a documented project-memory location, and `@path` imports resolve relative to the importing file, so `@../AGENTS.md` works (code.claude.com/docs/en/memory, "Project instructions" row and "Import additional files").
- Skills follow the open Agent Skills standard (agentskills.io). Which third-party tools implement it is **unverified**. `AGENTS.md` is an unrelated convention. A flattened single-file export still has a use for tools that read one prompt file and do not follow reference links.
- `claude plugin eval` is early access and gated per org; on this machine it prints "early access". Suite layout: `evals/<case>/prompt.md` + `graders/*.md` (`regex`, `tool_used`, `tool_order`, `file_exists`, `llm`, `baseline`). Distinct from the `skill-creator` plugin's `evals/evals.json` loop, which is generally available. `/skill-doctor` (2.1.252+) reports usage only.
- Marketplace, re-checked 2026-09-09 against code.claude.com/docs/en/plugin-marketplaces.md, discover-plugins.md, plugins.md:
  - Self-hosted: `.claude-plugin/marketplace.json` with `name`, `owner`, `plugins[]` of `name` + `source`. `source: "./"` is valid when the plugin is the marketplace root (the "shared skills folder" section). Users run `/plugin marketplace add kaltura/<repo>` then `/plugin install playkit-js-plugin-builder@<marketplace-name>`. `claude plugin validate .` validates `marketplace.json` too.
  - Official `claude-plugins-official`: no application process. Anthropic curates at its discretion; the only route is an existing Anthropic partner contact.
  - Community `claude-community` (`anthropics/claude-plugins-community`): submit via the Console form at platform.claude.com/plugins/submit (individuals) or the claude.ai admin directory form (Team/Enterprise). Run `claude plugin validate` first; review reruns it plus automated safety screening. Approved plugins are pinned to a commit SHA; the catalog syncs nightly.
  - README guidance is only "include installation and usage instructions". `homepage` is surfaced in the plugin UI; `repository` is a documented field.
- `claude plugin eval` and `/skill-doctor` are absent from the public docs as of 2026-09-09. Everything above about them comes from the local CLI's own output and help. Decision: not used. Own harness instead, built on `claude -p --plugin-dir <path> --output-format json --json-schema <schema> --max-budget-usd <n> --permission-mode <mode>` (all present in `claude --help`, 2.1.266) and Anthropic's develop-tests guidance (platform.claude.com/docs/en/test-and-evaluate/develop-tests): specific measurable criteria; code-based grading first, LLM grading with detailed rubrics, reasoning before a binary or ordinal verdict; more automated cases beat few hand-graded ones; compare against a baseline.

## 12. Composable skills in this environment

| Skill | Reuse for | Fallback if absent |
|---|---|---|
| `authoring-kaltura-docs` | README/guide/demo in Diátaxis structure and Kaltura voice | manual Diátaxis outline in `reference/docs-and-demo.md` |
| `security-review` | security pass before "done" | checklist in `reference/security-checklist.md` |
| `code-review`, `simplify` | final correctness pass | `reference/coding-guidelines.md` self-check |
| `karen` | deterministic quality gate | lint + type-check + build + tests + audit, all green |
| `harnessed-build` | spec → harness → implement → verify loop | 9-phase table in the plan |
| `rename-plugin` (inside the template, internal mode) | rename step | not needed in community mode |

## 13. Market and best-practice findings (2026-09-09, live sources)

What changes the design:

| Finding | Source | Consequence |
|---|---|---|
| Unscoped npm `kaltura-player-js` has a known-malicious version (OSV MAL-2025-41390, >=1.0.1) | ossf/malicious-packages | Only `@playkit-js/kaltura-player-js` is allowed. Lint hard-fail on the bare name. |
| Official `playkit-js-plugin-generator` last pushed 2020 | GitHub | Template is `playkit-js-plugin-example`; never the generator. |
| Kaltura house style: TS + webpack 5 + babel + `@microsoft/api-extractor` + standard-version + Cypress, externals as `root KalturaPlayer.*` | template `webpack.config.js`, `package.json` | Community scaffold matches it. No Vite/tsup in v1. |
| SaaS players run only plugins Kaltura whitelists in the bundler; no self-service registry | Kaltura KB, Annoto docs | Generated docs must say this. Self-hosted embeds load the script directly. |
| Only one production third-party PlayKit-JS plugin vendor found (Annoto) | GitHub search | Third-party plugin authoring is under-served; no prior art to copy. |
| No vendor (Video.js, JW, Bitmovin, Shaka, Vidstack) has a modern plugin scaffold; no Claude/Cursor skill targets this | vendor docs, skill directories | Design from first principles (OWASP, WCAG, CI hardening). |
| npm 12 (2026-07) default-denies install scripts, git deps, URL deps | github.blog, docs.npmjs.com | CI needs an explicit browser install step for Playwright/Cypress. |
| Cypress WebKit still experimental; Playwright has full WebKit | Cypress changelog 2026-09-01, State of JS 2025 | Playwright default in community mode; Cypress in internal mode (template). |
| GitHub Actions hardening: SHA pins, `permissions: {}` then per job, Dependabot for npm and actions, OIDC Pages deploy, OpenSSF Scorecard checks | step-security, ossf/scorecard | Community workflow templates ship this. |
| `npm audit --audit-level=high` plus `google/osv-scanner` action | OSV | CI gate. |
| jsDelivr: static tags cache forever, `@latest` 7 days; never SRI with `@latest`; prefer `/npm/` over `/gh/` when on npm; 20 MB/file, 150 MB/repo | jsdelivr.com docs | Docs and demo pin exact tags with SRI. |
| OWASP: no `innerHTML`/`eval` on untrusted data; `postMessage` explicit origin and exact allow-list; strict CSP compatible; Trusted Types newly Baseline | OWASP cheat sheets, caniuse | Security checklist items and lint rules. |
| WCAG 2.2 SCs 2.1.1, 2.4.7, 2.4.11 (focus not obscured); APG slider pattern; Kaltura Player V7 VPAT Sept 2024 | w3.org, knowledge.kaltura.com | UI branch a11y checks; docs cite the VPAT as baseline. |
| Diátaxis, Keep a Changelog 1.1.0, SemVer 2.0.0, Conventional Commits 1.0.0 all current | respective sites | Release and docs conventions unchanged. |

Not verified in that report: npm provenance / Trusted Publishing current state, Socket.dev CI features, exact VPAT PDF URL, a canonical 2026 README guide.

## 14. Open gaps (say so, do not guess)

- Internal registry reachability depends on the operator's Kaltura org token. Detect or ask.
- Multi-language i18n: mechanism verified (§6.3). Not verified: whether Kaltura SaaS player configs accept a per-locale `ui.translations` block from the partner side, or only from the plugin bundler. Check before promising SaaS multi-language.
- No Kaltura plugin security doc exists. Security guidance is synthesized from general web-plugin practice.
- No Kaltura a11y doc exists (§6.5).
- Single-repo self-marketplace layout documented as valid (§11) but not yet install-tested from GitHub here.
- npm Trusted Publishing (OIDC) current state not re-verified (§13). Check before recommending it in `release-and-versioning.md`.
- Trusted Types: engines (hls.js, dash.js, shaka) not grepped for sinks (§6.6). Verify when the e2e page is switched to an HLS/DASH source.
- Unisphere (§16): the loader is fetched at runtime with a dynamic `import()` of a URL. Not verified whether that works under an enforcing `require-trusted-types-for 'script'` CSP, and the Unisphere CSP guide never mentions Trusted Types. Test before promising it for the Unisphere consumer branch.
- Unisphere: which partners are entitled to which runtimes, and how a runtime is activated for a partner, is not visible from the plugin repos. Ask the operator; do not assume a runtime is available on their account.
- Unisphere: `provider.unisphereLoaderUrl` is set by the Kaltura embed on SaaS. The correct production value for a self-hosted player is not documented publicly. Only a QA-region URL appears in public demo pages.
- Unisphere: `pluginManager` returned by `getService('unisphereService')` is untyped (`any`) in the published d.ts, and `package.json` has no `types` field. Generated code needs a local type shim.
- Unisphere: the docs name packages that do not exist on npm (`@unisphere/workspace-loader`, `player-core`, `analytics-core`, `loader`, `reactions-types`, `media-manager-types`, `genie-chat-types`). npm is the source of truth for what is installable.
- Unisphere: two id discrepancies between docs and code. Genie widget is `unisphere.widget.genie` in the plugin, `kaltura.widget.genie` in docs. Analytics service is `unisphere.service.kaltura-analytics` in the API reference, `unisphere.service.analytics` in an overview page. Read the id from the runtime you target, never from memory.

## 15. Errors in the first draft (do not reintroduce)

| Draft said | Correct |
|---|---|
| `static isValid(player)` | `static isValid()` takes no args |
| config "merged automatically" | shallow spread at construction, deep merge only in `updateConfig` |
| `Error(Severity, Category, Code, data)` | five args, `errorDetails?` last; constructing always logs |
| dispatch with `player.Event.ERROR` per `docs/errors.md` | doc uses nonexistent `player.Event.Error`; use `player.Event.Core.ERROR` |
| event namespaces Core + UI | also Cast, Playlist, flat back-compat spread |
| `getUIComponents` "merges into config.ui.uiComponents" | duck-typed, each item passed to `addComponent` |
| area list of 13 values | 18 values; SidePanel* and PlayerArea were missing |
| plugin `translations/*.i18n.json` "read by preact-i18n" | not auto-loaded; host page must pass `ui.translations` |
| aws-analytics is "plain TypeScript, tsc-only, custom release script replacing standard-version" | webpack 5 + babel; release script wraps standard-version; `destroy()` skips `super.destroy()`; e2e hits live network |

## 16. Unisphere (verified 2026-09-09)

Sources: `kaltura/unisphere-documentations` @ `194490c` (repo is `internal` visibility on GitHub),
the three plugin repos and the legacy one in the SHA table (also `internal`), `kaltura/unisphere-video-summary`
@ `9b9149b` (a runtime, `internal`), `kaltura/playkit-js-providers` @ `2b40f86` (`public`), and
`registry.npmjs.org` for what is installable. Raw fact sheets were produced by four research passes
(docs, plugins, runtime, org survey) and cross-checked against each other.

**Correction, 2026-09-09 (second pass, prompted by the repo owner):** the first pass wrongly concluded
"the docs site returns 403 for every `/docs/*` page" and treated the docs as unreadable outside Kaltura.
That was checked again live against `https://unisphere.kaltura.com/` (not the GitHub repo) and is false.
The site is a public Docusaurus deployment (`kaltura-unisphere.vercel.app` behind that domain,
`robots.txt` disallows crawling/indexing but not direct access). `getting-started/*`, `learn/*`, and
`api/*` pages return 200 with no login; the one 403 found was `getting-started/load-unisphere`, a URL
the first pass guessed by analogy with the internal repo's file path — the real, live path is
`getting-started/loader`. §16.2 and §16.9 below are corrected accordingly. The site itself warns
"This documentation is currently in early stage and subject to change" and several sub-pages (e.g.
`getting-started/services/overview`, `api/core/workspace`) are marked "WORK IN PROGRESS" — treat those
as unstable, not as evidence of gating.

### 16.1 What it is

Docs overview: "Unisphere is a runtime platform that delivers interactive experiences as self-contained modules. Instead of building features from scratch, you load them dynamically into your application through a workspace that manages lifecycle, configuration, and coordination."

| Term | Meaning (docs glossary) |
|---|---|
| Workspace | Runtime environment on the page that loads runtimes and provides shared services. One per app, or one per player. |
| Experience / widget | Top-level product, id like `unisphere.widget.video-summary`. Contains runtimes, visuals, packages. |
| Runtime | Self-contained JS bundle, the "brain". `class Runtime extends UnisphereRuntimeBase`. Registers visual types. |
| Visual | UI mounted into a host element via `runtime.mountVisual({type, settings, target})`. |
| Service | Singleton shared by all runtimes: pub-sub, storage, user-settings, theme, iframes, utils, logger, kaltura-analytics. |
| Flavor | Alternate entry point of a runtime for a host context. `player-plugin` is one. Docs call flavors "not the default approach". |
| Package | npm-distributed shared code (`@unisphere/*`, `@kaltura-apps/*`, `@kaltura-sdk/*`). |

Built-in services, all `workspace.getService<T>(id)` and all extend `UnisphereService {id, kill()}`:

| id | Key methods |
|---|---|
| `unisphere.service.pub-sub` | `emit(event, options?)`, `subscribe(event, cb)` |
| `unisphere.service.storage` | `get(ns, prop)`, `update(ns, prop, value, options?)`, `subscribe(listener, options)` |
| `unisphere.service.user-settings` | `getLanguage()`, `setLanguage()`, `onLanguageChanged()`, legal-consent getters and setters |
| `unisphere.service.theme` | `setTheme()`, `onThemeChanged()`, `injectStyles(widget, runtime, styles[])`, `getNonce()` |
| `unisphere.service.iframes` | `onQuery()`, `notifyAll()` |
| `unisphere.service.utils` | `createOrGetVisual()`, `removeVisualFromBody()`, `validateSchema()`, `getRuntimeStyles()` |
| `unisphere.service.logger` | `getOrCreateLogger(type, name, options?)` |
| `unisphere.service.kaltura-analytics` | `registerUnisphereApp()`, `report(appId, data)`, `getAnalytics()` |

Host loading, vanilla JS: `import('${serverUrl}/loader/index.esm.js')` → `fetchAndLoadUnisphereWorkspace({workspaceName, appId, appVersion, serverUrl, ui: {language, theme}})` → `workspace.loadRuntime(widgetName, runtimeName, settings, flavor?)` → `runtime.mountVisual(...)`. `ui.language` is mandatory. Region is derived from `serverUrl`. Loading the workspace needs no `ks` or `partnerId`; Kaltura-backed runtimes (Genie) take `{partnerId, ks, kalturaServerURI}` in their settings. To attach to a workspace another script already created: `getUnisphereInstance(workspaceId)`, which waits for the `unisphere-ready` DOM event. The loader is served by the region server; there is no `@unisphere/loader` on npm.

The public docs (`getting-started/loader`, live 2026-09-09) also document a second, declarative shape
for the same npm-package integration path — a full `UnisphereWorkspaceConfig` object that can list
`runtimes[]` (each with `widgetName`, `runtimeName`, `flavor?`, `settings`, and inline `visuals[]`)
directly in the config passed at workspace-load time, instead of calling `loadRuntime`/`mountVisual`
imperatively afterward:

```ts
// from @unisphere/runtime
interface UnisphereWorkspaceConfig {
  workspaceName?: string;
  serverUrl: string;
  devops?: { fetchStrategy?: 'scripts' | 'esm' };
  runtimes?: {
    widgetName: string;
    runtimeName: string;
    flavor?: string;
    settings: Record<string, any>;
    ui?: { bodyContainer?: { zIndex?: number } };
    visuals?: { type: string; target: UnisphereVisualTarget; settings: Record<string, any> }[];
  }[];
  ui?: { theme?: 'light' | 'dark' | object; language?: string; bodyContainer?: { zIndex?: number } };
  appId: string;
  appVersion: string;
}
```

Page is marked "WORK IN PROGRESS" for prose but the type itself is given in full; treat the type as
current and the surrounding explanation as incomplete. There is also a "Single-Experience Embed (CDN)"
option: load the workspace straight from the region CDN with no npm install and no build step, for a
page that only needs one or two experiences.

### 16.2 Public vs. internal

| Capability | Who | Evidence |
|---|---|---|
| Read the consumption docs (`unisphere.kaltura.com/docs/getting-started/*`, `/learn/*`, `/api/*`) | **Anyone**, no login, no GitHub org | live check 2026-09-09; site says "Join thousands of developers who are already building" |
| Install `@unisphere/*`, `@kaltura-apps/*`, `@kaltura-sdk/*`, `@playkit-js/unisphere-*` from npm | **Anyone** | registry.npmjs.org, 2026-09-09. AGPL-3.0 unless noted below |
| Load a workspace and an already-deployed runtime, via npm packages or the CDN loader (`getting-started/loader`) | **Anyone** with a loader URL and, for Kaltura-backed runtimes, a ks | live docs page 2026-09-09; no auth on workspace load |
| Read the `unisphere-documentations`/plugin/runtime source repos on GitHub directly | Kaltura org members (repos are `internal` visibility) | `gh repo view`, 2026-09-09. Not required to consume — the public site covers consumption |
| Create a new experience/runtime (the "Create" track) | Kaltura employees; "If you're exploring partnerships or custom integrations, you can contact Kaltura" | live docs page `create/overview`, 2026-09-09: "The Create environment is currently available only to Kaltura developers" |
| Deploy, activate a version | Kaltura employees only | docs pages carry "Kaltura employees only" / "Closed Access" warnings; deploy uses `@unisphere/cli` and org-internal GitHub workflows |
| Resolve `@kaltura-corp/*` packages | Kaltura employees only | internal registry with a token in `.npmrc`; never copy that file |

Consequence for the skill: **community mode can consume existing runtimes — using only the public site
and public npm, no internal access needed — but cannot author or deploy new ones (or a partner can ask
Kaltura). Internal mode can do both, and may additionally read the internal source repos for
implementation-level fidelity.**

### 16.3 npm status

Installable, checked 2026-09-09 (AGPL-3.0 unless noted):

| Package | Version | Note |
|---|---|---|
| `@unisphere/core` | 1.100.0 | workspace core, from `kaltura/unisphere-core` |
| `@unisphere/runtime` | 1.99.0 | `UnisphereRuntimeBase` and types |
| `@unisphere/runtime-js` | 1.97.0 | `fetchAndLoadUnisphereWorkspace`, `getUnisphereInstance`, `normalizeLanguageCode` |
| `@unisphere/runtime-react` | 1.92.0 | `ScopedUnisphereWorkspaceProvider`, hooks. React, not Preact |
| `@unisphere/cli` 6.1.3, `nx` 5.0.2, `dev` 3.12.3, `create-unisphere-project` 3.4.1 | | authoring toolchain; deploy paths need employee access. `cli` has no license field |
| `@unisphere/genie-core` 1.8.0, `genie-types` 1.39.4 | | Genie chat |
| `@unisphere/ui-i18n-react` 1.71.0, `ui-types` 2.1.0, `ui-core` 1.4.0, `ui-runtime-react` 1.0.1, `ui-markdown-react` 1.0.0, `ui-kaltura-player-react` 2.1.0 | | UI helpers; `ui-kaltura-player-react` is "React wrapper for Kaltura Player" |
| `@unisphere/notifications-core` 1.25.0, `notifications-types` 1.28.1, `notifications-runtime-react` 1.27.1 | | notifications experience |
| `@unisphere/content-lab-core` 1.2.4, `rtc-types` 1.13.1, `hello-types` 1.0.1, `dx-types` 1.3.0, `models-sdk-types` 1.8.1 | | other experiences |
| `@kaltura-sdk/avatars` 1.16.1, `rtc-avatar` 1.33.1; `@kaltura-apps/genie-chat-react` 1.7.4 | | headless and app-level wrappers |
| `@playkit-js/unisphere-service` | 0.0.27 | the player-side workspace owner. Peers `@playkit-js/kaltura-player-js 3.17.71`, `preact 10.4.6`, `preact-i18n 2.0.0-preactx.2`. No `types` field in `package.json`; d.ts ships in `dist/` |
| `@playkit-js/unisphere-summary` | 1.1.6 | reference consumer plugin |
| `@playkit-js/unisphere-genie` | 0.0.29 | consumer plugin, flavor `player-plugin` |
| `@playkit-js/unisphere` | 0.0.30 | legacy, creates its own workspace; superseded by `unisphere-service` |
| `@playkit-js/ui-managers` | 1.9.2 | Apache-2.0; side panels and upper bar, used by `unisphere-service` |

Named in the docs but **404 on npm**: `@unisphere/workspace-loader`, `player-core`, `analytics-core`, `loader`, `reactions-types`, `media-manager-types`, `genie-chat-types`. Rule: `npm view <pkg> version` before depending on anything.

### 16.4 How the player reaches Unisphere: `provider.unisphereLoaderUrl`

- `unisphereLoaderUrl?: string` is a field of the provider options in `kaltura/playkit-js-providers` `src/types/provider-options.ts:19`.
- The Kaltura SaaS embed writes it into the player config server-side (server module `extwidget/actions/embedPlaykitJsAction.class.php`, loader-URL builder). SaaS embeds therefore have it without operator action. Self-hosted or custom embeds set `provider.unisphereLoaderUrl` themselves.
- The plugins read it as `player.config.provider.unisphereLoaderUrl` behind a `@ts-ignore` and a `// TODO remove once this is added to providers.env` comment (`unisphere-service/src/unisphere-plugin-manager.tsx:127-137`). Guard for absence.
- Public demo pages (for example Kaltura's advanced-audio-description demo) use a QA-region URL under `unisphere.<region>.ovp.kaltura.com/v1`. Production values for self-hosted players are not documented publicly (§14).

### 16.5 Footprint in the player org

102 `playkit-js*` repos surveyed. Exactly four depend on `@unisphere/*`: `playkit-js-unisphere-service`, `-summary`, `-genie`, `-unisphere`. The core player repos (`kaltura-player-js`, `playkit-js-ui`, `playkit-js-providers` (apart from the one config field), `playkit-js-plugin-example`) contain no Unisphere references. About 35 `unisphere-*` workspace repos exist (agents, analytics, avatar, content-lab, genie-studio, in-app-messaging, media-manager, notifications, reactions, recorder, rtc, video-summary, vod-avatars, and more); `unisphere-player` is an empty scaffold (`runtimes: {}`). A few other Kaltura front-end products consume Unisphere too, not named here.

So Unisphere is a contained, opt-in layer on top of the player, not a replacement for the plugin SDK. Everything in §1 to §7 still applies to a Unisphere consumer plugin.

### 16.6 The service-plus-consumer pattern (what to copy)

`@playkit-js/unisphere-service` (`PLUGIN_NAME = 'unisphereService'`, `defaultConfig {widgets: []}`):

- Constructor: `player.registerService('unisphereService', { pluginManager: this._unispherePluginManager, eventService: UnisphereEventService })` (`src/unisphere-plugin.ts:18-25`).
- `pluginManager.getWorkspace()` (`src/unisphere-plugin-manager.tsx:123-148`): memoized. Calls `fetchAndLoadUnisphereWorkspace({serverUrl: <unisphereLoaderUrl>, workspaceName, appId: 'kaltura-player', appVersion: '', ui: {theme: 'light', language: 'en'}})` or `getUnisphereInstance(...)` to attach to an existing one.
- `pluginManager.initRuntime(runtime, integrations, sidePanelConfig)` (`:192-269`): creates the side panel and upper-bar icon through `sidePanelsManager` and `upperBarManager` (`ServiceKeys`, `src/types/service-keys.ts`), renders a Preact `ContainerElement` (`<div id>`), waits for it (100 ms poll, 5 s cap), then `mountRuntimeToContainer` (`:271-282`) calls `runtime.mountVisual({type: layout.sidepanel.visualType, settings: layout.sidepanel.visualSettings, target})`.
- Also: `activateByWidgetName(name)`, `getByWidgetName(name)` (`:334-351`), `updateButtonVisibility(id, visible)`, `getButtonVisibility(id)` (`:314-332`), `revealUpperBarIconForWidget(name)` for `header.deferIcon`, `reset()`, `destroy()`.
- `updateSessionData` writes `{entryId, ks, entryName}` to storage namespace `player`, key `player-session` (`:367-373`). Runtimes read it from there.
- `UnisphereEventService` wraps `unisphere.service.pub-sub`; `UnisphereStorageService` wraps `unisphere.service.storage` in namespace `player`. All three services are static singletons, so **one workspace per page**. `destroy()` calls `workspace.kill()`.
- Published d.ts exports only the integration types: `UnisphereIntegrations`, `UnisphereIntegrationLayout`, `UnisphereIntegrationHeader`, `UnisphereIntegrationLayoutHeader`, `UnisphereIntegrationSidepanel`, `UnisphereIntegrationButton`, `PlayerEvent`, `UnisphereEvent`. `pluginManager` is `any`.

Consumer plugin, `@playkit-js/unisphere-summary` (`PLUGIN_NAME = 'summary'`):

1. `player.getService('unisphereService')` (`src/unisphere-summary-plugin.tsx:82-87`). Absent service means the plugin stays inert.
2. `pluginManager.getWorkspace()` → `workspace.loadRuntime('unisphere.widget.video-summary', 'kaltura-player-list', {})`.
3. Build `UnisphereIntegrations {schema: 1, layouts: [{presets: ['Playback'], type: 'sidepanel', header: {icon, tooltip, deferIcon}, sidepanel: {header: {type: 'buttons', title, showCloseButton, buttons}, visualType, visualSettings}, mountWhileHidden}]}` (`src/integration-config.ts`), then `pluginManager.initRuntime(runtime, integrations, sidePanelConfig)` (`:165`).
4. Push player state into storage namespace `player`: `currentTime`, `isPaused`, `isSmallSize`, `isShare`, `allowDownload`, `allowShareChapter`, `layout`, `selectedChapter`, `downloadClicked`.
5. Subscribe to runtime events on pub-sub, prefix `unisphere.event.player.*`: `upper-bar-icon.show`, `upper-bar-icon.click`, `side-panel.open|close|toggle|opened|closed`, `set-value.current-time`, `chapters.add` (bridged to the `timeline` service `addKalturaCuePoint`), `resize`, `dispatch-event`.
6. A second visual (`chapter-title`) is mounted through `player.ui.addComponent({label, presets: ['Playback'], area: 'BottomBarCenterControls', get: () => <div id={containerId}/>})` (`:384-407`).
7. One `AbortController` per `loadMedia`; skips clips; `destroy()` calls `super.destroy()` then `pluginManager.destroy()`.

Genie (`@playkit-js/unisphere-genie`) follows the same steps with widget `unisphere.widget.genie`, runtime `chat`, flavor `player-plugin` as the fourth `loadRuntime` argument, settings `{context: {type: 'entry', id}, ks, partnerId, shareUrl, agentMode}`, `defaultConfig {fallbackToPlayerKS: false, position: RIGHT, expandMode: ALONGSIDE, expandOnFirstPlay: false}`. `ks` comes from plugin config, with `player.config.session.ks` as fallback only when `fallbackToPlayerKS` is true.

Build facts shared by all three: webpack UMD `['KalturaPlayer', 'plugins', '<name>']`, externals `KalturaPlayer*` plus react mapped to `KalturaPlayer.ui.preact`, api-extractor, `standard-version`, internal reusable workflows, `kaltura.dependencies` pins, AGPL-3.0.

Do **not** copy: `npm test` is `echo 'TODO'` in all four repos; Cypress specs are the unmodified template boilerplate; i18n is one unmodified `en` file with real strings hardcoded in TSX; the `.npmrc` with registry tokens.

### 16.7 The runtime side (internal mode only)

From `kaltura/unisphere-video-summary` @ `9b9149b`:

- `.unisphere` manifest, `schemaVersion 2.0.0`, `elements.runtimes['kaltura-player-list'] {sourceRoot, distributionChannel: 'unisphere'}`. Widget id is a constant in a `types` package (`widget-types.ts`).
- `class Runtime extends UnisphereRuntimeBase` (`runtime.tsx`). Registers `visualTypes` `chapter-title` and `summary-list` (singleton, JSON schema for settings). `_createVisualContainer` is `ReactDOM.createRoot(htmlElement)`: React 19, no shadow DOM, no iframe. The plugin side is Preact through the player. The two trees are disjoint DOM subtrees in one document.
- Visuals are wrapped in `ScopedUnisphereWorkspaceProvider` (`@unisphere/runtime-react`), `UnisphereI18NRuntimeProxy` (`@unisphere/ui-i18n-react`) and a `ThemeProvider` from Kaltura's design-system package. Reads `player-session` from storage. Env name from `workspace.getEnvName()`.
- Local dev: `@unisphere/dev` playground; `devOverrides.modules[widgetName][flavorKey] = {version, url}` points a widget at a local build. Deploy and activate are separate `@unisphere/cli` steps, employees only.

### 16.8 CSP and theming

Host sets `window.kalturaGlobalConfig = { stylesNonce, scriptsNonce }` before any Kaltura script. Docs: applied "to all Unisphere visuals, Kaltura Player, Kaltura Mediaspace". `theme.getNonce()` returns the style nonce. No Unisphere doc mentions Trusted Types (§14).

### 16.9 Design consequence for the skill: Unisphere-first

Two layers, both mode-aware.

1. **Capability already exists as a Unisphere runtime** (video summary, Genie chat, and any runtime the operator names or that is listed in the workspace manifest they can reach): build a **thin consumer plugin** on `@playkit-js/unisphere-service`, exactly the `unisphere-summary` shape. Do not reimplement the feature, the side panel, the icon, the workspace load, or the pub-sub bridge. Works in both modes, subject to the operator's loader URL and runtime entitlement.
2. **Capability does not exist as a runtime**: community mode falls back to the three classic branches (§7). Internal mode may author a new runtime plus a thin consumer plugin, using the shape in §16.7.

Reading up on this branch requires no internal access: `unisphere.kaltura.com/docs` (getting-started,
learn, api sections) is public, as are the npm packages. Only the plugin repos' exact source (for
implementation-level fidelity) and the "Create" track (authoring a new runtime) need Kaltura org
membership or employee status (§16.2).

When a workspace is present, prefer its services (pub-sub, storage, user-settings for language, theme and nonce, logger, kaltura-analytics) over hand-rolled equivalents. Never load a second workspace on the page; always go through `getService('unisphereService')`.
