# Error and event taxonomy

Source of truth for every fact below: `docs/plans/2026-09-09-plugin-skill-research.md` §4 (playkit-js
`src/error/*`, kaltura-player-js `kaltura-player.ts:840-851`) and §15 (corrections against the first
draft). This file applies to every architecture branch, including the Unisphere consumer
(`reference/unisphere-integration.md`). A Unisphere consumer plugin is still a `BasePlugin` subclass
and still reports errors and listens to events the way described here.

Read this file on its own. It does not assume you have read `reference/base-plugin-api.md`, though the
two cross-reference each other on lifecycle and cleanup.

## 1. Constructing a Kaltura `Error`

Signature, five arguments (research §4, §15):

```
new Error(severity, category, code, data = {}, errorDetails?)
```

- `severity`: `Error.Severity.RECOVERABLE` or `Error.Severity.CRITICAL`.
- `category`: one value from the fixed list in §2 below.
- `code`: one value from the fixed list matching that category (§3 below has the `PLAYER` list, the
  one plugins use most).
- `data`: an object. This is where plugin-specific detail goes, because there is no plugin-specific
  category or code (§4).
- `errorDetails`: optional, extra structured detail (for example a caught exception).

**Constructing an `Error` always logs it**, even if you never dispatch it (research §4, §15). Do not
build one speculatively or for a code path you're not sure will fire. Build it exactly where you are
about to either dispatch it or return it to a caller. A stray `new Error(...)` left in a debug branch
will spam the log on every play, not just on failure.

```ts
// Correct: build it right where you dispatch it.
const err = new Error(Error.Severity.RECOVERABLE, Error.Category.PLAYER, Error.Code.PLUGIN_LOAD_FAILED, {
  plugin: this._name,
  reason: 'sdk timeout'
});
this.player.dispatchEvent(new FakeEvent(this.player.Event.Core.ERROR, err));
```

```ts
// Wrong: constructing on every call regardless of whether it's used floods the log.
function maybeError(cond: boolean) {
  const err = new Error(Error.Severity.RECOVERABLE, Error.Category.PLAYER, Error.Code.PLUGIN_LOAD_FAILED);
  if (cond) return err;
  return null; // err was still logged even though it's discarded here
}
```

## 2. Severity: RECOVERABLE vs CRITICAL

Only two values exist (research §4). There is no third "warning" or "fatal" level; if you were
planning for a "fatal" tier, use `CRITICAL`.

| Severity | Value | Player behavior | Use when |
|---|---|---|---|
| `RECOVERABLE` | 1 | Logged only. Playback continues. | The plugin's own feature failed but core playback is unaffected. This is the default for almost every plugin error. |
| `CRITICAL` | 2 | Player shows the error overlay. | Playback itself cannot continue (bad manifest, DRM failure, no source). Plugins should reach for this only when they are certain there's no way to keep the video playing without the failed thing. |

Rule of thumb for plugin authors: default to `RECOVERABLE`. Escalate to `CRITICAL` only if the plugin
is standing directly in the playback path (for example, an ads plugin that gates play until an ad
response arrives) and that path is now blocked with no fallback. A side-panel or event-bridge plugin
should almost never dispatch `CRITICAL`. Its failure means a feature is missing, not that the video
can't play.

## 3. Category and code

Category list (research §4), with the values Kaltura's own `Error.Category` enum uses:

| Category | Value |
|---|---|
| NETWORK | 1 |
| TEXT | 2 |
| MEDIA | 3 |
| MANIFEST | 4 |
| STREAMING | 5 |
| DRM | 6 |
| PLAYER | 7 |
| ADS | 8 |
| STORAGE | 9 |
| CAST | 10 |
| VR | 11 |
| MEDIA_NOT_READY | 12 |
| GEO_LOCATION | 13 |
| MEDIA_UNAVAILABLE | 14 |
| IP_RESTRICTED | 15 |
| SITE_RESTRICTED | 16 |
| SCHEDULED_RESTRICTED | 17 |
| ACCESS_CONTROL_BLOCKED | 18 |
| DELETED_ENTRY | 19 |

`PLAYER` codes (7xxx), the ones a generic plugin is most likely to use (research §4):

| Code | Value |
|---|---|
| LOAD_INTERRUPTED | 7000 |
| BITRATE_SWITCH_ISSUE | 7001 |
| LOAD_FAILED | 7002 |
| RUNTIME_ERROR_NOT_REGISTERED_PLUGIN | 7003 |
| RUNTIME_ERROR_METHOD_NOT_IMPLEMENTED | 7004 |
| RUNTIME_ERROR_NOT_VALID_HANDLER | 7005 |
| NO_SOURCE_PROVIDED | 7006 |
| NO_ENGINE_FOUND_TO_PLAY_THE_SOURCE | 7007 |
| ENTER_PICTURE_IN_PICTURE_FAILED | 7008 |
| EXIT_PICTURE_IN_PICTURE_FAILED | 7009 |
| PLUGIN_LOAD_FAILED | 7010 |

