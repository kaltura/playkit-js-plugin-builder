# Decision tree: architecture choice

Every plugin build starts here, in phase 0 (Intake). The tree has four branches, checked **in this
fixed order**. Stop at the first branch that matches; don't keep checking after a match. Each node
below asks one question and names the concrete signal in the prompt (or from the operator) that
answers it. Record the answer as you go; the end state is one line in `PLAN.md` naming the branch,
plus the config interface, the events consumed and emitted, and at most one open question (plan §4,
phase 0).

```
0. Does a Unisphere runtime already cover this?  -- yes --> Unisphere consumer
   |
   no
   v
1. Does the plugin need any visible UI at all?    -- no  --> event-bridge
   |
   yes
   v
2. Is a small always-visible control/overlay enough,
   or does the content need a dedicated panel/tab?
   -- control/overlay --> component UI
   -- panel/tab        --> side-panel UI
```

Hybrids are allowed (for example: an event-bridge plugin that also drops a small status icon, or a
side-panel plugin that also gates playback with middleware). When a build is a hybrid, say so in
`PLAN.md` and name which parts use which mechanism.

## Node 0: Unisphere consumer check

**Question:** does the requested capability already exist as a Unisphere runtime?

**Signal to test:** the operator names a runtime directly, or the prompt describes a feature that
matches one of the runtimes documented in `reference/unisphere-integration.md` (today: AI video
summary/chapters, Genie AI chat, research §16.6). This is not a vibe check; it's a lookup against
that file's known-runtime list plus whatever the operator confirms.

**If yes:** the branch is **Unisphere consumer**. Stop here. Do not evaluate nodes 1 or 2. Build a
thin plugin on `@playkit-js/unisphere-service` following `reference/unisphere-integration.md` in
full: the workspace, the side panel, the icon, and the event bridge already exist inside the runtime.
Rebuilding any of them duplicates a feature Kaltura already ships (research §16.9, plan §6.16). This
branch works in both community and internal mode; only internal mode may author a *new* runtime when
none matches (research §16.2, §16.7).

**If no:** record this line in `PLAN.md`, **verbatim, word for word** (it is a literal grep check in
the e2e evals — don't paraphrase it, don't drop it, don't summarize the Unisphere check some other
way): `Unisphere: no Unisphere runtime covers this (checked reference/unisphere-integration.md and
operator input)`. Then continue to node 1.

**Reference plugin to imitate:** `playkit-js-unisphere-summary` (internal visibility to Kaltura
employees; the shape is documented in full in research §16.6 and reference/unisphere-integration.md,
so no source access is needed to copy it).

## Node 1: event-bridge vs. any UI

**Question:** does this plugin render anything a viewer can see or interact with?

**Signal to test:** the prompt's verbs. "Reacts to X and reports/sends/logs/tracks Y" with no mention
of a control, icon, panel, or overlay implies **no UI**. "Shows/adds/displays a button, icon, overlay,
panel, or tab" implies UI (plan §5).

**If no UI:** the branch is **event-bridge**. The plugin listens to player events through
`this.eventManager.listen(...)` (never `player.addEventListener`, so `destroy()` cleanup reaches it,
research §4) and reports out: to an analytics endpoint, a third-party SDK, `document`-level
`CustomEvent`s for cross-framework bridges, or the plugin's own `dispatchEvent`. No `ui.addComponent`
call anywhere in `src/`. Stop here.

**Reference plugins to imitate:** `playkit-js-aws-analytics` (community-buildable, no internal
access needed, research §9) and `playkit-js-kava` (Kaltura's own analytics bridge). Copy the
event-listening and cleanup discipline, not `aws-analytics`'s `destroy()` (research §15: it calls
`this.eventManager.destroy()` directly instead of `super.destroy()`; always use `super.destroy()`
in generated code) and not its live-network e2e setup (research §9; use the mock-provider pattern
from `reference/testing-strategy.md` instead).

**If UI is needed:** continue to node 2.

## Node 2: component UI vs. side-panel UI

**Question:** is a small, always-present control or overlay enough, or does the content need its own
dedicated space (a panel, tab, or upper-bar entry the viewer opens and closes)?

**Signal to test:** words like "button", "icon", "overlay", "badge", "watermark", "small control" in
a fixed player area imply **component UI**. Words like "panel", "tab", "sidebar", "transcript",
"chapter list", "chat", "drawer", anything with its own open/close state or that needs more room
than a control, imply **side-panel UI** (research §7, plan §5, §6.5).

### Branch: component UI

Build with `this.player.ui.addComponent({label, presets, area, get: () => <Component/>})`, called
from `loadMedia()` (research §6.1). `addComponent` returns a remove function. Store it and call it
in both `reset()` and `destroy()`; the official template only calls it once and never removes it,
which leaks a component across a `reset()`. Pick `presets` and `area` from the real enums in
`reference/ui-components.md` (research §6.2), not from the upstream `docs/ui-components.md`, which
is stale and incomplete.

