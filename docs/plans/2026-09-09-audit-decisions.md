# Audit decisions, 2026-09-09

What the audit of the plan, research, and scaffolding changed, and why. The audit covered four areas:
core API verification, the official template and UI layer, Claude Code packaging, and market/best-practice
research; the resulting facts are folded into `docs/plans/2026-09-09-plugin-skill-research.md`.

## Research corrections

The first research draft had nine factual errors about the Kaltura API. They are listed in research §15. The most consequential for generated code:

| Wrong | Right | Effect if not fixed |
|---|---|---|
| `isValid(player)` | `isValid()` takes no args and throws by default | Generated plugin never receives the player; a throw kills plugin load |
| Config merged automatically | Shallow spread at construction; deep only in `updateConfig` | Nested defaults silently dropped |
| Dispatch on `player.Event.Error` | That key does not exist; use `player.Event.Core.ERROR` | Errors never reach the player |
| Plugin i18n files auto-loaded | Host page must pass `ui.translations` | Untranslated UI, and README omits the one required step |
| aws-analytics is the model community plugin | It skips `super.destroy()`, uses live-network e2e, tag-pinned Actions | Copying it propagates three defects |

## Scaffolding changes

| Change | Why |
|---|---|
| Skill renamed to `playkit-js-plugin-builder` | Owner's instruction |
| `commands/build-plugin.md` and `.claude/commands/` removed | Commands are legacy; skills are user-invocable and take `$ARGUMENTS`. Two entries for one job |
| `when_to_use` removed from SKILL.md frontmatter | Hard error on portable Agent Skills paths (claude.ai, Skills API). Description carries the trigger text in under 1,024 chars |
| `argument-hint` added | Claude Code UX for `/playkit-js-plugin-builder <prompt>`. Stripped by `export-portable.sh` |
| `CLAUDE.md` moved to `.claude/CLAUDE.md`, import is `@../AGENTS.md` | Root `CLAUDE.md` fails `claude plugin validate --strict`. Verified passing after the move. `./.claude/CLAUDE.md` is a documented memory location and relative imports resolve from the importing file |
| `reference/services-and-ui-managers.md` added (12 reference files); `reference/unisphere-integration.md` added 2026-09-09 (13) | Transcript and cuepoints plugins use the services registry and `@playkit-js/ui-managers`. Without it, only trivial UI plugins are possible |
| `PORTABLE_AGENTS.md` dropped as a committed file | Skills are an open standard. Flattened export is an optional `dist/` artifact |
| `templates/`, `evals/`, `marketplace.json` planned | Deterministic scaffold; acceptance tests; installability. Marketplace gated on a tested self-hosted install |

## Plan changes

