# Scaffolder notes (internal to this skill -- do not copy into a generated plugin)

This file is for whoever copies `templates/` to start a real plugin build. It is **not** part of the
generated plugin's own docs; don't ship it. (The brief that produced this scaffold calls this file
`templates/README.md`, but `README.md` at that same path is itself a shipped deliverable -- the
plugin's own top-level README, required by `reference/docs-and-demo.md`. Naming both files
`README.md` at the same path is a literal contradiction, so this internal note lives at
`SCAFFOLDER-NOTES.md` instead. See "Deviations from the brief" below.)

## Placeholder identity used in this scaffold

- Package name: `playkit-js-plugin-template`
- Class name: `PluginTemplatePlugin`
- Registered (camelCase) plugin name: `pluginTemplate`
- Output bundle: `dist/playkit-js-plugin-template.js`
- File to rename: `src/plugin-template-plugin.ts`

Before a real build, replace every literal occurrence of these three strings across the repo. See
`docs/guide.md`'s "How-to: rename this scaffold for a real plugin" section for the exact file list
and the verification command to run afterward.

## CI SHA-placeholder caveat

`.github/workflows/ci.yml`'s `uses:` lines use the literal placeholder text `<sha>` instead of a real
40-character commit SHA (e.g. `uses: actions/checkout@<sha>` rather than a real hash). This is
deliberate: resolving a real SHA per action requires a live `gh api repos/<owner>/<repo>/commits/<tag>
--jq .sha` call per action, which is a scaffold-time step (run once the real repo exists and `gh` has
network/auth access), not something that can be baked into this template while it's being authored.

**Before this workflow can actually run in CI**, resolve every `<sha>` to a real commit SHA for the
action version you want (keep the trailing `# vX.Y.Z` comment showing which tag that SHA resolves
to). Until that's done, `reference/security-checklist.md`'s exit check (`grep -c "uses: "` vs.
`grep -c "uses: .*@[0-9a-f]\{40\}"` must match) will correctly report a mismatch -- that mismatch is
expected on this template as committed, not a build error to chase down before resolving the SHAs.

## Known gap: no config-table/i18n-snippet generator

`reference/docs-and-demo.md` §3-§4 wants the README's config table and `ui.translations` block
generated from source and diffed in CI (`docs:config-table`, `i18n:snippet` npm scripts). This
scaffold's placeholder plugin has an empty config interface and no UI text, so there's nothing yet
for either generator to diff against, and the brief that produced this scaffold didn't list a
generator script among its deliverables. `README.md` documents this gap inline (see its "Config"
section) rather than silently omitting the `CONFIG_TABLE:START`/`:END` markers. Add both generator
scripts, wired into `ci.yml`'s `build` job with a `--check` flag, the same day a real config field or
UI string is added -- don't let the table go stale the way the official Kaltura template's did
(`reference/docs-and-demo.md` §9).

## Deviations from the brief that produced this scaffold

- **README naming.** The brief asked for a shipped `README.md` (docs-and-demo.md-compliant) and a
  separate internal note also called `templates/README.md`, at what is the identical path once this
  directory is the thing being copied. Resolution: the shipped README stays at `README.md`; this
  internal note lives at `SCAFFOLDER-NOTES.md` instead.
- **No config-table/i18n-snippet generator script.** See "Known gap" above -- out of this scaffold's
  brief-specified deliverable list, and not yet needed with an empty config/no UI text.
- **Toolchain: Vitest + Playwright + `ts-loader`, not Jest/babel.** A pre-existing draft in this
  directory (found already staged in git before this rewrite) used Jest and babel-loader. Rewritten
  to Vitest/Playwright (community-mode default per `reference/testing-strategy.md`) and `ts-loader`
  (matches the one real, previously-verified-working plugin build from this same skill this scaffold
  mirrors for its e2e/CI/tooling shape).
- **Dependency versions.** Pinned to match that same previously-verified-working example
  (`@playkit-js/kaltura-player-js@3.17.97`, `vitest@^4.1.11`, `jsdom@^25.0.1`, `eslint@^8.57.0` with
  the legacy `.eslintrc.json` format, `@typescript-eslint/*@^8.0.0`, `webpack-cli@^5.1.4`) rather than
  whatever a plain `npm view <pkg> version` would resolve to today, since that combination is the one
  actually confirmed to build, lint, type-check, test, and pass e2e in this environment.
