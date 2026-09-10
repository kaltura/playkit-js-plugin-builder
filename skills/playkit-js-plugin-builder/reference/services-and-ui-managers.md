# Services registry and ui-managers: the side-panel branch

This is the branch for a plugin that needs a side panel, an upper-bar icon, or that needs to publish
data another plugin can consume (like cue points). It is not `ui.addComponent` (that's
`reference/ui-components.md`) and it is not a Unisphere runtime (that's
`reference/unisphere-integration.md`, and you must rule that branch out first: research §16.9,
`reference/decision-tree.md`). Everything here is real behavior observed in two shipped Kaltura
plugins, `playkit-js-transcript` and `playkit-js-kaltura-cuepoints` (research §7).

**Rule: if the plugin needs a panel, tab, or overlay docked to the player chrome, or needs to expose
a value for other plugins to read, use the services registry and `@playkit-js/ui-managers`. Do not
build a floating `addComponent` div and call it a panel.**

## The API: `registerService` / `getService` / `hasService`

`KalturaPlayer` exposes three methods, string-keyed, at the player level (research §7:
`kaltura-player.ts:1214-1233`). They are not documented in Kaltura's public `writing-a-plugin.md`;
this file and the research doc are the only trace of them.

- `player.registerService(name: string, svc: any): void`: a plugin that owns a service calls this,
  usually in its constructor, so other plugins loaded later can find it.
- `player.getService(name: string): any`: returns the registered object, or `undefined` if nothing
  registered under that name. No type is enforced; you get back exactly what the provider passed to
  `registerService`.
- `player.hasService(name: string): boolean`: check before you call anything on the result of
  `getService`. Always guard with this; never assume a service exists.

There is no discovery mechanism and no event that fires when a service is registered. If you need a
service that hasn't been registered yet, you either wait for a specific lifecycle point (see
"Ordering" below) or you accept it may never appear and degrade gracefully.

## Known service names

Four are observed directly in shipped plugins (research §7):

