---
name: playkit-js-plugin-builder
description: Builds a production-ready Kaltura PlayKit-JS player plugin from one natural-language prompt. Checks first whether Kaltura's Unisphere platform already ships the capability as a runtime and, if so, builds a thin consumer plugin on it instead of rebuilding; otherwise decides the architecture (event-bridge, component UI, or side-panel UI). Scaffolds the repo, implements the BasePlugin subclass with validated config and correct lifecycle, writes unit and end-to-end tests, docs and a demo, runs a security pass, wires CI/CD for community or Kaltura-internal mode, and prepares the first tagged release. Use when the user asks to create, scaffold, build, or generate a Kaltura player plugin, a PlayKit-JS plugin, a kaltura-player-js plugin, or describes player behavior they want packaged as a plugin.
license: MIT
argument-hint: "<describe the plugin you want, e.g. 'show a chapter list side panel from cue points'>"
---

# PlayKit-JS Plugin Builder

Turns one prompt describing player behavior into a finished, tested, documented Kaltura PlayKit-JS
plugin, ready for a PR. It does not just rename a template: it picks the right architecture, writes
real plugin logic, tests it, secures it, and wires CI/CD for the operator's mode. It does not build
multi-plugin monorepos or non-JS PlayKit SDKs (iOS/Android/tvOS), both out of scope for v1.

Every Kaltura API fact this skill relies on traces to `../../docs/plans/2026-09-09-plugin-skill-research.md`
(pinned to specific commits). If you need a fact that file doesn't cover, fetch it live from the source
repos or `unisphere.kaltura.com/docs`. Don't guess from memory.

## Unisphere-first

Before picking an architecture, check whether the requested capability already exists as a Unisphere
runtime (for example: video summary, Genie chat, or one the operator names).

- **It does exist as a runtime** → build a thin consumer plugin on `@playkit-js/unisphere-service`.
  Don't reimplement the feature, the panel, the icon, or the workspace load. This works in both modes:
  community mode can consume any runtime it can reach, no internal access needed. Internal mode can
  also author a new runtime. See `use_unisphere` below.
- **It doesn't exist as a runtime** → fall through to the three classic branches (event-bridge,
  component UI, side-panel UI), decided by `decide_architecture`.

Run this check first, every time. Rebuilding a feature Unisphere already ships is the single biggest
architecture mistake this skill can make.

## The workflow

Nine phases, each with a check you actually run, not a self-rating. Full detail for each phase lives
in the named procedure's reference file.

| # | Phase | Exit check |
|---|---|---|
| 0 | Intake | `PLAN.md` states name, architecture branch, mode, config interface, events, ≤1 open question, and the Unisphere check result. Operator has seen the defaults stated back. |
| 1 | Scaffold | `npm ci && npm run build && npm run lint && npm run type-check` exit 0 on the empty plugin. Depends on `@playkit-js/kaltura-player-js`, never bare `kaltura-player-js`. |
| 2 | Implement | `isValid()` takes no args, returns `false` on bad config (no throw). `destroy()` calls `super.destroy()`. No `player.Event.Error`. `registerPlugin` return asserted in a test. Unisphere branch: workspace only via `player.getService('unisphereService')`, no direct `@unisphere/runtime-js` import. |
| 3 | Test | `npm test && npm run test:e2e` green. Lifecycle tests cover valid load, invalid config, `disable: true`, change media, destroy, error path. UI branch adds keyboard/`aria-label` checks and an enforcing Trusted Types CSP with zero violations. Multi-locale UI adds a translation key-parity test plus a non-`en` e2e run. |
| 4 | Document | README, `docs/guide.md`, `demo/index.html` exist. Config table matches the TS interface (diffed, not eyeballed). UI text implies a generated `ui.translations` README block. |
| 5 | Secure | `security-review` findings closed (or the fallback checklist fully ticked). `npm audit --audit-level=high` and an OSV scan clean. Actions SHA-pinned, least-privilege `permissions:`. No secrets tracked. No Trusted Types sinks in `src/`. |
| 6 | Quality gate | `karen audit` green if present; else lint, type-check, build, unit, e2e, audit all exit 0 and `git status` clean. |
| 7 | CI/CD and release | Mode-appropriate workflows pass on a push. First tag cut. Community: `dist/` committed at tag, jsDelivr URL resolves. Internal: canary workflow green. |
| 8 | Handoff | PR open, stating what was built, the architecture branch, what was defaulted, and any open question. CI green is not the merge signal; a human or Copilot review is. |

