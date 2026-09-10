# Unisphere integration: the consumer branch

Every fact below traces to `docs/plans/2026-09-09-plugin-skill-research.md` §16 (plugins at pinned
SHAs, npm registry checked 2026-09-09). Unisphere is Kaltura's runtime platform: features ship as self-contained **runtimes** loaded into a
**workspace** on the page, with shared **services** (pub-sub, storage, user-settings, theme, logger,
analytics). Kaltura's newest player features (AI video summary, Genie chat) are Unisphere runtimes.
The player reaches them through one plugin, `@playkit-js/unisphere-service`, and thin consumer
plugins on top of it.

**Consuming Unisphere needs no internal access.** The consumption docs
(`https://unisphere.kaltura.com/docs/getting-started/*`, `/learn/*`, `/api/*`) and every npm package
named below are public: no Kaltura login, no GitHub org membership. Only two things are gated to
Kaltura employees: reading the exact source of the reference plugins (their GitHub repos are
`internal` visibility) and *authoring a new* runtime (the docs say so explicitly: "The Create
environment is currently available only to Kaltura developers... If you're exploring partnerships or
custom integrations, you can contact Kaltura."). Don't tell an operator they need internal access to
build a consumer plugin; they don't.

**"No login needed" is not the same as "the latest version installs cleanly."** Live-verified during a
dry run (2026-09-09): `@playkit-js/unisphere-service`'s newest published version at that time (`0.0.27`)
has a broken dependency tree on the public registry — its dependency `@unisphere/genie-core@^1.8.0`
requires `@kaltura-corp/unisphere-rtc-core@^1.18.0`, which 404s (no such package is published
publicly). This is a supply-chain state, not an access gate, and it can change (fixed, or broken
differently) at any time. Before pinning a version: `npm view @playkit-js/unisphere-service versions`,
then try installing the newest candidate in isolation; if it fails, walk back through older versions
until one installs (`0.0.20`-`0.0.24` were confirmed installable as of that date, each pinning
`@unisphere/genie-core` to an exact, dependency-free version). Whatever version you land on also fixes
the required `@playkit-js/kaltura-player-js` peer version — pin that peer to the exact version the
chosen `unisphere-service` release declares, not the template's default range. Record the exact
versions checked and why in `PLAN.md`; don't assume the versions in this paragraph are still current.

**Rule: if the requested capability already exists as a Unisphere runtime, build a thin consumer
plugin. Do not rebuild the feature, the side panel, the icon, the workspace load, or the event
bridge.** If no runtime matches, use the classic branches in `reference/decision-tree.md`.

## 1. When this branch applies (phase 0)

- Ask, in this order, and record the answer in `PLAN.md`:
  1. Does the operator name a Unisphere runtime, or does the prompt match a known one?
     Known today (research §16.6): `unisphere.widget.video-summary` runtime `kaltura-player-list`
     (summary and chapters side panel), `unisphere.widget.genie` runtime `chat` with flavor
     `player-plugin` (AI chat side panel). Other documented experiences (reactions, notifications,
     media-manager, in-app-messaging) have no player-side consumer yet; treat them as candidates
     only if the operator confirms the runtime accepts a player host.
  2. Can the operator's player reach a workspace? Kaltura SaaS embeds set
     `provider.unisphereLoaderUrl` server-side. Self-hosted players must set it by hand and the
     production value is not documented publicly (research §14). If unknown, default to the branch
     anyway and mark the loader URL and runtime entitlement as the one open question. **Stay
     agnostic in code**, not just in `PLAN.md`: guard on `player.config.provider?.unisphereLoaderUrl`
     being present and stay inert if it's missing (research §16.6 pattern), rather than assuming a
     SaaS embed and hardcoding that path. The open-question disclosure and the code's behavior must
     match; don't disclose the gap in `PLAN.md` while the code silently assumes one answer to it.
- Output of this step is one line in `PLAN.md`, **verbatim, word for word** (this exact line is a
  grep check in the e2e evals — don't paraphrase it):
  - Match found: `Unisphere: <widget id> / <runtime>` (for example `Unisphere:
    unisphere.widget.video-summary / kaltura-player-list`).
  - No match: `Unisphere: no Unisphere runtime covers this (checked research §16.6 and operator
    input)`. Note both words: "no **Unisphere** runtime", not "no runtime" — write the line exactly
    as shown here, don't reword it to "not a Unisphere-runtime match" or similar.
- Community and internal mode both consume runtimes. Only internal mode may author a new runtime.

## 2. Consumer plugin recipe (phase 2)

Copy the `unisphere-summary` shape (research §16.6). Every bullet is a grep check.

- Dependencies: `@playkit-js/unisphere-service` as a dependency (its own deps bring
  `@unisphere/core`, `runtime`, `runtime-js`). Never import `@unisphere/runtime-js` directly and
  never call `fetchAndLoadUnisphereWorkspace` or `getUnisphereInstance` from the plugin. One
  workspace per page; the service plugin owns it.
- Entry: in `loadMedia()` (not the constructor; services are registered by other plugins) do
  `const svc = player.getService('unisphereService')`. If absent, log once and stay inert. Guard
  `player.config.provider?.unisphereLoaderUrl` the same way.
- Workspace and runtime: `const workspace = await svc.pluginManager.getWorkspace()`, then
  `const { runtime } = await workspace.loadRuntime(widgetId, runtimeName, settings, flavor?)`.
- Layout: build a `UnisphereIntegrations` object (`schema: 1`, `layouts: [{presets, type:
  'sidepanel', header: {icon, tooltip, deferIcon}, sidepanel: {header, visualType, visualSettings},
  mountWhileHidden}]`) typed against the exports of `@playkit-js/unisphere-service`, then
  `svc.pluginManager.initRuntime(runtime, integrations, sidePanelConfig)`. This creates the side
  panel and upper-bar icon and mounts the visual. No direct `sidePanelsManager` calls.
- Extra visuals outside the panel: `player.ui.addComponent({label, presets, area, get: () => <div
  id={containerId}/>})` then `runtime.mountVisual({type, settings, target})` once the element exists.
- State to the runtime: `UnisphereStorageService` (namespace `player`); the service plugin already
  writes `player-session` `{entryId, ks, entryName}`. Push only what the runtime's settings schema
  declares.
- Events from the runtime: `svc.eventService.subscribe('unisphere.event.player.<name>', cb)`.
  Known names: `upper-bar-icon.show|click`, `side-panel.open|close|toggle|opened|closed`,
  `set-value.current-time`, `chapters.add`, `resize`, `dispatch-event`. Bridge to player APIs
  (`player.currentTime`, `timeline` service) in the plugin, never in the runtime.
- Lifecycle: one `AbortController` per `loadMedia`, aborted in `reset()`. `reset()` calls
  `svc.pluginManager.reset()`. `destroy()` calls `super.destroy()` and `svc.pluginManager.destroy()`.
  Everything in `reference/base-plugin-api.md` still applies.
- Credentials: a `ks` in plugin config is the operator's choice. Fall back to
  `player.config.session.ks` only behind an explicit `fallbackToPlayerKS: true` (genie pattern).
  Never log the ks or write it to storage beyond what the service plugin already does.
- Types: `pluginManager` is `any` in the published d.ts and `package.json` has no `types` field.
  Ship a local `unisphere-service.d.ts` shim covering the methods you call, and pin the exact
  `@playkit-js/unisphere-service` version you typed against.
- Prefer Unisphere services over hand-rolled equivalents when a workspace is present: pub-sub for
  cross-plugin messages, storage for shared state, user-settings for language, theme for CSS nonce,
  logger for scoped logs, kaltura-analytics for reporting. Do not create a second event bus.
- If the operator has no other source, the public docs alone are enough to build the workspace side
  (`getting-started/loader` covers npm-package and CDN-embed integration, `api/core/workspace` gives
  the `UnisphereWorkspaceConfig` type, `getting-started/guides/csp` gives the nonce contract). The
  `@playkit-js/unisphere-service` consumer recipe above still needs the shape from research §16.6,
  which was read from the (internal) plugin source; if that source is unreachable, fall back to the
  public `UnisphereWorkspaceConfig.runtimes[]`/`visuals[]` shape directly and skip the service plugin.

## 3. Do not copy from the reference plugins

`npm test` is `echo 'TODO'`, Cypress specs are unmodified template boilerplate, i18n is one
unmodified `en` file with strings hardcoded in TSX, and `.npmrc` carries registry tokens. Use
`reference/testing-strategy.md`, `reference/ui-components.md` (i18n contract) and
`reference/security-checklist.md` instead.

## 4. Tests (phase 3)

- Unit: stub `player.getService('unisphereService')` with a fake `{pluginManager, eventService}`
  and assert `getWorkspace`, `loadRuntime` (widget id, runtime name, flavor, settings), `initRuntime`
  layout, storage pushes and event subscriptions. Assert inert behavior when the service is absent.
- E2E: load the real `@playkit-js/unisphere-service` bundle plus this plugin;
  `provider.unisphereLoaderUrl` from `UNISPHERE_LOADER_URL`. Skip (do not fail) when unset and print
  the skip reason. Trusted Types on this page is informational until research §14 closes the gap.

## 5. Docs and demo (phase 4)

- README states: requires `@playkit-js/unisphere-service` loaded first, requires a workspace
  (SaaS: automatic; self-hosted: set `provider.unisphereLoaderUrl`, value from Kaltura), requires
  the runtime to be enabled for the partner, and which `ks` privileges the runtime needs.
- Demo page loads both plugin bundles and reads the loader URL from a placeholder flagged for the
  operator. Never hardcode a Kaltura environment URL in tracked files.
- License note: `@unisphere/*` and `@playkit-js/unisphere-*` are AGPL-3.0. The generated plugin's
  license choice must be compatible; state the dependency licenses in the README.

## 6. Internal mode only: authoring a new runtime

Community mode stops at consuming. Internal mode may also create the runtime (research §16.7):
`unisphere-*` workspace repo from `create-unisphere-project`, `.unisphere` manifest, `class Runtime
extends UnisphereRuntimeBase` with registered `visualTypes` and JSON-schema settings, React 19
visuals wrapped in `ScopedUnisphereWorkspaceProvider` and the i18n proxy, `player-session` read
from storage, local dev through `@unisphere/dev` overrides, deploy and activate through
`@unisphere/cli` (employees only). The player-side plugin stays the thin consumer above. Do not
write runtime code into the plugin repo.

## 7. Known gaps (say so in PLAN.md, do not guess)

- Runtime entitlement and activation per partner: not visible from source. Ask.
- Production loader URL for self-hosted players: not documented publicly.
- Trusted Types with the dynamic `import()` loader: unverified.
- Docs name npm packages that do not exist; `npm view <pkg> version` before depending.
- Widget and service id discrepancies between docs and code (research §14). Use ids from the
  runtime you target.

## 8. Exit checks

- `grep -L "getService('unisphereService')" src/*.ts*` is empty for the consumer entry file.
- `grep -rn "fetchAndLoadUnisphereWorkspace\|getUnisphereInstance\|@unisphere/runtime-js" src/`
  returns nothing.
- `grep -n "super.destroy()" src/` and `grep -n "pluginManager.destroy()" src/` both hit.
- `PLAN.md` has the Unisphere line. README has the four requirements above.
