# playkit-js-plugin-template

A minimal [Kaltura PlayKit-JS](https://github.com/kaltura/kaltura-player-js) player plugin. This is
a placeholder scaffold: rename `playkit-js-plugin-template` / `PluginTemplatePlugin` / `pluginTemplate`
before shipping. See `templates/README.md` (only present in the skill's own repo, not shipped to a
generated plugin) for the rename checklist.

See `docs/guide.md` for task-oriented how-tos and the full reference.

## Install

Two ways to install, pick one:

**Script tag (direct/self-hosted embed).** Once a release is tagged, load the pinned build from
jsDelivr with Subresource Integrity:

```html
<script
  src="https://cdn.jsdelivr.net/gh/<org>/<repo>@vX.Y.Z/dist/playkit-js-plugin-template.js"
  integrity="sha384-<computed-against-that-exact-file>"
  crossorigin="anonymous"
></script>
```

Never use a floating `@latest` tag: it re-caches every 7 days and any SRI hash computed against it
goes stale the moment jsDelivr's `@latest` pointer moves. Always pin the exact tag you cut.

**npm (build pipeline).**

```bash
npm install playkit-js-plugin-template@X.Y.Z
```

```ts
import '@playkit-js/kaltura-player-js';
import 'playkit-js-plugin-template';
```

## Config

<!-- CONFIG_TABLE:START -->
This scaffold ships an empty config (`PluginTemplateConfig {}`) on purpose -- it has no options yet.
When you add config fields, generate this table from the TypeScript interface rather than hand-typing
it (reference/docs-and-demo.md §3); this template does not yet wire that generation script (see
`templates/README.md`, "Known gap: no config-table/i18n-snippet generator").

| Key | Type | Default | Description |
|---|---|---|---|
| _(none yet)_ | | | |
<!-- CONFIG_TABLE:END -->

## Events

This scaffold dispatches no plugin-specific events. When you add one, list it here by name with a
one-line description of its payload (see `reference/error-event-taxonomy.md` for how player-level
errors are structured; don't restate that taxonomy here, only this plugin's own event names).

## Browser support

Matches Kaltura Player V7's supported browser matrix. This scaffold adds no further narrowing (no
third-party SDK, no browser-specific feature use).

## Trusted Types

This plugin is safe to run under an enforcing `Content-Security-Policy: require-trusted-types-for
'script'`, verified by `npm run test:e2e` against zero `securitypolicyviolation` events. Two upstream
exceptions in the player stack itself, not this plugin, still apply:

- **iframe embed**: `playkit-js`'s `player.ts` sets `title.innerHTML` only when the player is
  embedded inside an iframe.
- **prebid**: `playkit-js`'s `loadScriptAsync` assigns `script.src`, but only through the prebid ad
  manager's code path.

A top-level (non-iframe) page with no prebid runs clean under this CSP today. If this plugin's demo
or e2e page ever switches from a local mp4 to an HLS/DASH source, Trusted Types compatibility for
hls.js/dash.js/Shaka has not been independently verified; re-check before claiming it.

## SaaS whitelisting

> On Kaltura SaaS, this plugin runs only after Kaltura has whitelisted it in the partner's player
> bundler configuration. Self-hosted players and custom embeds that load the player and this plugin's
> script directly do not have that restriction.

## License

MIT, see [`LICENSE`](./LICENSE).
