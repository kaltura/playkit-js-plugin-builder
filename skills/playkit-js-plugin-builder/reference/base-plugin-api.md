# BasePlugin API

Every Kaltura PlayKit-JS plugin is a subclass of `BasePlugin` (kaltura-player-js
`src/common/plugins/base-plugin.ts`, research §1). This applies to **every architecture branch** this
skill builds, including the Unisphere consumer branch (`reference/unisphere-integration.md`): a
Unisphere consumer is still a plain `BasePlugin` subclass with `isValid()`, `loadMedia()`, `reset()`,
and a `destroy()` that calls `super.destroy()`. Read this file on its own; it doesn't assume you've
read the others.

## 1. The full member surface

Source: research §1. Never call the constructor yourself; the plugin manager does.

| Member | Visibility | Default behavior | What generated code must do |
|---|---|---|---|
| `constructor(name, player, config)` | public | sets `name`, `player`, `logger = getLogger(capitalize(name))`, `eventManager = new EventManager()`, `config = {...defaultConfig, ...config}` | Never override the signature. Do setup in the constructor body only after calling `super(...)` implicitly (TS subclassing handles this). |
| `name` | public | set by ctor | Read-only in practice. |
| `displayName!`, `symbol!: {svgUrl, viewBox}` | public | uninitialized | Set both if any UI host (a plugin picker, a marketplace listing) lists installed plugins by name/icon. Skip for a plugin with no such host. |
| `logger`, `config`, `player`, `eventManager` | protected | set by ctor | Use `this.logger` for all logging, `this.eventManager.listen(...)` for all event subscriptions (never `player.addEventListener` directly; see §7). |
| `static defaultConfig` | protected static | `{}` | Always override with every config key and its default. |
| `static isValid(): boolean` | public static | **throws** `Error(CRITICAL, PLAYER, RUNTIME_ERROR_METHOD_NOT_IMPLEMENTED)` | Must override. See §2. |
| `getConfig(attr?)` | public | `Utils.Object.copyDeep` | Never mutate the returned object and expect it to affect the live plugin; it's a deep copy. |
| `updateConfig(update)` | public | `Utils.Object.mergeDeep` into live config | Deep merge, unlike the constructor merge (§3). |
| `get ready()` | protected getter | `Promise.resolve()` | See §6. |
| `loadMedia()` | public | no-op | Fires on `CHANGE_SOURCE_STARTED`, not "media has loaded". See §5. |
| `reset()` | public | no-op | Called before `setMedia()`/`loadMedia()` on a player instance being reused for a new entry. See §5. |
| `destroy()` | public | `this.eventManager.destroy()` | Subclasses that override `destroy()` **must call `super.destroy()`**, or must call `this.eventManager.destroy()` themselves. See §4. |
| `open()` | public | **throws** `RUNTIME_ERROR_METHOD_NOT_IMPLEMENTED` | Only relevant to overlay plugins opened by a UI host; no core caller invokes it today. Leave unoverridden unless you know a host calls it. |
| `getName()` | public | returns `name` | |
| `dispatchEvent(name, payload?)` | public | debug log, then `player.dispatchEvent(new FakeEvent(name, payload))` | Use this for the plugin's own custom events, never for player-level errors (see `reference/error-event-taxonomy.md`). |

## 2. `isValid()`: no arguments, never throws, blocks activation on `false`

Contract (research §1, §2):

- **Signature is `static isValid(): boolean`. It takes no arguments.** A generated plugin that writes
  `static isValid(player)` or reads `this.config` inside a static method is wrong twice over: it can't
  read instance config (the method is static and runs before construction), and it doesn't match the
  base signature.
- If you don't override it, the base implementation throws. That throw is **not caught** by the plugin
  manager's `load()` (research §2). It propagates and becomes a dispatched player error
  (`kaltura-player.ts:1064-1071`). This is why every generated plugin overrides `isValid()`.