| Service name | Registered by | What it's for |
|---|---|---|
| `sidePanelsManager` | Not confirmed (only that `playkit-js-transcript` and Unisphere's `pluginManager` both read it via `getService`, not who calls `registerService` for it; the classes live in `@playkit-js/ui-managers`) | Add, remove, open, close side panels |
| `upperBarManager` | Not confirmed, same caveat as `sidePanelsManager` | Add, remove upper-bar icons |
| `kalturaCuepoints` | `playkit-js-kaltura-cuepoints` | Cue point data other plugins can read |
| `AudioPluginsManager` | Not confirmed (research only shows `playkit-js-transcript` removing from it in `reset()`, not who registers it) | Not confirmed; name suggests audio-plugin coordination, don't assume more |

A fifth, `unisphereService`, is registered by `@playkit-js/unisphere-service` and wraps a whole
Unisphere workspace (side panel, upper-bar icon, pub-sub, storage) behind one object (research §16.6).
If the capability you need already exists as a Unisphere runtime, use that service through
`reference/unisphere-integration.md` and never call `sidePanelsManager`/`upperBarManager` yourself.
`pluginManager.initRuntime` does it for you internally (research §16.6, `unisphere-plugin-manager.tsx:192-269`).

**Known gap:** research confirms these four service names exist and that transcript
calls `getService('sidePanelsManager')` and `getService('upperBarManager')`, but neither source
records the exact method signatures on the returned objects (no `addPanel(...)` / `removePanel(...)`
signature was captured from `playkit-js-transcript` source). Don't invent method names from memory.
Before writing the call site: read the installed `@playkit-js/ui-managers` package's `.d.ts` (it's a
bundled devDependency, so it's in `node_modules/@playkit-js/ui-managers` once installed), or read
`playkit-js-transcript` source directly if you have access. State in `PLAN.md` that the exact API was
confirmed against the installed package version, not assumed.

## Two roles: provider and consumer

A plugin using this branch is either a **provider** (it owns data or a UI surface and publishes it)
or a **consumer** (it reads another plugin's service). Some plugins are both. Pick based on what the
operator's prompt asks for; state which role (or both) in `PLAN.md`.

### Provider pattern (cuepoints shape)

`playkit-js-kaltura-cuepoints` is the reference (research §7):

- Register the service in the **constructor**, not `loadMedia()`. Other plugins may look it up as
  soon as the plugin is constructed: `player.registerService('kalturaCuepoints', this._cuePointService)`.
- Reset the owned state in `destroy()`, alongside the mandatory `super.destroy()`:
  `destroy() { this.eventManager.destroy(); this._cuePointService.reset(); }` (verbatim shape,
  verified against the plugin's source). Do not skip the reset call; a service left registered after
  `destroy()` is a stale reference other plugins can still read.
- The service object itself can be anything (`this._cuePointService` above is a plain class
  instance). There's no interface Kaltura enforces; document your own service's shape in your
  plugin's README so consumers know what they're getting.

### Consumer pattern (transcript shape)

`playkit-js-transcript` is the reference (research §7):

- Add `@playkit-js/ui-managers` as a **devDependency**, and bundle it (it is not on the webpack
  externals list). This differs from `@playkit-js/kaltura-player-js` and `@playkit-js/playkit-js-ui`,
  which are externals mapped to the global `KalturaPlayer` object (research §8/§10). Get the externals list
  right in `webpack.config.js` or you'll double-bundle preact.
- Look up services in `loadMedia()`, not the constructor (see "Ordering" below):
  `this.player.getService('sidePanelsManager')`, `this.player.getService('upperBarManager')`.
- Add the panel and/or icon inside `loadMedia()`. Remove them inside `reset()`. Transcript's
  `destroy()` is one line, `destroy() { this.reset(); }`, so `reset()` carries all the teardown:
  it removes from `sidePanelsManager`, `upperBarManager`, and `AudioPluginsManager`.
  Whatever your plugin adds to a manager in `loadMedia()`, remove the same thing in `reset()` so a
  media change or plugin `destroy()` doesn't leak a panel or icon.
- Transcript **does not call `ui.addComponent` at all**. If you find yourself reaching for
  `player.ui.addComponent` to build something that looks like a panel, stop: that's the wrong branch.
  Panels and upper-bar icons go through the services above; `addComponent` is for a component mounted
  into a fixed preset area (`reference/ui-components.md`).

## Ordering: services aren't there yet when the constructor runs

Plugins load and construct in whatever order the host player config lists them. A service you need
may be registered by a plugin that hasn't constructed yet when your constructor runs. Two
consequences:

- **Never call `getService` in the constructor** expecting a result. Resolve lazily: in
  `loadMedia()`, or on first actual use (e.g., inside a click handler), whichever fires later than
  every plugin's constructor.
- **Always check `hasService(name)` before calling anything on the result.** If it's absent, log once
  (not on every call) and make the plugin inert for that feature instead of throwing. A missing
  service must never crash `loadMedia()` or block playback.

```js
loadMedia() {
  if (!this.player.hasService('sidePanelsManager')) {
    this.logger.warn('sidePanelsManager not registered; panel UI disabled');
    return;
  }
  const sidePanelsManager = this.player.getService('sidePanelsManager');
  // ... add the panel
}
```

## Community vs internal mode

This pattern works the same in both modes; there's no mode split in the API itself. The one
mode-specific detail is packaging: the `kaltura` field in `package.json` (e.g.
`{"name": "kalturaCuepoints"}`, or with a `dependencies` map for transcript) is internal-only
tooling metadata (`kaltura-tools`/canary, research §10 table row). **Do not emit the
`kaltura` package.json field in a community scaffold.** Internal-mode scaffolds may include it if the
`rename-plugin` or template flow expects it.

## Do not copy from the reference plugins

Live verification against the reference plugins' actual source found real quality gaps in
both reference plugins. Don't carry these into a generated plugin:

- `playkit-js-transcript` ships **no unit tests** at all. Write your own per
  `reference/testing-strategy.md`; don't treat the absence of tests in the reference plugin as
  precedent.
- Neither cuepoints nor transcript documents the service object's shape anywhere. Don't repeat that:
  document your provider service's fields/methods in the plugin's README.
- Two import styles exist across these plugins: modular `import {BasePlugin} from
  '@playkit-js/kaltura-player-js'` (template, aws-analytics) vs. global `KalturaPlayer.core.BasePlugin`
  (cuepoints, transcript). Use the modular import for type-checking (research §10 table, "Base class
  import" row); don't copy the global-object style from cuepoints/transcript.
- Transcript's `preinstall` internal gate is disabled in its own repo but is active-by-default in the
  template; don't assume either state, check `reference/ci-cd-modes.md` for what the target mode needs.

## Tests

Follow `reference/testing-strategy.md` for the full harness. Specific to this branch:

- **Provider**: a unit test that constructs the plugin and asserts
  `player.registerService` was called with the plugin's service name and an object exposing the
  documented shape. A second test that calls `destroy()` and asserts the service's `reset()` (or
  equivalent teardown method) ran.
- **Consumer**: stub `player.hasService`/`player.getService` to return a fake manager object with the
  methods your plugin calls (e.g. a fake `sidePanelsManager` with a spy for the add/remove method you
  use). Assert: (a) the add call happens in `loadMedia()` with the right panel/icon config, (b) the
  matching remove call happens in `reset()`, (c) when `hasService` returns `false`, `loadMedia()`
  does not throw and does not call `getService`.
- **Both**: a lifecycle test that calls `loadMedia()` twice (simulating a media change) and asserts no
  duplicate panel/icon accumulates. That is, `reset()` between the two calls actually removed the
  first one before the second one is added.

## Known gaps (say so in `PLAN.md`, do not guess)

- Exact method names on `sidePanelsManager`, `upperBarManager`, and `AudioPluginsManager` (add/remove
  panel or icon signatures) are not captured in the research doc. Confirm against the installed
  `@playkit-js/ui-managers` version's type definitions before writing the call, and record the
  version you checked.
- Whether `kalturaCuepoints` or any other provider service has a documented public shape upstream:
  no. Treat every provider service as ad hoc and document your own.
- **`sidePanelsManager.add(item)` does not make the panel visible.** Live-verified against the
  installed `@playkit-js/ui-managers` `1.9.2` bundle: `add()` only validates `item` and registers an
  `ItemWrapper`, returning an id (or `undefined` + a logged error if `item` is malformed, never a
  throw). The panel stays mounted but hidden until a separate `activateItem(id)` call runs (it sets
  `activePanels[position]` and expands the panel). If your plugin's whole purpose is to show a panel
  it just added, call `sidePanelsManager.activateItem(id)` right after a successful `add()`.
- **A generic ancestor keydown handler can swallow your panel's own keyboard activation.** Live-verified
  in a real browser (not reproducible in jsdom, which doesn't implement native Enter/Space
  button-activation): several `@playkit-js/playkit-js-ui` components that can host a mounted panel
  (list items, dropdown items, etc.) attach their own bubble-phase `keydown` handler for Enter/Space
  that unconditionally calls both `preventDefault()` and `stopPropagation()`, regardless of the actual
  event target. Because `preventDefault()` cancels a keydown's default action even when called later,
  on an ancestor, after the event already passed through your button, this silently cancels the
  browser's native "Enter/Space activates a focused button" behavior for any interactive element your
  panel mounts inside such a container -- a real mouse click works, but keyboard activation on the
  exact same element does nothing. **Fix**: give each interactive element inside your panel its own
  `keydown` handler that calls `event.stopPropagation()` (never `preventDefault()`) for Enter/Space,
  in the bubble phase. This stops the event from reaching the ancestor's handler while leaving the
  browser's own default action alone. Cover this with an e2e test (jsdom can't reproduce the bug, so a
  unit test can only assert the fix's mechanism, not the failure it prevents).

## Exit checks

Run these before calling phase 2 (Implement, plan §4) done for this branch:

- `grep -n "registerService(" src/*.ts*` hits in the constructor file, for a provider plugin.
- `grep -n "getService(\|hasService(" src/*.ts*` hits, and none of those calls sit inside the
  constructor (check by eye or `grep -B5` around each hit and confirm it's inside `loadMedia`, a
  handler, or a lazily-invoked method, not the constructor body).
- `grep -n "ui.addComponent" src/*.ts*` returns nothing for a plugin whose whole job is a side panel
  or upper-bar icon. (A Unisphere consumer plugin may still use `addComponent` for a secondary mount
  point outside the panel, research §16.6 item 6. That's a documented exception, not a violation.)
- `grep -n "super.destroy()" src/*.ts*` hits, and the same function or the `reset()` it calls also
  removes whatever was added to a manager service.
- If community mode: `grep -n '"kaltura"' package.json` returns nothing.
