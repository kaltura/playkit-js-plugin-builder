# Coding guidelines

Kaltura's own style rules for player code live in `kaltura-player-js`'s
`docs/coding-guidlines.md` (yes, misspelled; that is the real filename, research §5). This file
turns those rules into checks an agent can run while writing a plugin, for every architecture
branch (event-bridge, `addComponent` UI, services/side-panel, Unisphere consumer). Read
`reference/base-plugin-api.md` for lifecycle rules and `reference/security-checklist.md` for the
security-driven lint rules (Trusted Types sinks, the `kaltura-player-js` typosquat guard); this
file does not repeat those.

No published `eslint-config-kaltura` or similar shareable package exists (checked research §5 and
§8; nothing named that way surfaced). The rules below come from the upstream guidelines doc plus
the config actually shipped in `playkit-js-plugin-example` (research §8). Ship them as local
`.eslintrc`/`.prettierrc` files in `templates/`, don't invent an `extends` on a package that isn't
real.

## Naming

| Kind | Convention | Example |
|---|---|---|
| Function | `functionNamesLikeThis` | `loadMedia`, `getConfig` |
| Variable | `variableNamesLikeThis` | `eventManager`, `sidePanelRef` |
| Class | `ClassNamesLikeThis` | `TranscriptPlugin` |
| Enum | `EnumNamesLikeThis` | `PluginState` |
| Constant value | `CONSTANT_VALUES_LIKE_THIS` | `DEFAULT_TIMEOUT_MS` |
| Type / interface | PascalCase | `TranscriptPluginConfig` |

Apply these to every identifier you generate, including test names and file-local helpers. Don't
rename identifiers in code you're calling into (player APIs, dependency exports) even if they use
a different convention; match the caller, not the callee.

## Private members: trailing underscore

The documented convention is a trailing underscore on private members (`_cache`, `_teardown()`).
Upstream code is inconsistent: `base-plugin.ts` uses TypeScript `protected` with no underscore,
`plugin-manager.ts` uses `private _x` (research §5). Apply the underscore in every plugin you
generate. Don't flag upstream Kaltura source, or a dependency, for lacking it in review; it's a
convention for new code, not a defect in old code.

```ts
class MyPlugin extends BasePlugin {
  private _refreshTimer: number | null = null;

  private _clearTimer(): void {
    if (this._refreshTimer !== null) {
      clearTimeout(this._refreshTimer);
      this._refreshTimer = null;
    }
  }
}
```

## Statement-level style

- Single quotes for strings, everywhere. No double quotes, no backticks unless you need
  interpolation or a multi-line string.
- JSDoc `@param`/`@returns` above every function and method, including private ones. A function
  with no parameters and no return value still gets a one-line description.
- Arrow functions over `.bind(this)`. If a method needs a stable `this` for an event listener or
  callback, declare it as an arrow-typed class field, not a bound method.
- Braces on every control structure, even a one-line `if`. No single-statement bodies without
  braces.
- 2-space indent. No tabs.

```ts
/**
 * Refreshes the cached transcript for the current entry.
 * @param force When true, bypasses the cache even if it's fresh.
 * @returns A promise that resolves once the refresh completes.
 */
private _refresh = async (force: boolean): Promise<void> => {
  if (!force && this._isFresh()) {
    return;
  }
  await this._fetchTranscript();
};
```

## TypeScript strictness

- Write in TypeScript strict mode, matching the official template's stack (research §8). Don't
  loosen `strict` in a generated `tsconfig.json` to make code compile faster.
- `explicit-member-accessibility`: every class member (`public`/`protected`/`private`) states its
  accessibility explicitly. Don't rely on the implicit-`public` default.
- Prefer the modular import (`import {BasePlugin} from '@playkit-js/kaltura-player-js'`) over the
  global (`KalturaPlayer.core.BasePlugin`). The global object only exists at runtime, once the
  player's UMD bundle has loaded and attached it to the page (research §8, "Externals" row). A
  bundler-based `tsc` setup can't check it against the real declarations before then, so it needs a
  loose or `any`-typed ambient declaration to compile at all. Use the global form only inside a demo
  HTML page that loads the player from a script tag, never inside plugin `src/`.
- Avoid `any`. The one documented exception is a third-party type gap you can't fix: the
  Unisphere `pluginManager` has no published types (research §16, "Types" bullet in
  `reference/unisphere-integration.md`), so that branch ships a local `.d.ts` shim instead of
  reaching for `any`. If you hit a similar gap elsewhere, write a local shim first; reach for `any`
  only as a last resort and leave a comment naming the untyped dependency.
- Type every public method's parameters and return value. Inference is fine for local `const`s
  with an obvious literal type; it isn't a substitute for a typed function signature.

## Module layout

- One plugin class per file, named after the class (`transcript-plugin.ts` for `TranscriptPlugin`).
- `index.ts` is the entry point. It imports the plugin class, calls `registerPlugin(name, Class)`,
  and re-exports anything the package's public API needs (config types, emitted event names). It
  does not contain plugin logic.
