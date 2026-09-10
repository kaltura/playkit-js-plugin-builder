# playkit-js-plugin-builder

A Claude Code skill that takes one natural-language prompt and builds a compliant, tested, documented,
secure, production-ready Kaltura PlayKit-JS player plugin.

**Status: content complete, pre-release.** All 13 reference files are written and eval-tested (see
`docs/plans/2026-09-09-evals-results.md`): intake routing, four full e2e builds, and a baseline
comparison all meet threshold. Still open: a `templates/` community scaffold, the repo's public GitHub
home, and marketplace submission — see `AGENTS.md`'s "Definition of done" for the exact list. See
`docs/plans/2026-09-09-plugin-skill-plan.md` for the build plan and
`docs/plans/2026-09-09-plugin-skill-research.md` for the research it's grounded in.

## What this does

Give an agent one prompt describing a Kaltura player plugin. The skill walks it through:

intake → scaffold → implement → test → document → security review → quality gate → CI/CD + release →
handoff (PR).

Before choosing an architecture, the skill checks whether Kaltura's Unisphere platform already ships
the capability as a runtime (for example AI video summary or Genie chat). If it does, the plugin is a
thin consumer on `@playkit-js/unisphere-service`, not a rebuild.

Two operating modes:

- **Community mode** (default) — self-contained: plain GitHub Actions, Playwright e2e, jsDelivr distribution,
  GitHub Pages docs. No Kaltura-internal access required.
- **Internal mode** (opt-in) — for Kaltura employees: scaffolds from the real
  `playkit-js-plugin-example` template and wires the internal CI/CD workflows. May also author a new
  Unisphere runtime when none exists; community mode only consumes existing ones.

## Install

Run these two commands in Claude Code (this repo's `.claude-plugin/marketplace.json` is itself a
valid single-plugin marketplace, so no separate marketplace repo is needed):

```
/plugin marketplace add kaltura/playkit-js-plugin-builder
/plugin install playkit-js-plugin-builder@playkit-js-plugin-builder-marketplace
```

Restart Claude Code (or start a new session) after installing so the skill loads.

**Alternative, no plugin system needed:** copy `skills/playkit-js-plugin-builder/` into your own
project's `.claude/skills/playkit-js-plugin-builder/`. Claude Code picks up any skill under
`.claude/skills/` automatically, with no marketplace or install step.

## Use it

In any Claude Code session where the skill is installed (or copied in), just describe the plugin you
want in plain language — no slash command, no special syntax:

```
Build a Kaltura player plugin that shows a chapters list side panel, generated from the video's cue points.
```

```
Add the Kaltura Unisphere AI video summary panel to the player.
```

```
Build a plugin that sends playback analytics events to our own endpoint.
```

Claude checks first whether Kaltura's Unisphere platform already ships the capability as a runtime
(video summary, Genie chat) and reuses it instead of rebuilding it; otherwise it picks the right
architecture itself (event-bridge, component UI, or side-panel UI), scaffolds the repo, writes the
plugin, tests it, documents it, runs a security pass, wires CI/CD, and opens a PR. It asks you only
what it can't safely infer (e.g. community vs. Kaltura-internal mode, if that can't be auto-detected;
a partner/entry ID for the demo, defaulting to a mock provider if you don't have one handy) — see
`skills/playkit-js-plugin-builder/SKILL.md` for the full phase-by-phase workflow and exit checks.

## For contributors building this skill

Read `AGENTS.md`.

## License

MIT — see [LICENSE](LICENSE).
