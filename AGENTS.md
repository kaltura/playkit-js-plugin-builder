# AGENTS.md — building the `playkit-js-plugin-builder` skill

This repo is not a plugin. It's a Claude Code skill/plugin whose job is to make *other* agents build
Kaltura PlayKit-JS plugins correctly from one prompt. You are building the skill's expertise content,
not a plugin.

## Read first, in this order

1. `docs/plans/2026-09-09-plugin-skill-research.md` — every Kaltura API/architecture fact used in this
   package, each traced to a pinned SHA. Treat this as ground truth; don't re-derive from memory.
2. `docs/plans/2026-09-09-plugin-skill-plan.md` — the target layout, the 9-phase workflow with runnable
   exit checks, and the scope decisions (§5, §6, §7). §6's recommendations are proposed defaults until
   the repo owner confirms them.
3. `docs/plans/2026-09-09-audit-decisions.md` — what the audit changed and why.
4. This file, for how to author the parts that aren't written yet.

## What's already here vs. what you're building

Scaffolding is preseeded: directory tree, `.claude-plugin/plugin.json`, stub `scripts/*.sh`, and stub `skills/playkit-js-plugin-builder/SKILL.md` + `reference/*.md` files
(frontmatter and section headers only, marked `<!-- TODO -->`). None of the reference files have real
content yet — that's the actual build.

## Target package layout

See `docs/plans/2026-09-09-plugin-skill-plan.md` §3 for the full annotated tree. Don't restructure it
without updating that doc — `plugin.json`'s `skills` path and the dev symlink under `.claude/skills/`
depend on the paths matching exactly. Keep `CLAUDE.md` under `.claude/`, not at the root: a root
`CLAUDE.md` fails `claude plugin validate --strict`.

## Authoring `SKILL.md` and `reference/*.md`

Follow the pattern in the installed `karen` skill (read it directly — usually cached at
`~/.claude/plugins/cache/*/karen/*/skills/karen/SKILL.md` — don't reconstruct it from memory):

- `SKILL.md` stays short: frontmatter (`name`, `description`, `license`, `argument-hint`; no
  `when_to_use`, it breaks portable validation) + a table of named
  procedures, each pointing at one `reference/*.md` file. The skill's actual expertise lives in the
  reference files, read on demand — not duplicated into `SKILL.md`.
- Each `reference/*.md` is self-contained: someone should be able to open just that one file and act
  on it without having read the others first.
- Every factual claim about Kaltura's API, guidelines, or taxonomy must cite or match
  `docs/plans/2026-09-09-plugin-skill-research.md`. If you need a fact that research doesn't cover,
  fetch it live from the Kaltura repos (`kaltura-player-js`, `playkit-js-plugin-example`,
  `playkit-js-ui`, `playkit-js-providers`, and for Unisphere `playkit-js-unisphere-service`,
  `playkit-js-unisphere-summary`, `playkit-js-unisphere-genie`) — don't guess. Those three plugin
  repos are org-internal on GitHub; without org access, use `https://unisphere.kaltura.com/docs`
  (public, no login — verified 2026-09-09; consumption docs, not the repos) or npm (`npm view <pkg>`)
  as the fallback source.
- Unisphere-first (research §16, plan §6.16): when the requested capability already exists as a
  Unisphere runtime, the skill must route to the Unisphere consumer branch
  (`reference/unisphere-integration.md`) before any classic branch. Keep internal-only details
  (registry tokens, internal hostnames, region lists, deploy credentials) out of every tracked file.

## Workflow this skill teaches agents to run

The 9 phases (Intake → Handoff) are specified in the plan doc §4, each with a concrete exit condition,
not a vibe. When you write `reference/testing-strategy.md`, `reference/ci-cd-modes.md`, etc., encode
those exit conditions as checks an agent can actually run (a command, a file that must exist, a test
that must pass) — same "decompose into a count that hits zero" discipline the `karen` skill uses.

## Two modes, don't blur them

Community mode (self-contained, default) vs. internal mode (Kaltura-employee, opt-in) — see plan §2.
Every reference file that touches CI/CD, distribution, or scaffolding needs to say which mode it
applies to, or cover both explicitly. Don't write internal-mode assumptions into a file that community
operators will read.

## Definition of done for a v1 of this skill

Plan §8 is the list. In short: 13 real reference files, a `templates/` community scaffold that passes
phase 1, `detect-mode.sh` working, four dry-run prompts reaching phase 8 (one with a second locale, one on
the Unisphere consumer branch, all under an enforcing Trusted Types CSP), the `evals/` harness (intake set plus four e2e cases) run and meeting its thresholds,
`claude plugin validate --strict .` passing, `marketplace.json` install-tested and submitted, repo name
settled.

## Non-goals (v1)

- Multi-plugin monorepos.
- Non-JS PlayKit SDKs (iOS/Android/tvOS).

## Open decisions

Resolved by the repo owner on 2026-09-09:

- LICENSE: **MIT** (see `LICENSE`, and `license` in `.claude-plugin/plugin.json`).
- Repository home and name: **`kaltura/playkit-js-plugin-builder`** (resolved 2026-09-10, matching
  the plugin name, skill folder, and marketplace entry already used everywhere else in this repo;
  `homepage`/`repository` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
  updated to match).

Still open — ask via one batched question if you're picking this up and these matter to your task:

- The sixteen recommendations in plan §6 — proposed defaults, not yet explicitly confirmed. §6.9
  (Playwright for community e2e, Cypress for internal) is the only one that splits the modes.

## Composable skills to lean on, not reimplement

`karen` (quality-gate harness), `security-review`, `authoring-kaltura-docs`, `code-review`/`simplify`,
`harnessed-build`. Reference them from `reference/*.md` with a documented fallback checklist for when
they're not installed in the target environment — see plan §6.4.