**Reference plugin to imitate:** `playkit-js-plugin-example` (research §8). It's the official
scaffold and the only real-world example of this exact mechanism. `playkit-js-hotspots` is a second,
more elaborate example (overlay UI over video).

### Branch: side-panel UI

Build against the services registry, not `addComponent`. In the constructor,
`player.registerService(...)` if the plugin also exposes a service to others; more commonly, consume
`sidePanelsManager` and `upperBarManager` via `player.getService(name)` (research §7). This is how
Kaltura's own UI-heavy plugins are actually built today. `playkit-js-transcript` never calls
`ui.addComponent` at all. Full recipe, enums, and lifecycle in `reference/services-and-ui-managers.md`.

**Reference plugin to imitate:** `playkit-js-transcript` (research §7, §10). Bundles
`@playkit-js/ui-managers` as a devDependency, not externalized. Copy that dependency shape, not its
test suite (research §10: no unit tests ship).

## Reference plugins: full imitate/avoid list

| Branch | Imitate | Copy | Avoid copying |
|---|---|---|---|
| Unisphere consumer | `playkit-js-unisphere-summary` | service-getter pattern, `initRuntime`, storage/pub-sub contracts (research §16.6) | its `npm test` (`echo 'TODO'`), unmodified Cypress boilerplate, hardcoded i18n, `.npmrc` tokens |
| Event-bridge | `playkit-js-aws-analytics`, `playkit-js-kava` | `eventManager.listen` discipline, mock-provider e2e | `destroy()` skipping `super.destroy()`; live-network e2e as the default |
| Component UI | `playkit-js-plugin-example` | `addComponent` call shape, webpack/build config (research §8) | stale README (`npm run dev`, `lint:check`; none exist in `package.json`); no unit tests ship, add your own |
| Side-panel UI | `playkit-js-transcript` | services-registry consumption, `@playkit-js/ui-managers` devDependency | no unit tests ship, add your own |
| Any (service pattern) | `playkit-js-kaltura-cuepoints` | registers its own service (`kalturaCuepoints`) in the constructor; copy if the plugin should expose a service to *other* plugins | its `kaltura` package.json field (internal convention, research §10) |
| Any (minimal utility) | `playkit-js-detect-ad-block` | small, dependency-free plugin shape | n/a |

**Never use as a model:** `playkit-js-plugin-generator` (abandoned since 2020, research §13) or any
Flow-era plugin (`playkit-js-ima`, `playkit-js-youbora`); they predate the current TypeScript
`BasePlugin` contract and will teach the wrong lifecycle.

## Extra hooks, orthogonal to the branch

These duck-typed hooks (research §3) layer on top of any of the four branches. Add one only when the
prompt gives a concrete reason, not by default:

- **`getMiddlewareImpl()`**: only when the plugin must gate `play`/`pause`/`load` itself (for
  example, a pre-roll or consent gate). It's pushed onto `_localPlayer.playbackMiddleware`.
- **`getEngineDecorator()`**: only when the plugin wraps the media engine itself. Rare; most UI and
  event-bridge plugins never need it.
- **`get ready()`** override: only for a true async dependency the plugin cannot function without
  (loading a third-party SDK, fetching remote config). Note the trap from research §3: a rejected
  `ready` is swallowed (debug log only, playback continues); it delays playback on a slow resolve,
  but it cannot block playback on failure. A plugin that must block playback on a failed dependency
  has to dispatch a CRITICAL error itself instead of relying on `ready` rejecting.

## Constraints that apply regardless of branch

- **Single plugin only.** Multi-plugin monorepos are out of scope for this skill (plan §7). If the
  prompt describes two unrelated capabilities, ask once whether to split them into two separate
  builds rather than scaffolding a monorepo.
- **Default silently vs. ask once** (plan §5). Infer the branch from the prompt's signals above
  without asking. Ask only when getting it wrong is expensive and the prompt gives no signal at all
  (for example: the prompt is genuinely ambiguous between component UI and side-panel UI). Batch any
  such question with the other open questions from `reference/config-and-validation.md` and ask once,
  not as a drip of separate questions.
- **Always echo the decision back before scaffolding.** State the branch chosen, the signal that
  drove it, and any defaults taken, in one short message the operator can correct before code is
  written (plan §4, phase 0: "Operator has seen the 'building X as Y, say so if wrong' line").

## Exit checks (phase 0, Intake)

Phase 0 is not done until all of these are true (plan §4):

- `PLAN.md` exists in the target repo and states: plugin name (kebab-case), the architecture branch
  chosen from this file, mode (community/internal), the config interface, the events consumed and
  emitted, and at most one open question.
- `PLAN.md` has the Unisphere line from node 0: either `Unisphere: <widget id> / <runtime>` or
  `Unisphere: no Unisphere runtime covers this (checked reference/unisphere-integration.md and
  operator input)`.
- The operator has seen the echo-back line and had a chance to correct it before scaffolding starts.

If any of these is missing, stay in phase 0. Don't scaffold on a guess.