- Your override must **return `false` on bad config, never throw**. `isValid() === false` (or
  `config.disable === true`) makes the plugin manager silently skip activation: no error, no log
  spam, just "this plugin doesn't run." A throw from your override is what happens if you forget this
  and let some other code path (e.g. reading a missing nested key without a guard) blow up instead of
  returning `false`.
- A **constructor** throw is a different, second layer: the plugin manager catches it and rethrows as
  `Error(RECOVERABLE, PLAYER, PLUGIN_LOAD_FAILED)`. Put required-field validation in `isValid()`, not
  the constructor, so a bad config degrades to "plugin inactive" instead of a recoverable player error.
  Full config validation flow (schema, required keys, per-field checks) is in
  `reference/config-and-validation.md`; this file only covers the lifecycle contract.

Minimal correct shape:

```ts
static isValid(): boolean {
  return true; // or a real check against static/class-level requirements only
}
```

Because `isValid()` is static, it cannot see instance config. If validity depends on the config value
itself, do the boolean check in the constructor and either skip your own setup or dispatch a
RECOVERABLE error there. `isValid()` stays for cases where the plugin as a class is always
activatable and per-instance config problems are handled after construction. Most generated plugins
that need config-dependent gating instead keep `isValid()` returning `true` and make `getConfig`-driven
checks part of `loadMedia()`/constructor logic, dispatching errors per `reference/error-event-taxonomy.md`
rather than silently no-op-ing. Document whichever choice you make in `PLAN.md`.

## 3. The constructor merge is shallow; `updateConfig` is deep

Research §1, flagged as a footgun: the constructor merge is `{...defaultConfig, ...config}`
(`base-plugin.ts:87`), a **shallow spread**. A nested default like `{thresholds: {a: 1, b: 2}}` is
**replaced wholesale**, not merged, if the host passes `{thresholds: {a: 5}}`. The result has only
`{a: 5}`; `b` is gone.

`updateConfig(update)` uses `Utils.Object.mergeDeep` (`base-plugin.ts:118-120`) and merges nested
objects key by key.

Consequence for generated code: any plugin with nested default config must merge that nesting
explicitly in its own constructor, after calling `super(...)`:

```ts
constructor(name: string, player: ConstructorParameters<typeof BasePlugin>[1], config: MyPluginConfig) {
  super(name, player, config);
  this.config.thresholds = {...MyPlugin.defaultConfig.thresholds, ...config.thresholds};
}
```

Type the `player` parameter as `ConstructorParameters<typeof BasePlugin>[1]`, not `KalturaPlayerTypes.Player`.
The latter is an ambient interface from the package's legacy `ts-typed/` declaration surface; the real
exported `BasePlugin` class (the modular `dist/*.d.ts`, what `import {BasePlugin} from
'@playkit-js/kaltura-player-js'` actually resolves to) types its constructor's `player` param as the
concrete `KalturaPlayer` class from a different, differently-scoped declaration, and `KalturaPlayerTypes.Player`
does not match it under `tsc --strict`. `ConstructorParameters<typeof BasePlugin>[1]` always matches
whatever the installed version's real signature is, with no type name to get wrong or keep in sync
(live-verified: `npm run type-check` passes clean with this pattern against the installed package).

Do this for every nested config object, not just the top-level one. If a config object has two levels
of nesting, repeat the pattern at each level that has defaults worth preserving.

## 4. `destroy()` must call `super.destroy()`

Base `destroy()` does exactly one thing: `this.eventManager.destroy()`, which removes every listener
registered through `this.eventManager.listen(...)`. If your override does other cleanup (removing UI
components, aborting in-flight requests, killing a workspace connection) and forgets to also call
`super.destroy()` (or call `this.eventManager.destroy()` directly), every listener registered through
`eventManager` leaks for the life of the page.

Correct shape:

```ts
destroy(): void {
  this._removeUIComponent?.();
  this._abortController?.abort();
  super.destroy();
}
```

