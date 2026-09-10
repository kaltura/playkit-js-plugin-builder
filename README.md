# playkit-js-plugin-builder

A Claude Code skill that takes one natural-language prompt and builds a compliant, tested, documented,
secure, production-ready Kaltura PlayKit-JS player plugin.

**Status: v1 content complete.** All 13 reference files are written and eval-tested (see
`docs/plans/2026-09-09-evals-results.md`): intake routing, four full e2e builds, and a baseline
comparison all meet threshold. The community `templates/` scaffold is built and verified (builds,
lints, type-checks, and passes unit + Playwright e2e, including under an enforcing Trusted Types CSP).
Still open: marketplace submission — see `AGENTS.md`'s "Definition of done" for the exact list. See
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

In any Claude Code session where the skill is installed (or copied in), open (or create) an empty
directory for the new plugin and just describe what you want in plain language — no slash command, no
special syntax:

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
architecture itself (event-bridge, component UI, or side-panel UI). It states its plan (name,
architecture, mode, config, events) back to you before scaffolding, then works through implement,
test, document, security review, quality gate, CI/CD, and opens a PR. It only stops to ask when it
genuinely can't infer something safely — e.g. community vs. Kaltura-internal mode, if
`scripts/detect-mode.sh` can't tell, or a partner/entry ID for the demo (it defaults to a mock
provider if you don't have one handy).

Full phase-by-phase workflow and exit checks: `skills/playkit-js-plugin-builder/SKILL.md`.

### What you get, and how to run it yourself

The output is a normal npm package (a scaffold cloned/generated from
`skills/playkit-js-plugin-builder/templates/` in community mode). Once Claude finishes, or at any
point while it's working, you can run the same checks it does, from the generated plugin's own
directory:

```bash
npm ci                  # install
npm run build           # webpack production bundle -> dist/
npm run lint            # eslint
npm run type-check      # tsc --noEmit
npm test                # vitest unit tests
npm run test:e2e        # playwright e2e (builds first, then runs against a real browser)
```

To see the plugin running in a real page, open `demo/index.html` (a static demo with a real player
and a local video) after `npm run build` — serve the repo root with any static file server (e.g.
`npx http-server .`) rather than opening the file directly, since the player needs an HTTP origin.

What each check is actually verifying:

| Command | Verifies |
|---|---|
| `npm run build` / `lint` / `type-check` | The plugin compiles, follows Kaltura's coding guidelines, and has no type errors |
| `npm test` | Lifecycle correctness: valid load, invalid config (`isValid()` returns `false`, never throws), `disable: true`, media change, `destroy()`, error path |
| `npm run test:e2e` | The plugin actually works in a browser against a real (or mock) player, including keyboard/`aria-label` checks for UI plugins, and zero violations under an enforcing Trusted Types CSP |

If something fails, that's the same signal Claude itself uses to know the build isn't done yet — see
phases 1–3 in `skills/playkit-js-plugin-builder/SKILL.md`'s workflow table.

### Trying the scaffold directly, without a prompt

To see the raw starting point the skill builds from (useful for exploring the shape of a plugin
before asking Claude to change anything):

```bash
cp -r skills/playkit-js-plugin-builder/templates/ my-plugin
cd my-plugin
npm ci && npm run build && npm test && npm run test:e2e
```

This is a real, working (if minimal) plugin — everything above passes cleanly out of the box.
`SCAFFOLDER-NOTES.md` and `docs/guide.md` inside it cover the rename checklist and config/event
conventions before you ship it as your own.

## For contributors building this skill

Read `AGENTS.md`.

## License

MIT — see [LICENSE](LICENSE).
