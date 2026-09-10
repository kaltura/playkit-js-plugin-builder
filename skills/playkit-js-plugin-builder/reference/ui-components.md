# UI component contract

Covers `player.ui.addComponent`, the area/preset enums, the i18n host-page contract, and
accessibility for any plugin that renders visible UI. Source: `docs/plans/2026-09-09-plugin-skill-research.md`
§6 (playkit-js-ui `src/reducers/shell.ts:45-75`, `src/types/ui-component-options.ts`,
`src/ui-manager.tsx`, `docs/ui-components.md` at `497114d`), §15 (errors in the first draft).

## Branch check first

Skip this whole flow if the requested capability already exists as a Unisphere runtime (video
summary, Genie chat, or one the operator names). Check `reference/unisphere-integration.md` first;
that branch owns its own side panel and upper-bar icon and you should not rebuild them with
`addComponent`. A Unisphere consumer plugin can still use `addComponent` for one thing: a `<div id>`
mount target *outside* the side panel, so `runtime.mountVisual` has somewhere to render (research
§16.6, the chapter-title visual). Everything below applies to that mount target too.

For the three classic branches (event-bridge, component UI, side-panel UI), see
`reference/decision-tree.md`. This file is the reference for the **component UI** branch and for
any UI element any branch adds via `addComponent`.

## 1. The `addComponent` contract

Call `this.player.ui.addComponent(options)` from `loadMedia()`, not the constructor (research §6.1;
the official template does the same). Signature (`KPUIAddComponent`, `src/types/ui-component-options.ts`):

```ts
{
  label: string,
  presets: string[],       // which ReservedPresetNames this component shows under
  area: string,             // which ReservedPresetAreas it mounts into
  get: (() => any) | 'remove',
  props?: object,
  beforeComponent?: string,
  afterComponent?: string,
  replaceComponent?: string,
  container?: string,       // deprecated, do not use in new plugins
}
```

- `get` is a function returning the component (a Preact element, `() => <MyComponent {...props}/>`),
  or the string `'remove'` to delete a built-in component from that area/presets combination.
- **`addComponent` returns a remove function.** Store it on the plugin instance and call it in both
  `reset()` and `destroy()`. Skipping this leaks a mounted component across a `reset()`/`loadMedia()`
  cycle (a new media load without a page reload) and after `destroy()`.
- `docs/ui-components.md` upstream still says the API is **BETA** and its area list is incomplete.
  State the BETA status in generated docs; use the source enums below, not the doc's list.

Minimal pattern:

```ts
private _removeComponent?: () => void;

loadMedia(): void {
  this._removeComponent?.(); // guard against a stale mount from a previous loadMedia
  this._removeComponent = this.player.ui.addComponent({
    label: 'my-plugin-overlay',
    presets: [this.player.config.ui.presets... /* e.g. ReservedPresetNames.Playback, Live */],
    area: /* one ReservedPresetAreas value, see §2 */,
    get: () => <MyOverlay player={this.player} />,
  });
}

reset(): void {
  this._removeComponent?.();
  this._removeComponent = undefined;
}

destroy(): void {
  this._removeComponent?.();
  super.destroy();
}
```

## 2. The enums, from source, not the doc