## 4b. `listen()`/`addEventListener` never dedupe; `reset()` must call `unlisten`/`removeAll`, never `destroy()`

Live-verified by reading the installed `@playkit-js/playkit-js` runtime source
(`event/fake-event-target.ts`, `event/event-manager.ts`), not documented upstream:

- **Neither `EventManager.listen()` nor `FakeEventTarget.addEventListener` (the base of `player` itself,
  since `KalturaPlayer extends FakeEventTarget`) deduplicates.** Each call unconditionally pushes a new
  binding, unlike native DOM `EventTarget.addEventListener`, which silently ignores an exact duplicate
  (same type, same listener reference). Calling `this.eventManager.listen(this.player, type, fn)` twice
  with the same `fn` registers two bindings; the handler then runs **twice** per event, not once.
- This makes a `loadMedia()` that adds a listener but a `reset()` that forgets to remove it a worse bug
  than a simple leak: on a media change, `loadMedia()` runs again and adds a **second** binding for the
  same listener, so the handler fires twice; a second media change adds a third, and so on. Always pair
  every `this.eventManager.listen(...)` added in `loadMedia()` with a matching
  `this.eventManager.unlisten(...)` in `reset()` (§5), and cover it with the "call `loadMedia()` twice,
  assert no duplicate" test already required in `reference/services-and-ui-managers.md`'s Tests section
  — that same pattern applies to any plugin using `eventManager.listen`, not only side-panel plugins.
- **`EventManager.removeAll()` and `EventManager.destroy()` are not interchangeable.** `removeAll()`
  clears every binding but leaves the manager usable. `destroy()` calls `removeAll()` and then sets the
  internal binding map to `null` **permanently** — every later `listen()` call on that manager becomes a
  silent no-op (the `null` map guards the push), not an error. `this.eventManager` is a single instance
  for the plugin's whole lifetime, so **never call `this.eventManager.destroy()` from `reset()`**; that
  would leave the plugin unable to register anything for the rest of the page's life, the next time
  `loadMedia()` runs. Use `this.eventManager.removeAll()` in `reset()` if you want a blanket "clear
  everything I added this entry" instead of pairing individual `unlisten()` calls; reserve
  `this.eventManager.destroy()` for the plugin's own `destroy()` (§4), which never runs again after.

## 5. Lifecycle order: `loadMedia`, `reset`, `destroy`

Research §1, §2:

- `loadMedia()` fires on the player's `CHANGE_SOURCE_STARTED` event, fanned out by the plugin manager
  to every registered plugin. It does **not** mean "media has finished loading". Name your own logic
  accordingly. This is where UI components get added (`this.player.ui.addComponent(...)`, see
  `reference/ui-components.md`) and where a Unisphere consumer looks up its service
  (`reference/unisphere-integration.md`), because services are registered by other plugins and aren't
  guaranteed to exist yet at construction time.
- `reset()` runs before `setMedia()`/`loadMedia()` on a player instance being reused for a new entry
  (e.g. a playlist advance). Use it to tear down per-entry state (abort controllers, subscriptions tied
  to the old entry) without destroying the plugin itself. A plugin with no per-entry state can leave
  `reset()` as a no-op or delegate to `loadMedia()` if setup is idempotent.
- `destroy()` runs once, when the plugin manager tears the player down. See §4.

## 6. `ready`: a protected getter the middleware probes, rejection is swallowed

`get ready()` (research §1, §3) defaults to `Promise.resolve()`. `PluginReadinessMiddleware` reads it
on `load`/`play`. Two things generated code must not get wrong:

- **It's a getter, not a method.** Override it as `protected get ready(): Promise<void> { ... }`.
- **A rejection is swallowed.** The middleware logs at debug level and lets playback continue anyway.
  Only a *slow resolve* delays `load`/`play`; a *reject* does nothing visible. A plugin that must block
  playback on a failed async dependency cannot rely on rejecting `ready`. It has to dispatch a
  CRITICAL error itself (`reference/error-event-taxonomy.md`) to get the player to show an error state.

