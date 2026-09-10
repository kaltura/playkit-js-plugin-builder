# Config and validation

Source of truth: `docs/plans/2026-09-09-plugin-skill-research.md` §1 (`BasePlugin` constructor and
`updateConfig` merge semantics), §2 (plugin manager, the `disable` key), and §15 (corrections against
the first draft). This file owns the **config schema, defaults, merge, and validation** layer. Two
sibling files own adjacent ground and are worth reading alongside this one, but not required first:
`reference/base-plugin-api.md` owns the lifecycle contract (`isValid()`, constructor, `destroy()`) and
states explicitly that config validation itself belongs here; `reference/security-checklist.md` §4
owns what happens to a config value once it reaches a dangerous sink (`innerHTML`, `postMessage`,
`eval`). This file applies to every architecture branch this skill builds, including the Unisphere
consumer (`reference/unisphere-integration.md`): a Unisphere consumer plugin still takes a config
object through the same `BasePlugin` constructor and is validated the same way.

Read this file on its own; it does not assume you've read the others first.

## 1. Two merge behaviors: shallow at construction, deep in `updateConfig`

This is the single most important fact in this file (research §1, §15). The plugin manager passes
config into the constructor, and `BasePlugin` merges it like this:

```
config = {...defaultConfig, ...config}   // constructor: shallow spread, base-plugin.ts:87
```

A shallow spread replaces a nested key wholesale instead of merging into it. If `defaultConfig` is:

```ts
static defaultConfig: MyPluginConfig = {
  apiUrl: null,
  thresholds: {warn: 10, critical: 20}
};
```

and the host passes `{thresholds: {critical: 50}}`, the merged result is `{thresholds: {critical:
50}}` and `warn` is gone, not preserved. This is different from what most JavaScript developers expect
from "config defaults," and different from how the same class behaves later:

```
updateConfig(update)   // public method: Utils.Object.mergeDeep, base-plugin.ts:118-120, deep merge
```

A later call to `plugin.updateConfig({thresholds: {critical: 50}})` **does** preserve `warn`, because
`updateConfig` deep-merges key by key. Construction and `updateConfig` behave differently on the exact
same shape of input. A generated plugin with any nested default must merge that nesting explicitly in
its own constructor, right after `super(...)`:

```ts
constructor(name: string, player: ConstructorParameters<typeof BasePlugin>[1], config: Partial<MyPluginConfig>) {
  super(name, player, config);
  this.config.thresholds = {
    ...MyPlugin.defaultConfig.thresholds,
    ...(config.thresholds ?? {})
  };
}
```

Do this once per nested object that has defaults worth preserving, not just at the top level. If a
config object nests two levels deep (`{a: {b: {c: 1, d: 2}}}`) and the host can pass a partial `b`,
repeat the merge at that level too. A single top-level spread does not fix nesting further down.