`docs/ui-components.md` lists 13 areas. The real list, read from `src/reducers/shell.ts:45-75`
(research §6.2, correcting research §15's flagged first-draft error), has **18**:

**`ReservedPresetAreas`** (18 values):

| Area | Typical use |
|---|---|
| `PlayerArea` | Whole-player overlay, outside the preset-specific chrome |
| `PresetArea` | Root of the active preset |
| `InteractiveArea` | Click-through layer over the video; the template's example uses this |
| `VideoArea` | Directly over the video element |
| `GuiArea` | Root of the player chrome |
| `TopBar` | Top bar container |
| `BottomBar` | Bottom bar container |
| `PresetFloating` | Floating layer above the preset |
| `TopBarLeftControls` | Left side of the top bar |
| `TopBarRightControls` | Right side of the top bar |
| `BottomBarLeftControls` | Left side of the bottom bar (play/pause, time) |
| `BottomBarRightControls` | Right side of the bottom bar (settings, fullscreen) |
| `SidePanelTop` | Top of the side panel |
| `SidePanelLeft` | Left side panel |
| `SidePanelRight` | Right side panel |
| `SidePanelBottom` | Bottom of the side panel |
| `SeekBar` | Seek bar row |
| `LoadingSpinner` | Loading-spinner slot |

Do not tell an operator or generate docs claiming only 13 areas exist, and do not invent an area name
that is not in this table; a wrong string silently mounts nothing (no exported list to validate
against, so a typo fails quietly).

**`ReservedPresetNames`** (8 values): `Playback`, `Live`, `Ads`, `Error`, `Idle`, `Img`, `Document`,
`MiniAudioUI`. Pass one or more of these in `presets` to control which player state shows the
component; most plugins use `[Playback, Live]`.

Both enums are runtime exports (see §3), not just types: import them, don't hardcode the strings.

## 3. Runtime surface

`src/index.ts` exports (research §6.4), reachable off `KalturaPlayer.ui` in a global build or from
`@playkit-js/playkit-js-ui` in a modular build:

- `h`, `createPortal`, `preact`, `redux`, `preacti18n`, `preactHooks`: the UI runtime, mapped to
  root externals so a plugin never bundles a second copy (see the externals table in
  `reference/base-plugin-api.md`'s sibling scaffold notes and research §8).
- `EventType`, `Event`: UI-layer event constants, distinct from the player's own event taxonomy in
  `reference/error-event-taxonomy.md`.
- `getOverlayPortalElement`, `getDurationAsText`, `style`: small helpers.
- `Reducers`, `Presets`, `Components` (about 50, including `Tooltip`, `Icon`, `SidePanel`,
  `SmartContainer`, keyboard higher-order components): reusable pieces. Prefer these over
  hand-rolled equivalents so the plugin's UI matches player chrome.
- `Utils`: `withKeyboardA11y`, `focusElement`, `KeyMap`/`KeyCode`, `getLogger`, see §5.
- `UIManager`, `SidePanelPositions`, `SidePanelModes`, `ReservedPresetNames`, `ReservedPresetAreas`,
  `VERSION`, `NAME`.

Webpack externals for a community-mode build (research §8): map `preact`, `preact-i18n`,
`preact/hooks` to `KalturaPlayer.ui.preact`, `KalturaPlayer.ui.preacti18n`, `KalturaPlayer.ui.preactHooks`
respectively, alongside the three core externals in `reference/base-plugin-api.md`. Skipping this
double-bundles Preact and can break event delegation between the plugin's tree and the player's.

Author components as Preact `.tsx` with CSS/SCSS modules, matching the template (research §8).

## 4. i18n is a host-page contract, not a plugin auto-load

This is the fact most likely to surprise someone porting a React/Vue mental model: **shipping a
translation file does not make the player load it.**

Verified at `497114d`, `ui-manager.tsx:57-64,148-162,199` (research §6.3):

- `IntlProvider` wraps the player `<Shell>` with playkit-js-ui's own built-in `translations/en.i18n.json`,
  merged with whatever the host page passes as `config.ui.translations`.
- `_setLocaleTranslations` runs **once, from the constructor**. Each `config.ui.translations[locale]`
  is deep-merged over the built-in `en`, so any key missing from a locale falls back to English.
- `config.ui.locale` is lower-cased and used **only if a dictionary for it exists** in
  `ui.translations`; otherwise the player silently stays on `en`.
- There is no public method to add a dictionary or switch locale after construction.
  `_translations` and `_locale` are private fields.

Consequence for anything this plugin ships under `translations/<locale>.i18n.json`: nothing reads
that directory automatically, ever. A generated plugin must:

1. Ship `translations/<locale>.i18n.json` for every locale the operator asked for (default: `en`
   only if nothing was asked). Every key needs an English fallback string in `en`, since an
   unsupported locale degrades to English, not to raw i18n keys, only if the fallback exists.
2. Generate the `ui.translations` block the **host page** must pass, one sub-object per shipped
   locale, with `npm run i18n:snippet` (see `reference/docs-and-demo.md`). This is not optional
   tooling; without it the operator has to hand-write the block themselves, which is exactly the
   template's own gap (`demo/index.html:20-27` re-declares the keys by hand).
3. Document in the README, verbatim, that the host page must set both `ui.translations` (the
   generated block) and `ui.locale` (if not `en`). State plainly that the plugin cannot switch its
   own locale at runtime.
4. Use `withText`/`<Text>` for every user-facing string, never a raw string in the component tree,
   so the fallback-to-English behavior actually works.

Tests (also in `reference/testing-strategy.md`): a unit test asserts every
`translations/<locale>.i18n.json` has exactly the same key set as `en` (a missing key is a silent
English fallback in production, a typo'd extra key is dead weight); one e2e case loads the player
with `ui.locale` set to a shipped non-`en` locale and asserts the translated string actually renders,
not just that the file parses.

Known gap (research §14, do not promise this): whether a Kaltura SaaS player config accepts a
per-locale `ui.translations` block set from the *partner* side (as opposed to the plugin's own
bundler-time config) is unverified. Say so in generated docs if the operator is targeting SaaS.

## 5. Accessibility

No ARIA or focus-management doc exists upstream for playkit-js-ui; only `docs/with-keyboard-event.md`
covers keyboard event wiring. `Utils.withKeyboardA11y` and `focusElement` exist in source
(§3) but are undocumented. Everything below is synthesized from WAI-ARIA practice plus those two
utilities and WCAG 2.2 (research §6.5, §13); say so in generated docs rather than presenting it as
an official Kaltura a11y guide.

Baseline for any interactive component this plugin adds:

- **Keyboard reachability.** Every control a mouse can activate must be reachable and operable by
  keyboard alone (WCAG 2.1.1). Use `Utils.withKeyboardA11y` on custom interactive elements and
  `focusElement` to move focus programmatically (opening a panel, dismissing an overlay) instead of
  hand-rolling `tabIndex`/`keydown` logic.
- **Visible focus** (WCAG 2.4.7). Never remove the focus outline with CSS without providing an
  equally visible replacement.
- **Focus not obscured** (WCAG 2.4.11, new in WCAG 2.2). A focused control must not be fully hidden
  behind another layer the plugin adds, such as an overlay or a side panel that renders on top of
  the currently focused bottom-bar control. This specifically catches plugins that add a
  `PlayerArea`/`PresetFloating` overlay without checking what it covers.
- **No keyboard traps.** A panel or modal the plugin opens must let focus leave it (Escape, or a
  visible close control reachable by Tab).
- **ARIA roles and labels.** Every interactive element needs a role appropriate to its behavior and
  an `aria-label` (or visible text) that says what it does, not just what it looks like ("Close",
  not "X"). A custom slider-like control follows the WAI-ARIA APG slider pattern: `role="slider"`
  plus `aria-valuenow`, `aria-valuemin`, `aria-valuemax`, and `aria-valuetext` when the numeric value
  alone isn't meaningful to a screen-reader user.
- **Respect `prefers-reduced-motion`.** Any animation or transition the plugin adds must have a
  reduced-motion fallback.

Kaltura publishes a Player V7 VPAT (September 2024, WCAG 2.2 and Section 508) covering the player
itself. Generated docs should state that this plugin's UI does not regress that baseline, and link
the VPAT index page (`https://knowledge.kaltura.com/help/accessibility-in-kalturas-products` at time
of writing) rather than a PDF URL, which is not public and changes without notice.

Test: a Cypress (internal mode) or Playwright (community mode) a11y check on the rendered component,
using `cypress-axe` or an equivalent axe-core runner, see `reference/testing-strategy.md`. Unit-level,
assert keyboard reachability (the control receives focus via Tab and activates via Enter/Space) and
that every interactive element has an `aria-label` or accessible text.

## 6. This file vs. `reference/services-and-ui-managers.md`

Two different mechanisms mount UI, and picking the wrong one produces working-but-nonstandard UI:

| | This file (`addComponent`) | `reference/services-and-ui-managers.md` |
|---|---|---|
| Mechanism | `player.ui.addComponent` | `player.getService('sidePanelsManager'/'upperBarManager')` |
| Shape | A component in a preset area (overlay, bar control, floating layer) | A full side panel or upper-bar icon |
| Reference plugin | `playkit-js-plugin-example` (research §8) | `playkit-js-transcript` (research §7) |
| Bundling | `@playkit-js/playkit-js-ui` externalized | `@playkit-js/ui-managers` bundled as a devDependency, not externalized |

Use this file whenever the UI is a control, overlay, or bar element that fits one of the 18 areas
above. Use the services file when the UI is a dedicated panel with its own open/close lifecycle, or
an upper-bar icon that toggles one. A Unisphere consumer plugin uses neither directly for its panel;
`pluginManager.initRuntime` creates the panel and icon for it (`reference/unisphere-integration.md`).

## 7. Common mistakes (research §15, do not reintroduce)

| Wrong | Right |
|---|---|
| "13 areas" from `docs/ui-components.md` | 18 areas, source-verified (§2); `SidePanel*` (4 values) and `PlayerArea` were the ones missing |
| "plugin `translations/*.i18n.json` files are read automatically by preact-i18n" | Nothing auto-loads them. The host page must pass `ui.translations` (§4) |
| Removing a component only in `destroy()` | Also remove and re-add across `reset()`/`loadMedia()`, or a stale component survives a media change |
| Bundling `preact`/`preact-i18n`/`preact/hooks` instead of externalizing them | Double-bundles the UI runtime and can desync events between trees (§3) |

## Exit checks

Run these before calling the UI branch done:

- `grep -n "addComponent" src/*.ts*` finds at least one call, and the same file stores its return
  value (grep for `= this.player.ui.addComponent` or an assignment on the same statement).
- `grep -n "reset()" -A5 src/*.ts*` and `grep -n "destroy()" -A5 src/*.ts*` both show the stored
  remove function being called.
- `grep -rn "ReservedPresetAreas\.\|ReservedPresetNames\." src/*.ts*` shows enum members, not
  hardcoded string literals, for `area` and `presets`.
- If any `translations/` directory exists: a unit test asserts key-set parity against `en`, and
  `npm run i18n:snippet` output is committed and matches what CI regenerates (diff, not eyeballed).
- If a Cypress/Playwright a11y run exists, it's green and actually exercises the rendered component
  (not just that the player loads).