- Three architecture branches (event-bridge, component UI, side-panel UI) instead of two.
- Every phase exit is a command or file check, listed in plan §4.
- Cypress defaults to the mock provider with a pinned player version. Live network is opt-in.
- Community CI ships SHA-pinned Actions, least-privilege `permissions:`, Dependabot.
- Resilience rules folded into `error-event-taxonomy.md` and `base-plugin-api.md`. Accessibility folded into `ui-components.md`.
- Definition of done (plan §8) now includes `evals/` cases and `claude plugin validate --strict` passing.
- 2026-09-09, owner decision: four items moved from "Not in v1" into v1. Multi-language i18n (host-page contract, research §6.3), Trusted Types enforcement on e2e/demo pages plus sink lint (research §6.6), running evals (own harness, see below), and marketplace publishing beyond self-hosted. Plan §6.12 to §6.15 and §8.8 to §8.11 carry the details.
- 2026-09-09, owner request: **Unisphere-first.** Live review (gh, 102 `playkit-js*` repos plus the Unisphere workspace repos, research §16) found Kaltura's newest player features (video summary, Genie chat) shipped as Unisphere runtimes consumed through `@playkit-js/unisphere-service`. Decision: a fourth architecture branch, **Unisphere consumer**, checked before the three classic ones (plan §1, §5, §6.5, §6.16). When a runtime exists, the plugin is a thin consumer in the `unisphere-summary` shape and never loads its own workspace. Community mode consumes only; internal mode may also author and deploy runtimes (plan §2). Adds `reference/unisphere-integration.md`, a fourth dry run and e2e eval case, a Unisphere line in the phase 0 exit and a grep in phase 2 (plan §4, §8). Gaps kept explicit rather than guessed (research §14): Trusted Types with the loader, runtime entitlement, production loader URL for self-hosted players, docs naming npm packages that do not exist. Internal-only details (registry tokens, hostnames, regions, deploy tooling access) stay out of tracked files.
- 2026-09-09, correction (repo owner spot-checked the claim and asked to verify): the first Unisphere
  pass wrongly concluded the public docs site (`unisphere.kaltura.com`) is unreadable outside Kaltura
  ("returns 403 for every `/docs/*` page"). Re-checked live: the site is public, no login, indexed-off
  but directly reachable (`robots.txt` blocks crawling, not access); the one 403 found was a guessed
  URL that doesn't exist (`getting-started/load-unisphere` vs. the real `getting-started/loader`).
  Corrected: consuming Unisphere (npm packages or the public docs) needs no internal access at all;
  only the plugin repos' exact source and the "Create" (author-a-new-runtime) track are gated to
  Kaltura employees, and the docs state a "contact Kaltura" partnership path for the latter. Research
  §16 (source note, §16.2, §16.9), plan §2, `reference/unisphere-integration.md`, and `AGENTS.md`
  updated. Also picked up a live, more precise public API not previously documented: a declarative
  `UnisphereWorkspaceConfig` shape with inline `runtimes[]`/`visuals[]` (research §16.1).

## Market research consequences (report 04)

| Finding | Decision |
|---|---|
| Bare npm `kaltura-player-js` has a known-malicious version (OSV MAL-2025-41390) | Scoped name only; lint hard-fail in scaffold and tests. Nothing in this repo depends on it |
| Official generator CLI abandoned 2020 | Template is `playkit-js-plugin-example` |
| No comparable scaffold in any player ecosystem or agent-skill directory | Design from first principles; no prior art to port |
| Cypress WebKit still experimental | Playwright default in community mode, Cypress in internal mode (proposed, see plan §6.9) |
| npm 12 blocks install scripts by default | CI templates add an explicit browser install step |
| SaaS players run only whitelisted plugins | Generated README states it |
| jsDelivr: never `@latest` with SRI | Docs and demo pin exact tags with SRI |
| WCAG 2.2 adds 2.4.11 focus-not-obscured; Kaltura has a V7 VPAT | UI branch a11y checks; docs cite the VPAT |

## Still open for the repo owner

1. Plan §6 recommendations are proposed defaults, not confirmed.
2. Resolved 2026-09-10: repo name and home settled as `kaltura/playkit-js-plugin-builder` (see `AGENTS.md`).
3. Resolved 2026-09-09: skip the gated `claude plugin eval` (CLI prints "currently in early access", nothing in public docs). Build a self-owned harness under `evals/` per Anthropic's develop-tests guidance (plan §6.14, §8.10).
4. Playwright (community) vs Cypress (internal) split, or one runner for both.
5. Official marketplace listing needs the Kaltura Anthropic partner contact; there is no form (plan §6.15).
6. Unisphere e2e in CI needs a loader URL Kaltura is willing to expose to the repo (`UNISPHERE_LOADER_URL` secret/var). Until then the case skips (plan §8.4).
7. 2026-09-09, decision: `evals/run.sh`'s `invoke_claude_intake`/`invoke_claude_e2e` stay a deliberate no-op rather than being wired to call `claude -p` for real. Reason: that call would be a real, uncontrolled-cost recursive Claude Code invocation from inside a running session, exactly the risk the harness's own README flags. Plan §8 item 4 (four dry-run prompts reaching phase 8) was instead satisfied directly: a Workflow ran all four required cases end to end against the real skill content, in scratch directories, with real `npm ci`/`build`/`lint`/`type-check`/`test`/`test:e2e` runs, graded by `evals/grade.py e2e` against each case's `expect.yaml`. Wiring `run.sh` for real (to meet plan §8 item 10's repeated-run thresholds) needs an explicit owner decision on acceptable spend and whether it should run in CI or only on demand.