**Validate the merged result, not the raw `config` argument.** The raw constructor argument may omit
keys entirely (that's what defaults are for); the merged, nested-default-corrected object is the only
one that reflects what the plugin will actually read. Do the nested merge first, then run validation
(§3) against `this.config`.

## 2. Where validation runs: the boundary, not scattered checks

Two places in a plugin's public surface receive data the plugin's author does not control: the
**constructor** (the `config` argument) and any later **`updateConfig(update)`** call, which a host
integrator can invoke at any time after construction. Everywhere else, that is `loadMedia()`, event
handlers, and internal helpers, code reads `this.config` and trusts it. Don't add a second
validation pass inside those internal methods; that duplicates the boundary check, drifts out of sync
with it as the plugin evolves, and hides the fact that there's supposed to be one source of truth.

**`isValid()` cannot do config-dependent validation.** It's declared `static isValid(): boolean`
(research §1) and runs without access to any instance (`reference/base-plugin-api.md` §2 spells out
why: it's static, so it can't read `this.config`). Config-dependent gating belongs in the constructor,
not in an override of `isValid()`. Keep `isValid()` for class-level requirements that don't depend on
a specific instance's config (a browser feature check, for example), and let it return `true` in the
common case where the class itself is always activatable.

When constructor-time validation finds a bad value, pick one of two patterns and record the choice in
`PLAN.md` (this mirrors the open design choice `reference/base-plugin-api.md` §12 flags for
`isValid()`. It isn't settled by a spec fact, it's a per-plugin call):

- **Self-disable.** Set an internal flag (for example `this._valid = false`) in the constructor and
  guard every public entry point, that is `loadMedia()`, event handlers, and any hook, with an early
  return when the flag is false. The plugin still registers and loads successfully (`isValid()` and
  `registerPlugin` both succeed); it just never does anything. Use this when the bad or missing value
  means there is nothing useful the plugin can do at all, and a silent no-op is acceptable.
- **Dispatch and degrade.** Fall back to a safe default for the one bad field, keep the rest of the
  plugin running, and dispatch a `RECOVERABLE` error with the bad value in `data` so the integrator can
  see it in logs or telemetry (`reference/error-event-taxonomy.md` has the exact `Error` shape and
  dispatch call). Use this when only one feature is affected, not the plugin as a whole.

**Don't make a constructor throw your primary validation strategy.** A throw from the constructor is a
real, separate path: the plugin manager catches it and rethrows as `Error(RECOVERABLE, PLAYER,
PLUGIN_LOAD_FAILED)` (research §2). It works, but it discards the specific bad-field detail unless you
catch and re-wrap it yourself, and in logs it looks identical to an actual bug in the constructor
rather than a documented "bad config" outcome. Prefer self-disable or dispatch-and-degrade.

**`updateConfig` is a boundary too.** If you override it, call `super.updateConfig(update)` first (so
the deep merge runs), then re-run the same validation pass you ran in the constructor against the
newly merged `this.config`. A host can hand the plugin a bad value just as easily through
`updateConfig` after startup as through the initial config; validating only once, at construction,
leaves that second entry point wide open.

## 3. Validate the merged config, once, into a normalized shape

A plugin's config validation is one function, called once per boundary crossing (§2), that:

- Confirms every required key is present and of the right type.
- Clamps numeric values to a documented min/max instead of trusting an out-of-range number (a
  negative timeout, a percentage over 100).
- Falls back to a safe default for a malformed value rather than crashing on it. A config error
  should never be indistinguishable from a real bug in the plugin's own code.

```ts
interface MyPluginConfig {
  apiUrl: string | null;
  thresholds: {warn: number; critical: number};
}

function normalizeConfig(raw: MyPluginConfig): {config: MyPluginConfig; problems: string[]} {
  const problems: string[] = [];
  const config = {...raw};

  if (config.apiUrl !== null && !/^https:\/\//.test(config.apiUrl)) {
    problems.push(`apiUrl must be an https URL, got: ${config.apiUrl}`);
    config.apiUrl = null; // fall back rather than crash
  }
  config.thresholds.warn = Math.max(0, Math.min(100, config.thresholds.warn));
  config.thresholds.critical = Math.max(config.thresholds.warn, Math.min(100, config.thresholds.critical));

  return {config, problems};
}
```

Call `normalizeConfig` once in the constructor (after the nested-default merge in §1) and once at the
top of an overridden `updateConfig`, after `super.updateConfig(update)` (§2). Everywhere else in the
plugin, read `this.config.thresholds.warn` directly. It has already been validated and clamped, so a
third check in `loadMedia()` or an event handler is redundant, not extra safety.

## 4. No live references from config into internal state

`getConfig()` never hands out a live reference: it returns `Utils.Object.copyDeep` of the internal
config (research §1), specifically so a caller mutating the returned object can't touch the plugin's
real state. Mirror that same discipline for the plugin's **own** internal use of nested config values.

Concretely, don't do this:

```ts
// Wrong: this._thresholds now aliases the same object as this.config.thresholds.
this._thresholds = this.config.thresholds;
```

A later `updateConfig({thresholds: {...}})` deep-merges into `this.config.thresholds` (§1); depending
on exactly how that nested object is rebuilt, `this._thresholds` can end up silently pointing at stale
data, or get mutated underneath the plugin without going through whatever change-handling logic
(recompute a derived value, dispatch a "config changed" event) was supposed to run when a threshold
changes. Copy instead:

```ts
// Right: an independent copy, safe from later mutation of this.config.
this._thresholds = {...this.config.thresholds};
```

For a nested object more than one level deep, deep-copy it (a small structuredClone or a manual
recursive copy), not a shallow spread. A shallow spread only protects the top level.

## 5. The `disable` key: reserved, host-owned, don't repurpose

Config reaches a plugin at `config.plugins.<name>`, and `config.plugins.<name>.disable: boolean` is
the **only** reserved key at that level (research §2, `docs/configuration.md:163-204`). It belongs to
the integrator embedding the player, not to the plugin's own `defaultConfig`. Never set a default
value for `disable` in a generated plugin's `defaultConfig`, and never write to
`this.config.disable` from inside the plugin's own code.

Two behavior details worth knowing before you rely on it:

- The plugin manager's `load()` step treats `isValid() === false` and `config.disable === true`
  identically: it silently returns `false` and the plugin never activates, with no throw, no dispatched
  error, no log line calling it out (research §2). That's useful (it's exactly the outward behavior a
  self-disabling plugin also wants, §2 above), but it means a disabled plugin leaves no trace in
  normal logs; don't rely on `disable` alone if you need visibility into why a plugin didn't load.
- The flag is **cached per plugin name and only re-read when `typeof config.disable === 'boolean'`**
  (research §2). An integrator who wants to toggle a plugin on or off should always pass an explicit
  `true`/`false`, not omit the key expecting it to reset to "enabled". An omitted or non-boolean value
  doesn't force a re-read of the cached state.

Never repurpose `disable` for a plugin-specific meaning, like "keep tracking but hide the UI." That
key triggers the plugin manager's coarse, whole-plugin skip (no `loadMedia`, no duck-typed hooks,
nothing runs). A feature-level toggle needs its own, differently named config key (`hidden`,
`uiDisabled`, whatever fits the plugin), validated the normal way (§3), so a partial degrade and a
full disable stay distinguishable both in code and in the integrator's config.

## Do not copy

