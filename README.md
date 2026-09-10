# playkit-js-plugin-builder

A Claude Code skill that builds a Kaltura PlayKit-JS player plugin from one prompt. Tested, documented,
secured, ready for a PR.

**Status: v1.** All 13 reference files are written. The eval suite passes (intake routing, 4 e2e
builds, baseline comparison — see `docs/plans/2026-09-09-evals-results.md`). The `templates/` scaffold
builds, lints, type-checks, and passes its e2e tests. Only marketplace submission is still open (see
`AGENTS.md`).

## What this does

You describe a plugin. The skill:

1. Checks if Kaltura's Unisphere platform already ships it as a runtime (video summary, Genie chat).
   If so, it builds a thin consumer instead of rebuilding the feature.
2. Otherwise picks an architecture (event-bridge, component UI, or side-panel UI).
3. Scaffolds, implements, tests, documents, security-reviews, wires CI/CD, and opens a PR.

Two modes:

- **Community** (default) — self-contained. GitHub Actions, Playwright e2e, jsDelivr distribution. No
  Kaltura-internal access needed.
- **Internal** (opt-in, Kaltura employees) — uses the real `playkit-js-plugin-example` template and
  internal CI/CD. Can also author new Unisphere runtimes.

## Install

```
/plugin marketplace add kaltura/playkit-js-plugin-builder
/plugin install playkit-js-plugin-builder@playkit-js-plugin-builder-marketplace
```

Restart Claude Code so the skill loads.

**No plugin system?** Copy `skills/playkit-js-plugin-builder/` to `.claude/skills/` in your own
project. Claude Code picks it up automatically.

## Use it

Open (or create) an empty directory for your new plugin, then just ask:

```
Build a Kaltura player plugin that shows a chapters list side panel, generated from the video's cue points.
```

```
Add the Kaltura Unisphere AI video summary panel to the player.
```

```
Build a plugin that sends playback analytics events to our own endpoint.
```

Claude states its plan back to you (name, architecture, mode, config, events) before scaffolding. It
only asks you questions when it truly can't guess safely — e.g. community vs. internal mode, or which
partner/entry ID to use for the demo.

Full workflow and exit checks: `skills/playkit-js-plugin-builder/SKILL.md`.

## Run and test the plugin it builds

The output is a normal npm package. From its directory:

```bash
npm ci             # install
npm run build      # build the bundle
npm run lint        # eslint
npm run type-check  # tsc --noEmit
npm test            # unit tests
npm run test:e2e    # e2e tests, in a real browser
```

| Command | What it checks |
|---|---|
| `build` / `lint` / `type-check` | Compiles, follows style rules, no type errors |
| `test` | Lifecycle: valid load, bad config, `disable: true`, media change, destroy, error path |
| `test:e2e` | Works in a real browser. UI plugins also get keyboard/a11y checks and a strict CSP check |

To see it running: `npm run build`, then serve the repo with a static server (e.g. `npx http-server .`)
and open `demo/index.html`. Don't open the file directly — the player needs an HTTP origin.

## Try the scaffold directly

Skip the prompt and just look at the starting point:

```bash
cp -r skills/playkit-js-plugin-builder/templates/ my-plugin
cd my-plugin
npm ci && npm run build && npm test && npm run test:e2e
```

It's a real, minimal plugin — everything above passes out of the box. See `SCAFFOLDER-NOTES.md` and
`docs/guide.md` inside it for the rename checklist before you ship it as your own.

## Contributing to this skill

Read `AGENTS.md`.

## License

MIT — see [LICENSE](LICENSE).