For an ads-, VR-, network-, or DRM-adjacent plugin, use the matching category (`ADS`, `VR`, `NETWORK`,
`DRM`) instead of `PLAYER` if one of its codes actually fits. Most plugins never touch those; they stay
on `PLAYER`.

## 4. There is no PLUGIN or CUSTOM category or code

This is the single most important correction in this file (research §4, §15). Kaltura's `Error` type
has no `PLUGIN` category and no generic "custom plugin error" code. If you need a plugin-specific
error, you still pick from the fixed category/code lists above (`PLAYER` covers almost every case) and
put the plugin-specific detail (what actually went wrong, which plugin, which config) in the `data`
argument.

```ts
// Correct: fixed category/code, plugin detail in `data`.
new Error(Error.Severity.RECOVERABLE, Error.Category.PLAYER, Error.Code.RUNTIME_ERROR_NOT_VALID_HANDLER, {
  plugin: 'my-plugin',
  handler: 'onAdBreakStart'
});
```

```ts
// Wrong: these do not exist and will not type-check or resolve at runtime.
new Error(Error.Severity.RECOVERABLE, Error.Category.PLUGIN, Error.Code.CUSTOM_ERROR, {});
```

Do not invent a category or code. Do not skip the `Error` type and throw a plain `Error` (the
JavaScript builtin) either. See §9 on why plugins should never throw at all from most call sites.

## 5. Dispatching the error correctly

```ts
this.player.dispatchEvent(new FakeEvent(this.player.Event.Core.ERROR, err));
```

**`player.Event.Error` does not exist.** The upstream `docs/errors.md:37-49` example in
kaltura-player-js uses `player.Event.Error`, which is wrong (research §4, §15). If you copy that
example verbatim, the dispatch call resolves `undefined` as the event name and the error event never
reaches listeners the way they expect. Always use `player.Event.Core.ERROR`.

## Do not copy from upstream docs

- `docs/errors.md`'s example line using `player.Event.Error`. Use `player.Event.Core.ERROR` instead
  (§5 above).
- Any first-draft assumption that a `PLUGIN`/`CUSTOM` category exists. It doesn't (§4 above).
- Treating `Error.Severity` as having a third level ("warning", "fatal"). Only `RECOVERABLE` and
  `CRITICAL` exist (§2 above).

## 6. Event namespaces on `player.Event`

`player.Event` is not a flat list. It has namespaces, and one of them (`Core`) is where `ERROR` lives
(research §4):

| Namespace | What's in it |
|---|---|
| `Core` | Core playback events, including `ERROR`. |
| `UI` | UI-layer events. |
| `Cast` | Casting events. |
| `Playlist` | Playlist events. |
| (flat, back-compat) | `VISIBILITY_CHANGE`, `REGISTERED_PLUGINS_LIST_EVENT`, and every `CoreEventType` key spread flat on `player.Event` directly, for backward compatibility with code written before the namespaces existed. |

`docs/events.md` upstream documents only `Core` and `UI` (research §4). `Cast` and `Playlist` are real
but undocumented there; if you need a cast or playlist event, look it up in the namespace, not in that
doc, and don't assume it's missing just because the doc doesn't mention it.

Prefer the namespaced form (`player.Event.Core.SOME_EVENT`) over the flat back-compat spread in new
code. The flat form exists for old call sites, not as the recommended style going forward.

## 7. Custom plugin events

For events your plugin defines itself (not part of the player's own taxonomy):

```ts
this.dispatchEvent(name, payload);
```

This goes through the plugin's own `dispatchEvent`, inherited from `BasePlugin`. It logs the call and
then dispatches the event on the player (`player.dispatchEvent(new FakeEvent(name, payload))`, see
`reference/base-plugin-api.md`), so anyone listening on the player for that event name receives it. Use
it for anything internal to your plugin's contract with its consumers.

For cross-framework bridges, cases where something outside the player's event system (a different
framework, or a `<script>` on the host page with no reference to the player instance) needs to observe
your plugin, dispatch a `CustomEvent` on `document` in addition. `playkit-js-aws-analytics` does this
(research §4). Don't make this the default. It's an escape hatch for one specific integration problem,
not a general substitute for `this.dispatchEvent`.

```ts
// Internal event, the normal case.
this.dispatchEvent('summary-ready', { itemCount: 12 });

// Cross-framework bridge, only when something outside the player event system needs it.
document.dispatchEvent(new CustomEvent('my-plugin:summary-ready', { detail: { itemCount: 12 } }));
```