## 7. Duck-typed hooks probed by `kaltura-player.ts`

These three hooks are **not declared on `BasePlugin`**: there's nothing to override, no abstract
method, no interface. `kaltura-player.ts:1078-1097` (research §3) checks `typeof plugin.hookName ===
'function'` at plugin-load time and wires up the hook only if present. Add the method to your subclass
and it's picked up automatically; omit it and nothing happens (no error, no warning).

| Hook | Effect if present | Notes |
|---|---|---|
| `getMiddlewareImpl()` | Return value pushed onto `_localPlayer.playbackMiddleware` (unshifted, i.e. run first, if the plugin's registered name is `bumper`) | Undocumented upstream. Used for engine-level playback interception (pre-roll bumpers, DRM gating). |
| `getUIComponents()` | Each item in the returned array is passed to `_uiWrapper.addComponent()` | The upstream `docs/writing-a-plugin.md` describes this hook incorrectly (research §15: it is not "merged into `config.ui.uiComponents`"). Prefer calling `this.player.ui.addComponent(...)` directly from `loadMedia()` instead of implementing this hook; that's what the official template and most real plugins do (research §8, §6.1). Implement `getUIComponents()` only if you specifically need components registered before `loadMedia()` runs. |
| `getEngineDecorator()` | If present, `registerEngineDecoratorProvider(new EngineDecoratorProvider(plugin))` is called; only method existence is checked, not a specific interface it must satisfy beyond what `EngineDecoratorProvider` expects | Used for plugins that need to intercept engine-level playback calls (advanced ad insertion, custom stream stitching). Rare; most plugins need none of these three hooks. |

If a plugin implements none of these hooks, that's the common case, not a gap. Only add one when a
concrete requirement needs it.

## 8. `registerPlugin` and the plugin manager

Research §2:

- Register with the free function `registerPlugin('myPluginName', MyPluginClass)`, imported from
  `@playkit-js/kaltura-player-js` (modular) or accessed as `KalturaPlayer.core.registerPlugin` (global,
  see §9).
- Internally this calls `register(name, Class)`, which validates `Class.prototype instanceof
  BasePlugin` and **returns `false` silently** (no throw, no console error) on an invalid class or a
  duplicate plugin name.
- **Generated tests must assert the return value of `registerPlugin(...)` is `true`.** A typo in the
  plugin name, a class that doesn't extend `BasePlugin`, or a duplicate registration will otherwise
  fail silently and the plugin simply never loads, with no signal pointing at the cause.
- `config.plugins.<name>.disable: boolean` is the **only** reserved plugin config key (research §2,
  `docs/configuration.md:163-204`). It's cached per plugin name and only re-read when
  `typeof config.disable === 'boolean'`. Don't invent another reserved key name; `disable` is the one
  the player already understands.
- `loadMedia()`, `reset()`, `destroy()` on the plugin manager fan out to every registered plugin in
  turn; `destroy()` also removes each plugin from the manager's internal map.

## 9. Two import styles: prefer modular

Research §1, §8, §10:

```ts
// Modular (preferred): type-checked, works with any bundler
import {BasePlugin, registerPlugin} from '@playkit-js/kaltura-player-js';

// Global: relies on the player having patched these onto window.KalturaPlayer.core
const {BasePlugin, registerPlugin} = KalturaPlayer.core;
```

`src/index.ts` in kaltura-player-js patches `BasePlugin` and `registerPlugin` onto the re-exported
`core` object, so both styles resolve to the same runtime objects. The modular import gives you
compile-time type checking against the class you're extending; the global style only works once the
player script has already run on the page. Default to modular for anything built with a bundler
(the community `templates/` scaffold does). Only reach for the global style in a plain-script,
no-bundler embed.

## 10. Do not copy from real plugins

These are confirmed defects in shipped Kaltura plugins (research §9, §15), not hypothetical mistakes.
Don't repeat them just because they appear in a repo you're using as a reference:

- `playkit-js-aws-analytics`'s `destroy()` calls `this.eventManager.destroy()` **directly instead of
  `super.destroy()`**. It happens to work today because that's all the base method does, but it's
  fragile: if `BasePlugin.destroy()` ever does more than that, this plugin silently stops running the
  extra cleanup. Always call `super.destroy()`; never reimplement its body.
- The upstream `docs/errors.md` example dispatches with `player.Event.Error`, which **does not exist**
  on the real `player.Event` object (research §4, §15). Never write `player.Event.Error` in generated
  code or docs; the correct path is `player.Event.Core.ERROR`. Full taxonomy in
  `reference/error-event-taxonomy.md`.
- Three of the four real plugins surveyed (`plugin-example`, `transcript`, `aws-analytics`) ship no
  unit tests at all (research §9, §10), so none of them assert `registerPlugin(...)` returns `true`.
  The fourth (`kaltura-cuepoints`) has karma+mocha+chai specs, but the research audit didn't confirm
  whether they cover this assertion. Generated plugins must add one regardless; don't assume any
  reference repo already models it.

## 11. Phase 2 exit checks

These are the literal checks this skill's phase-2 (Implement) exit condition requires (plan §4, row 2).
Run them against the plugin's `src/` and `test/` (or `tests/`) directories before calling the phase
done. All must pass with no output from the "must return nothing" checks and a real hit from the
"must hit" checks.

```bash
# 1. isValid() has no arguments (must hit, and the arg list between the parens must be empty)
grep -rn "isValid()" src/

# 1b. No override reintroduces a throw for a bad-config case (inspect manually; grep only flags candidates)
grep -rn "isValid" src/ -A 5 | grep -n "throw"
# ^ any hit here needs a human/agent read: isValid() must return false on bad config, never throw.

# 2. destroy() calls super.destroy() (must hit at least once per plugin class file)
grep -rn "super.destroy()" src/

# 2b. No destroy() override skips super.destroy() by calling eventManager.destroy() instead
grep -rn "eventManager.destroy()" src/
# ^ any hit here should be inside base-plugin.ts itself, never in a subclass. A subclass hit means
#   the destroy() override is bypassing super.destroy(). Fix it per §4 before continuing.

# 2c. reset() never calls eventManager.destroy() (must return nothing; see §4b)
grep -n "reset()" src/*.ts* -A 15 | grep "eventManager.destroy()"
# ^ any hit means reset() permanently kills the plugin's ability to listen on the next loadMedia().
#   reset() should use eventManager.removeAll() or paired unlisten() calls instead.

# 3. No use of the nonexistent player.Event.Error anywhere in source (must return nothing)
grep -rn "player\.Event\.Error\b" src/

# 4. registerPlugin's return value is asserted in a test (must hit)
grep -rln "registerPlugin(" test/ tests/ 2>/dev/null | xargs grep -n "registerPlugin(" 2>/dev/null
# ^ confirm the surrounding test asserts the return value is true, e.g.
#   expect(registerPlugin('myPlugin', MyPlugin)).toBe(true)
```

If the plugin is on the Unisphere consumer branch, also run the two additional checks in
`reference/unisphere-integration.md`'s exit-checks section (no direct `@unisphere/runtime-js` import,
no direct `fetchAndLoadUnisphereWorkspace`/`getUnisphereInstance` call). Everything in this file still
applies to that branch unchanged.

## 12. Known gaps

- `open()` has no documented core caller (research §1). If a UI host in the target environment does
  call it, verify from that host's source before relying on the contract described in the table above.
- Whether a config-dependent `isValid()` check is preferable to constructor-time validation is a design
  choice, not a spec fact; §2 states the tradeoff, it doesn't mandate one answer. Record the choice made
  for a given plugin in that plugin's `PLAN.md`.
