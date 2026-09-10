# Guide

This guide follows [Diátaxis](https://diataxis.fr/): how-to sections for a specific task, a full
reference below that, and an explanation section for the "why" behind non-obvious choices. The
README covers install and a quick summary only; this file is where the detail lives.

## How-to: rename this scaffold for a real plugin

1. Pick your plugin's name in three forms: a kebab-case package/file name (`my-plugin`), a
   PascalCase class name (`MyPluginPlugin`), and a camelCase registered name (`myPlugin`).
2. Replace every occurrence of `playkit-js-plugin-template` / `PluginTemplatePlugin` / `pluginTemplate`
   across the repo (`package.json`, `webpack.config.js`'s `output.filename` and `output.library`,
   `src/index.ts`, `src/plugin-template-plugin.ts` renamed to `src/<name>-plugin.ts`, `e2e/index.html`,
   `demo/index.html`, this guide, `README.md`).
3. Run `npm run build && npm run lint && npm run type-check && npm test && npm run test:e2e` and
   confirm all five pass before writing any new plugin logic.

## How-to: add a config option

1. Add the field to `PluginTemplateConfig` in `src/plugin-template-plugin.ts`, with a JSDoc comment
   describing it (the future config-table generator reads that comment).
2. Add a default value to `static defaultConfig`.
3. If the field is a nested object, merge it explicitly in the constructor right after `super(...)`
   -- the constructor's merge is a shallow spread, so a nested default is replaced wholesale, not
   merged, unless you merge it yourself. See `reference/config-and-validation.md` §1 in the skill
   that generated this scaffold for the exact pattern and why it matters.
4. Validate the merged config once, at the constructor boundary and again at the top of any
   `updateConfig` override, following the `normalizeConfig` pattern in
   `reference/config-and-validation.md` §3.
5. Add the shallow-merge regression test and the `updateConfig` re-validation test described in that
   same file's "Tests" section.

## How-to: add a second locale

1. Add `translations/<locale>.i18n.json` with the same key set as `translations/en.i18n.json`.
2. Pass `ui.translations` and `ui.locale` from the host page config (this plugin does not read its
   own translation files at runtime; `playkit-js-ui` never auto-loads them).
3. Add both locales' `ui.translations` sub-objects to a "UI translations" section in `README.md` once
   the plugin actually ships UI text; this scaffold has none, so that section is absent here.

## Reference

- **Package**: `playkit-js-plugin-template`
- **Registered plugin name**: `pluginTemplate`
- **Exported class**: `PluginTemplatePlugin` (from `src/plugin-template-plugin.ts`, re-exported by
  `src/index.ts`)
- **Config type**: `PluginTemplateConfig` (currently empty)
- **Build output**: a single UMD bundle, `dist/playkit-js-plugin-template.js`, attached at
  `window.KalturaPlayer.plugins.pluginTemplate`
- **Scripts**: `npm run build`, `npm run build:dev`, `npm run lint`, `npm run type-check`, `npm test`,
  `npm run test:e2e`, `npm run release` -- every one of these exists in `package.json`; don't
  document a script that isn't there.

## Explanation

**Why config is validated once, at construction and at `updateConfig`, not scattered through the
plugin.** Two places in a plugin's public surface receive data the plugin author doesn't control:
the constructor and any later `updateConfig` call. Everywhere else (`loadMedia()`, event handlers,
internal helpers) reads `this.config` and trusts it. A second validation pass inside those internal
methods would duplicate the boundary check and drift out of sync with it as the plugin evolves.

**Why the build must stay UMD, never ESM-only.** A plain `<script src="...">` tag -- the install
method this README documents first -- can't load an ESM-only bundle. The e2e and demo pages both
load the plugin exactly that way, so an ESM-only build would break both, not just the documented
install path.

**Why `preact`/`preact/hooks`/`preact-i18n` are webpack externals here even though this scaffold has
no UI.** Every plugin loaded on the same page shares one Preact instance, provided by the player's
own UMD bundle at `window.KalturaPlayer.ui.preact`. Bundling a second copy of Preact breaks every
other plugin's UI components on that page the moment two incompatible Preact instances try to share
one DOM tree. Keeping the externals mapping in `webpack.config.js` from the start means a later
addition of `addComponent` UI inherits the correct config instead of a bundled, duplicate Preact.

**Why the e2e page enforces `Content-Security-Policy: require-trusted-types-for 'script'` as a real
response header, not just a lint rule.** The ESLint sink-ban rules in `.eslintrc.json` only stop new
code in this plugin from introducing a Trusted Types violation. They can't prove the plugin (plus
the exact player build it runs against) is actually compatible with a host page that turns Trusted
Types on. Only a live page, under the real enforcing header, with a `securitypolicyviolation`
listener registered before any script loads, proves that.

## Known gap in this scaffold

This scaffold does not (yet) wire a config-table/`ui.translations` generator script (would be added
as `docs:config-table` and `i18n:snippet` in `package.json`'s `scripts`). Its config is empty and it
ships no UI text, so there is nothing yet for either generator to diff against. Add both scripts, and
a CI `--check` step for each, the same day you add the first real config field or the first UI
string -- see `templates/README.md`'s "Known gap" note for why this wasn't wired into the scaffold
itself.