- Keep UI components, services, and the plugin class in separate files under their own
  directories (`components/`, `services/`, or similar). A component file exports a component, not
  a plugin class; a services file wraps a `getService(...)` call, it doesn't subclass
  `BasePlugin`.
- Translation dictionaries live under `translations/<locale>.i18n.json`, one file per locale, per
  the i18n contract in `reference/ui-components.md`. Don't inline translation strings in TSX; that
  breaks the key-set-parity check other reference files rely on.
- Never bundle `preact`, `preact/hooks`, or `preact-i18n` into your output. The build maps them to
  `KalturaPlayer.ui.preact` / `preactHooks` / `preacti18n` as externals (research §8) so every
  plugin on the page shares one Preact instance. Bundling your own copy breaks other plugins on
  the same page, and Preact components stop working across the boundary.
- No circular imports between the plugin class and its components/services. If a component needs
  to call back into the plugin, pass a callback prop, don't import the plugin class from the
  component file.

## Tooling enforced in the template

`templates/` ships these configs; generated plugins get them unmodified unless the operator asks
for something else.

- ESLint: `@typescript-eslint/recommended` plus Prettier, `max-len: 150`, `no-console: 'error'`
  (use `this.logger`, never `console.*`), `explicit-member-accessibility` (research §5).
- Prettier: `printWidth: 150`, `singleQuote: true`, no trailing commas.
- `npm run lint` and `npm run type-check` both exit 0 on the untouched scaffold and after every
  change you make. This is the plan's phase 1 exit check; don't treat lint or type errors as
  something to fix later.
- Build output must be a UMD bundle (`output.libraryTarget: 'umd'` / webpack 5's equivalent
  `output.library.type`), matching the official scaffold (research §8: `UMD
  ['KalturaPlayer','plugins','<pluginName>']`) — never ESM-only. An ESM-only build can't be loaded by
  a plain `<script src="...">` tag, which breaks the script-tag install path `reference/docs-and-demo.md`
  §1 requires the README to document, and breaks any e2e/demo page that loads the plugin the same way
  the player itself is loaded. If a bundler default (e.g. a bare esbuild/Vite config) would emit
  ESM-only, override it explicitly rather than leaving the default in place.

## Do not copy

Real Kaltura plugins on GitHub have style issues; don't reproduce them just because they're in
official or reference code (research §9, §10):

- `playkit-js-aws-analytics`'s `destroy()` calls `this.eventManager.destroy()` directly instead of
  `super.destroy()`. It happens to work because `eventManager.destroy()` is most of what
  `super.destroy()` does, but it skips whatever else the base class cleans up. Always call
  `super.destroy()`.
- The `"kaltura": {...}` field in some plugins' `package.json` (e.g. `kalturaCuepoints`'s name
  entry) is an internal convention for Kaltura's own tooling (kaltura-tools, canary). It has no
  meaning outside Kaltura's build system. Don't add it to a community-mode `package.json`.
- `kalturaCuepoints` and `playkit-js-transcript` import `BasePlugin` off the global
  `KalturaPlayer.core` object instead of the modular package (research §10). That's a valid runtime
  pattern for a plugin loaded via script tag, but it needs a loose ambient declaration to compile
  and so gives up compile-time checking against the real declarations. Use the modular import in
  generated source (see TypeScript strictness above).
- The template's stale README documents `npm run dev`, `lint:check`, `prettier:fix`, `types:check`,
  none of which exist in its own `package.json` (research §8). Never copy template README prose
  wholesale; verify every command you write in a generated README actually exists in the generated
  `package.json`'s `scripts`.

## Fallback self-check list

Run this when the `code-review` and `simplify` skills aren't installed in the target environment
(research §12). Each line is a command; a clean plugin passes all of them with no output (or exit
0) before you call the work done.

```bash
# Lint and types clean
npm run lint && npm run type-check

# No console.* in source (use this.logger)
grep -rn "console\.\(log\|warn\|error\|info\|debug\)" src/

# No .bind(this); arrow functions instead
grep -rn "\.bind(this)" src/

# Every destroy() override calls super.destroy()
grep -rln "destroy()" src/*.ts* | xargs -I{} sh -c 'grep -q "super.destroy()" {} || echo "missing super.destroy(): {}"'

# No internal-only package.json field leaking into a community scaffold
grep -n "\"kaltura\":" package.json

# No global BasePlugin import inside plugin src/ (modular import only)
grep -rn "KalturaPlayer\.core\.BasePlugin" src/
```

If any of these return unexpected output, fix the source before moving to the next phase. Don't
suppress a lint rule to make a check pass; fix the code instead. If a rule is genuinely wrong for
a specific case (a rare exception, not a pattern), disable it inline with a one-line comment
explaining why, scoped to the smallest span possible, never at the file or project level.

## Known gap

Research didn't surface a published, versioned Kaltura ESLint/Prettier config package to depend
on (checked §5 and §8). The rule set above is reconstructed from the guidelines doc plus one
template's actual config, not from a package you can `npm install` and trust to stay in sync. If
Kaltura publishes one later, prefer depending on it over the local copy in `templates/`.