## 8. Listener discipline

Register every listener, on the player, on `document`, on anything, through
`this.eventManager.listen(...)`. Never use `player.addEventListener` or `target.addEventListener`
directly (research §4).

```ts
// Correct.
this.eventManager.listen(this.player, this.player.Event.Core.ERROR, this._onError);

// Wrong: destroy() cleanup never reaches this listener.
this.player.addEventListener(this.player.Event.Core.ERROR, this._onError);
```

The reason is cleanup, not style: `eventManager` tracks every listener registered through it so
`destroy()` can remove them all in one call. A listener added directly bypasses that tracking and
leaks. It keeps firing (and can throw, per §9) after the plugin is destroyed. See
`reference/base-plugin-api.md` for the full `destroy()` contract, specifically that `destroy()` must
call `super.destroy()`, which is what triggers this cleanup.

## 9. Resilience rules

A plugin must never take playback down with it when it fails. Concretely:

- **Never throw from an event handler.** A handler registered via `eventManager.listen` runs inside the
  player's event dispatch. An uncaught throw there can break the dispatch loop for every other
  listener on that event, not just yours. Wrap handler bodies in `try/catch` and turn a caught
  exception into a `RECOVERABLE` `Error` dispatch (or just a log, if it's not worth surfacing to the
  host page).
- **Wrap every third-party SDK call.** Anything from an SDK you don't control (an ad SDK, an analytics
  SDK, a chat widget) can throw, reject, or hang. Wrap synchronous calls in `try/catch` and give
  promises a `.catch`. Never let a third-party failure propagate uncaught into your plugin's own
  lifecycle methods (`loadMedia`, `reset`, `destroy`).
- **Default to RECOVERABLE, escalate to CRITICAL only when truly justified.** Ask: "with this failure,
  can the video still play?" If yes, even in a degraded way (feature missing, panel empty, analytics
  silent), dispatch `RECOVERABLE` or just log. Reserve `CRITICAL` for the narrow case in §2: playback
  itself is blocked and there's no fallback.
- **Retry vs disable.** For transient failures (a network blip loading plugin config, a flaky SDK
  handshake), a bounded retry (a small fixed number of attempts, not an unbounded loop) is reasonable
  before giving up. For failures that won't change on retry (invalid config, a required dependency
  missing, `isValid()` returning `false`), don't retry. Disable the feature for that session: skip
  the UI, skip the event wiring, log once, and let the rest of the player run normally. Never retry
  forever and never let a retry loop block `loadMedia()` or `reset()` from completing.
- **Guard async work against destroy.** If a plugin kicks off a promise chain (loading a runtime,
  fetching config) and the player calls `destroy()` or `reset()` before it resolves, the callback must
  not act on a torn-down plugin. Use an `AbortController` per load cycle, or check a `destroyed` flag
  before touching `this.player` or UI state in the `.then()`/`.catch()`. See the Unisphere consumer
  recipe in `reference/unisphere-integration.md` for a concrete example of this pattern
  (`AbortController` per `loadMedia`, aborted in `reset()`).

## Known gaps

- The exact retry budget (attempt count, backoff) for transient third-party failures isn't specified
  anywhere in Kaltura's own docs or source (research §4 doesn't cover it). Treat "small, bounded,
  logged" as the floor and let the specific plugin's requirements set the actual number; don't invent
  a project-wide default and present it as a Kaltura convention.

## Exit checks

Run these against `src/` before calling a plugin's error/event handling done. All are plain `grep`;
none need a build.

- No use of the nonexistent event: `grep -rn "player\.Event\.Error\b" src/` returns nothing.
- No invented category/code: `grep -rn "Error\.Category\.PLUGIN\|Error\.Category\.CUSTOM\|Code\.CUSTOM_ERROR" src/` returns nothing.
- All error dispatches use the real path: every `dispatchEvent(new FakeEvent(...` in `src/` that
  carries an `Error` uses `player.Event.Core.ERROR`, not a flat or invented event name. Check by hand
  if the grep below doesn't localize it: `grep -rn "Event\.Core\.ERROR" src/` should hit at least once
  wherever the plugin reports errors.
- No bypassed cleanup: `grep -rn "player\.addEventListener\|\.addEventListener(" src/` returns nothing
  outside of code that also appears in `eventManager.listen(...)` calls. That is, every listener
  registration in the plugin goes through `this.eventManager.listen`.
- Lifecycle test exists (cross-check with `reference/testing-strategy.md` phase 3): a unit test drives
  a failure path (bad third-party response, thrown SDK call) and asserts the plugin dispatches a
  `RECOVERABLE` error (or just logs) rather than throwing out of the test, and that playback-affecting
  state is left in a working condition afterward.