- The official template's `defaultConfig` is a flat object with one key (`{someTitle: 'Plugin
  Example...'}`, verified live against `kaltura/playkit-js-plugin-example` at the pinned SHA in
  research §8), and its `isValid()` unconditionally returns `true` regardless of that config (research
  §8). Copy the class shape, that is a typed `defaultConfig` and an overridden `isValid()`, not the
  pattern of ignoring config entirely. The template's config is flat and never checked; a generated
  plugin with nested defaults or required fields needs the merge (§1) and validation (§3) this file
  adds, which the template has no example of.
- None of the four real plugins the research audited (`plugin-example`, `kaltura-cuepoints`,
  `transcript`, `aws-analytics`; research §9, §10) demonstrate nested-default merging or a config
  validation pass of any kind. There is no shipped Kaltura plugin to point to as a worked example for
  §§1–3 above; those patterns are synthesized from the `BasePlugin` merge/lifecycle facts in research
  §1–§2 plus general boundary-validation practice, not copied from a Kaltura-authored repo. Say so
  rather than implying a gold-standard example exists somewhere in that set.
- Don't put config-dependent checks inside `isValid()` (§2 above, `reference/base-plugin-api.md` §2).
  It's static and runs with no instance to read `this.config` from; a generated plugin that tries this
  is wrong twice over: it won't type-check as written, and even if it did, it can't see the value
  it's supposed to be checking.
- Don't make a constructor throw the primary way you signal bad config (§2 above). It's a real,
  caught path (`PLUGIN_LOAD_FAILED`), but it reads like a crash in logs and discards field-level detail
  unless you deliberately re-wrap it.

## Tests

Cover the lifecycle cases the plan's phase-3 exit condition names explicitly: valid load, invalid
config, `disable: true`, change media, destroy. For the config-specific ones:

- **The shallow-merge regression test.** Construct the plugin with a partial nested config object,
  e.g. `new MyPlugin('x', player, {thresholds: {critical: 50}})`, and assert
  `plugin.getConfig().thresholds.warn` still equals the documented default. Without this test, the
  fix in §1 is unverified. It's easy to write the manual merge once and have a later refactor delete
  it silently, and nothing else in the suite would catch that.
- **The `updateConfig` re-validation test.** Call `plugin.updateConfig({thresholds: {critical: 500}})`
  (out of range) and assert the clamp from §3 still applies after the update, not just at construction.
- **The invalid-required-config test.** Construct the plugin with a missing or malformed required
  field and assert whichever pattern from §2 the plugin chose: either every public method becomes a
  no-op (self-disable), or the plugin dispatches exactly one `RECOVERABLE` error with the bad value in
  `data` and keeps running in a degraded state (dispatch-and-degrade).
- **The `disable: true` test.** Construct with `config.plugins.<name>.disable = true` (or however the
  test harness feeds plugin config) and assert `loadMedia()` is never called and no UI mounts. This
  exercises the plugin-manager path in §5, not the plugin's own code, so keep it as a thin
  integration-style assertion rather than duplicating internal logic.

## Exit checks

```bash
# 1. Every nested key in defaultConfig has a matching manual merge line in the constructor
grep -n "static defaultConfig" src/*.ts
grep -n "defaultConfig\." src/*.ts
# for each nested object literal in defaultConfig, confirm a "this.config.<key> = {...}" merge exists

# 2. No config-dependent check lives inside isValid()
grep -n "isValid" src/*.ts -A 5 | grep -n "this.config"
# any hit is wrong per §2: isValid() is static and cannot read instance config

# 3. The plugin never writes to the reserved disable key itself
grep -rn "config\.disable\s*=" src/
grep -rn "disable\s*:" src/*.ts
# expect nothing outside a comment; disable is host-owned, never plugin-set (§5)

# 4. The shallow-merge regression test exists
grep -rln "thresholds\|nested\|defaultConfig" test/ tests/ 2>/dev/null
# confirm by reading: at least one test asserts a sibling default key survives a partial nested update

# 5. No config value reaches an injection sink directly (full list and rationale in
#    reference/security-checklist.md §3-4; this is a narrow cross-check, not the whole gate)
grep -rnE "innerHTML|eval\(|new Function" src/
```

## Known gaps

- No Kaltura document defines a canonical config-validation pattern for plugins; the general "no
  Kaltura plugin-security doc exists" gap in research §14 extends to validation specifically.
  Everything in §§1–5 above is built from the `BasePlugin` merge and plugin-manager facts in research
  §1–§2 plus general boundary-validation practice, not a Kaltura-authored example.
- Self-disable versus dispatch-and-degrade (§2) is a per-plugin design choice, not a spec fact. Record
  the choice made for a given plugin in that plugin's `PLAN.md`, the same way
  `reference/base-plugin-api.md` §12 asks for the parallel `isValid()`-timing choice to be recorded.
- The exact internal mechanics of `Utils.Object.mergeDeep` (whether it mutates nested objects in place
  or always allocates new ones) were not independently re-verified beyond the citation in research §1.
  Treat "copy nested config into internal state instead of aliasing" (§4) as the safe default
  regardless of that implementation detail. It costs nothing and removes the question entirely.