Never ask for what you can infer from the prompt (name, architecture branch, i18n need, lifecycle
hooks). Ask once, batched, only when guessing wrong is expensive: mode when `detect-mode.sh` returns
`ambiguous`, a third-party CDN SDK choice, or partner/entry ID for the demo (default to the mock
provider and say so). Always state defaults back before scaffolding, per plan §5.

## Named procedures

| Named procedure | What you actually do | Detail |
|---|---|---|
| `decide_architecture` | Check Unisphere first; then choose event-bridge vs component UI vs side-panel UI; echo the decision back to the operator | `reference/decision-tree.md` |
| `apply_base_plugin_api` | Implement the `BasePlugin` subclass with the correct lifecycle, `isValid()`, `registerPlugin` | `reference/base-plugin-api.md` |
| `validate_config` | Validate config at the boundary, merge nested defaults explicitly, avoid the shallow-merge footgun | `reference/config-and-validation.md` |
| `apply_error_event_taxonomy` | Emit errors via `Error(severity, category, code, data)` on `player.Event.Core.ERROR`, keep failures RECOVERABLE where possible | `reference/error-event-taxonomy.md` |
| `apply_coding_guidelines` | Follow Kaltura's naming, structure, and style rules for plugin source | `reference/coding-guidelines.md` |
| `build_ui_components` | Build UI with `addComponent`, i18n, and a11y, only for the component UI branch | `reference/ui-components.md` |
| `use_services_and_ui_managers` | Use the services registry and `@playkit-js/ui-managers`, only for the side-panel branch or cross-plugin services | `reference/services-and-ui-managers.md` |
| `use_unisphere` | Build the thin consumer on `@playkit-js/unisphere-service`, only when the capability already exists as a Unisphere runtime; never rebuild it | `reference/unisphere-integration.md` |
| `write_tests` | Write unit and e2e tests, including the lifecycle list and the enforcing-CSP check | `reference/testing-strategy.md` |
| `write_docs` | Write README, guide, demo, and the generated config/translations tables | `reference/docs-and-demo.md` |
| `run_security_checklist` | Run `security-review` or the fallback checklist; supply chain, CSP, secrets | `reference/security-checklist.md` |
| `wire_ci_cd` | Wire the mode-appropriate CI/CD workflows | `reference/ci-cd-modes.md` |
| `release` | Cut the first tag and set up distribution (jsDelivr or npm) | `reference/release-and-versioning.md` |

## Two modes

Community mode (default, self-contained) and internal mode (Kaltura-employee, opt-in) differ in
scaffold source, CI runner, e2e runner, distribution, and Unisphere authoring rights. See plan §2 for
the full comparison table.

Run `${CLAUDE_SKILL_DIR}/../../scripts/detect-mode.sh` to get `community`, `internal`, or `ambiguous`.
Only ask the operator (via `AskUserQuestion`, batched with any other open question) when the result is
`ambiguous`. Every reference file that touches CI/CD, distribution, or scaffolding says which mode it
covers, or covers both explicitly. Don't carry internal-mode assumptions into community-mode work.

## Stopping condition

Done, for one invocation: every phase 0-8's exit check above has actually run and passed, `karen audit`
is green if present (else the fallback checklist is), the PR is open with the phase-8 body, and no
open question remains unasked. A phase that "looks fine" without its check having run is not done.
