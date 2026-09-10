# Docs and demo

Covers phase 4 ("Document", plan §4 row 4) of every plugin build: the README, `docs/guide.md`, and
`demo/index.html`. Applies to both modes; the two places mode actually changes something are marked
below. Read this file on its own; it doesn't assume you've read the others, though it points at
`reference/ui-components.md` (i18n contract), `reference/security-checklist.md` (Trusted Types,
CDN/SRI), and `reference/unisphere-integration.md` (Unisphere README requirements) for the detail
each of those files owns.

The rule underneath every section here: **generate from a source that already exists in the repo,
never hand-type a fact the code already states.** The config table comes from the TypeScript
interface. The `ui.translations` block comes from the `translations/` files. The CDN tag comes from
`package.json`'s pinned dependency version. Every one of those three gets a script and a CI diff, not
a human typing a table and hoping it stays in sync. That drift is exactly what happened to the
official template (§6 below).

## 1. Diátaxis structure: what ships, and where

Check first whether the `authoring-kaltura-docs` skill is installed. If it is, use it to produce the
README and `docs/guide.md` in Kaltura's public brand voice, structured by Diátaxis. It already knows
the voice and terminology conventions; don't re-derive them here.

If it is not installed, use this fallback mapping (Diátaxis: tutorial, how-to, reference,
explanation, see https://diataxis.fr/):

| Artifact | Diátaxis quadrant(s) | Contents |
|---|---|---|
| `README.md` | Tutorial (quick start) + a thin reference (config table) | Install, minimal working example, config table, events, browser support, Trusted Types statement, license. Everything an integrator needs in one scroll, no deep explanation. |
| `docs/guide.md` | How-to + reference + explanation | Task-oriented sections ("add a locale", "listen for X event", "customize the panel position"), the full reference the README only summarizes, and the "why" behind non-obvious choices (e.g. why config is validated once at construction, why `ui.translations` is a host-page contract). |
| `demo/index.html` | Tutorial, runnable | A working page an integrator can open and see the plugin do something, with placeholder values clearly flagged. |
| `docs/*.pdf` (optional) | Same content as the guide, exported | Only if the operator asks for an offline/print artifact. Generate from the guide (e.g. weasyprint, matching the community-reference pattern in research §9); don't hand-maintain a second copy. |

A short README that links to a longer guide beats one long README. Don't collapse the guide into the
README just because the plugin is small; keep the split even for a two-page guide, so the pattern is
consistent across every plugin this skill builds.

## 2. README: the required contents

Every generated README states all of the following. Treat this as a checklist, not a suggestion:
phase 4 is not done until every line here exists in the file.

1. **Install**, two ways: the pinned jsDelivr `<script>` tag with SRI (community mode's primary
   distribution, §5 below) and `npm install <package>` at the same pinned version. State which one the
   operator should use when (script tag for a direct/self-hosted embed, npm for a build pipeline).
2. **Full config table**, generated from the TypeScript config interface (§3 below), never hand-typed.
3. **`ui.translations` block** for every shipped locale plus the `ui.locale` line, generated from
   `translations/` (§4 below), only when the plugin ships UI text. Skip this section entirely (don't
   leave an empty header) for an event-bridge plugin with no UI.
4. **Events dispatched** (and, if relevant, consumed), by name, with a one-line description of the
   payload. Cross-reference `reference/error-event-taxonomy.md` for how errors are structured; don't
   restate that whole taxonomy here, just list this plugin's own event names.
5. **Browser support**, stated plainly (e.g. "matches Kaltura Player V7's supported browser matrix";
   name any plugin-specific narrowing, such as a third-party SDK that drops IE/older Safari).
6. **Trusted Types statement**: this plugin is safe to run under an enforcing
   `require-trusted-types-for 'script'` CSP, with the two upstream exceptions named verbatim (iframe
   embed title, prebid ad loader, research §6.6, detailed in `reference/security-checklist.md` §3).
   Don't claim compatibility without naming the exceptions; an integrator who hits one of them needs
   to know it's not this plugin's bug.
7. **License**, matching `LICENSE` and the `license` field in `package.json`. If the plugin is a
   Unisphere consumer, also state the AGPL-3.0 license of `@unisphere/*` and `@playkit-js/unisphere-*`
   next to the plugin's own license (§8 below).
8. **The SaaS whitelisting constraint** (§7 below), stated as a fact, not hedged as a maybe.

## 3. Config table: generated from the TypeScript interface, diffed in CI

Never hand-write the config table. A hand-typed table drifts from the code the moment someone adds or
renames a config key, and nothing catches it until an integrator files a confused issue. Generate it
instead:

- Write a small script (e.g. `scripts/gen-config-table.ts`, run via `npm run docs:config-table`) that
  parses the plugin's exported config `interface`/`type` (the TypeScript compiler API, or a doc-comment
  extractor like `ts-json-schema-generator`/`typedoc` if the plugin's build already depends on one,
  don't add a new heavy dependency just for this) and emits a markdown table: column, type, default
  (read from `static defaultConfig`), and description (from the interface's own doc comments).
- Insert the generated table into `README.md` between two literal marker comments, e.g.:
  ```html
  <!-- CONFIG_TABLE:START -->
  <!-- CONFIG_TABLE:END -->
  ```
  The script replaces everything between the markers and leaves the rest of the README untouched.
- Run the script in `--check` mode in CI (regenerate into a temp buffer, diff against what's
  currently between the markers, fail on any difference). This is what "diffed in CI, never
  hand-typed" (plan §4 row 4) actually means: a human can still write prose around the table, but the
  table's cells are never a manual edit that CI can silently drift from.
- If the config interface has nested objects (the shallow-merge footgun in
  `reference/config-and-validation.md`), flatten nested keys in the table with dotted paths
  (`thresholds.warning`, `thresholds.critical`) rather than a single opaque "object" cell. An
  integrator setting one nested field needs to see its default without reading the source.

Exit check for this section:

```bash
test -f README.md && grep -q "CONFIG_TABLE:START" README.md && grep -q "CONFIG_TABLE:END" README.md
npm run docs:config-table -- --check   # must exit 0; nonzero means the README table is stale
```

## 4. `ui.translations` block: generated from `translations/`, diffed in CI

Only when the plugin ships UI text (`reference/ui-components.md` §4: playkit-js-ui never auto-loads a
plugin's translation files; the host page has to pass `ui.translations` itself). Skip this whole
section, and don't add an empty placeholder header, for a plugin with no UI text.

- `npm run i18n:snippet` reads every `translations/<locale>.i18n.json` the plugin ships and emits the
  `ui.translations` object the host page must pass, one sub-object per locale, plus the `ui.locale`
  line showing how to select a non-`en` default. This is the same script named in
  `reference/ui-components.md` §4 and `reference/testing-strategy.md`; author it once, referenced from
  both docs and tests.
- Insert the generated block into `README.md` (and `demo/index.html`, §5 below) between markers, same
  pattern as the config table:
  ```html
  <!-- UI_TRANSLATIONS:START -->
  <!-- UI_TRANSLATIONS:END -->
  ```
- CI runs `npm run i18n:snippet -- --check` and fails on drift, for the same reason as the config
  table: the official template's own gap was a hand-typed block in `demo/index.html:20-27` that
  nothing kept in sync with the actual translation files (research §6.3, §9's "do not copy" note in
  `reference/ui-components.md`). Don't reproduce that gap here.
- The generated block must cover **every locale the plugin ships**, not just the one the operator
  mentioned first. If the plugin ships `en` and `fr`, the README shows both sub-objects, even though a
  host page that only wants French only needs to pass that one. Completeness in the docs, not
  minimalism, is the point: an integrator adding a second locale later should be able to copy the
  block wholesale.

Exit check:

```bash
test -d translations && {
  grep -q "UI_TRANSLATIONS:START" README.md
  npm run i18n:snippet -- --check   # must exit 0
}
```

## 5. Demo page: pinned CDN tag, SRI, same enforcing CSP as e2e

`demo/index.html` is a real, runnable page, not a code snippet pasted into a markdown fence. It loads
two things: the pinned Kaltura player build, and the plugin's own bundle (local file during
development, the plugin's own pinned CDN tag once a release exists).

- **Pin an exact version, never `@latest`.** Resolve the exact `@playkit-js/kaltura-player-js` version
  the plugin was built and tested against with `npm view @playkit-js/kaltura-player-js version` (don't
  guess or recall a version number), and write that exact string into the `<script>` tag's URL. The
  same rule applies to the plugin's own bundle once it's released: link
  `cdn.jsdelivr.net/gh/<org>/<repo>@vX.Y.Z/dist/<file>.js` (community mode, research §9) at the tag just
  cut, never a floating `@latest` pointer that jsDelivr re-caches every 7 days (research §13).
- **Add an SRI `integrity` attribute to every pinned `<script>` tag.** jsDelivr computes and publishes
  an SRI hash for any exact, static version URL (never for `@latest`, the hash would go stale the
  moment the pointer moves, research §13). Get the hash from jsDelivr's own site for that exact URL, or
  compute it yourself once the file is fetched: `openssl dgst -sha384 -binary <file> | openssl base64
  -A`, then `integrity="sha384-<that output>"`. Verify the exact dist file path/name for the pinned
  package by checking the package's published contents (`npm view <package> files`, or the tarball
  listing) rather than assuming a filename from memory. Package layouts change between majors.
- **Same enforcing CSP as the e2e page.** `demo/index.html` sets
  `Content-Security-Policy: require-trusted-types-for 'script'` via a `<meta http-equiv>` tag (a
  static demo page usually can't set a response header the way the e2e dev server can, use the meta
  tag here specifically for that reason) and the page must actually run cleanly under it: no
  `securitypolicyviolation` on load. This is the same rule `reference/testing-strategy.md` and
  `reference/security-checklist.md` apply to the e2e page; the demo is the one artifact an integrator
  opens by hand, so it has to prove the claim the README makes in real time, not just in CI.
- **Placeholder partner/entry IDs, clearly flagged.** Default the demo to the mock provider
  (`partnerId: -1`, mock `cdnUrl`/`serviceUrl`, a local `media/video.mp4`, the same shape
  `reference/testing-strategy.md` uses for e2e) so the demo runs with zero Kaltura network dependency
  out of the box. If the operator supplied a real partner/entry ID for the demo specifically, use it,
  but mark it with an inline HTML comment (`<!-- OPERATOR-SUPPLIED: replace before using with a
  different account -->`) so a later reader doesn't mistake it for a stable public sandbox account.
- **Every documented script and option must exist.** Before writing a line into the README or guide
  that names an npm script (`npm run lint:check`, `npm run dev`, whatever), grep `package.json`'s
  `scripts` block to confirm it's actually there. The official template's README documents `npm run
  dev`, `lint:check`, `prettier:fix`, `types:check`, and a Mocha/Karma setup, **none of which exist in
  its own `package.json`** (research §8). That drift is the single clearest example of why this file
  exists; don't let a generated plugin repeat it.

Exit check:

```bash
test -f demo/index.html
# Matches a real floating CDN URL, not prose warning against one (README/docs/guide.md are expected
# to say "never @latest" in words -- that's not the thing this check is guarding against).
grep -En "(cdn\.jsdelivr\.net|unpkg\.com)/[^\"'[:space:]]*@latest" demo/index.html README.md docs/guide.md
# ^ must print nothing
grep -n "integrity=" demo/index.html                        # must hit once per pinned <script>
grep -n "require-trusted-types-for" demo/index.html          # must hit
# every npm script named in README.md/docs/guide.md exists in package.json:
grep -oE 'npm run [a-zA-Z0-9:_-]+' README.md docs/guide.md | sed 's/.*npm run //' | sort -u | \
  while read -r s; do grep -q "\"$s\":" package.json || echo "MISSING SCRIPT: $s"; done
# ^ must print nothing
```

## 6. SaaS whitelisting constraint

State this fact plainly in the README; it is not optional and not a "maybe" (plan §4 row 4, research
§13's market finding: "SaaS players run only plugins Kaltura whitelists in the bundler; no
self-service registry"):

> On Kaltura SaaS, this plugin runs only after Kaltura has whitelisted it in the partner's player
> bundler configuration. Self-hosted players and custom embeds that load the player and this plugin's
> script directly do not have that restriction.

Never write or imply that an integrator can self-service-deploy this plugin onto a SaaS account by
installing it themselves; that capability does not exist. If the operator's target is specifically
SaaS, this line is the single most important sentence in the README, because it sets the right
expectation before the integrator spends time wiring config that never gets a chance to run.

Exit check: `grep -in "whitelist" README.md` hits, and the surrounding sentence names both the SaaS
constraint and the self-hosted exception (a bare "whitelist" hit with no context doesn't satisfy the
phase-4 exit condition).

## 7. Mode differences: GitHub Pages

Plan §2's mode table lists "GitHub Pages" for both community and internal mode's docs/demo row, and
research §9 confirms the community pattern in detail (`aws-analytics`'s `ci.yaml` gates a Pages deploy
on push to `main`, via `configure-pages`/`upload-pages-artifact`/`deploy-pages` with `contents: read`,
`pages: write`, `id-token: write`). Community mode always wires this: `docs/` is the Pages source, the
deploy job runs on every push to `main`.

Internal-mode repos live under the `kaltura/*` org and are typically private. A private repo's GitHub
Pages site is not publicly reachable unless the org's GitHub plan and settings specifically enable
Pages for private repos. That's an org-level setting this skill can't see or set from inside a single
plugin repo. Don't assume either way:

- If the operator confirms the target repo will be public, or confirms the org has private-repo Pages
  enabled, wire the same Pages deploy job as community mode.
- Otherwise, `docs/` and `demo/index.html` still exist and are complete in the repo (every requirement
  in §2-§6 still applies in full); they're read directly from git rather than served from a public URL.
  Record which case applies in `PLAN.md` rather than guessing.

This is the one place internal mode might not match the plan table's "GitHub Pages" cell exactly; say
so in `PLAN.md` instead of silently wiring a Pages deploy that will 404 for every reader, or silently
skipping one the operator actually wanted.

## 8. Unisphere consumer branch: README requirements

If this plugin is a Unisphere consumer (`reference/unisphere-integration.md`), the README states, in
addition to everything in §2 above, the four requirements from that file's "Docs and demo" section
verbatim:

1. Requires `@playkit-js/unisphere-service` loaded first (the consumer plugin does nothing without it).
2. Requires a reachable Unisphere workspace: automatic on Kaltura SaaS, or `provider.unisphereLoaderUrl`
   set explicitly for a self-hosted player.
3. Requires the target runtime to be enabled for the partner (entitlement/activation is not visible
   from source, the README says "ask Kaltura", not "this works everywhere").
4. States which `ks` privileges the runtime needs.

Also state the AGPL-3.0 license of `@unisphere/*` and `@playkit-js/unisphere-*` next to the plugin's
own license choice, and confirm the two are compatible before publishing.

The demo page for this branch loads both plugin bundles (the service plugin and this consumer plugin)
and reads the loader URL from a clearly flagged placeholder, never a hardcoded Kaltura environment
URL in a tracked file (research §14, §16.8; `reference/security-checklist.md` §3 and §6 cover why).

This section is a pointer, not a duplicate: the full recipe, including the exact layout object shape
and the event-bridge contract, lives in `reference/unisphere-integration.md`'s "Docs and demo (phase
4)" subsection. Read it there before writing this branch's README section.

## 9. Do not copy from real plugins

Confirmed drift found in shipped repos (research §8, §16.6), not hypothetical:

- The official template's README documents `npm run dev`, `lint:check`, `prettier:fix`, `types:check`,
  and a Mocha/Karma test setup, none of which exist in its own `package.json` (research §8). Never
  copy template README prose wholesale; verify every command against the actual `package.json` you're
  documenting (§5's exit check automates this).
- The template's `demo/index.html:20-27` hand-declares the `ui.translations` keys instead of
  generating them from `translations/`, so the two are free to drift the moment a key is added or
  renamed (research §6.3). This is exactly the gap §4 above closes with `npm run i18n:snippet`.
- The official template's `cypress/public/index.html` loads the player via jsDelivr `@latest`
  (research §8). Never do this in a committed demo page, with or without SRI: with SRI it breaks the
  next time `@latest` moves; without SRI it's an unpinned dependency that can change the demo's
  behavior with no diff to review.

## 10. Known gaps

- **Exact CDN dist filename for `@playkit-js/kaltura-player-js`** is not asserted anywhere in
  `docs/plans/2026-09-09-plugin-skill-research.md`. Verify it per-build with `npm view
  @playkit-js/kaltura-player-js files` (or inspect the published tarball) rather than assuming a path;
  package layouts change between majors.
- **Whether a Kaltura SaaS player config accepts a per-locale `ui.translations` block set from the
  partner side**, as opposed to only from the plugin's own bundler-time config, is unverified
  (research §14). Say so in the guide if the operator is targeting SaaS with more than one locale;
  don't promise SaaS multi-language support without that caveat.
- **Internal-mode GitHub Pages reachability** depends on org-level private-repo Pages settings this
  skill cannot see (§7 above). Ask, don't assume.
- **jsDelivr SRI hash generation** for a package's dist file assumes the file is reachable at a stable
  path once tagged; this has not been re-verified against jsDelivr's current tooling as of this
  research pass (research §13 notes "npm provenance / Trusted Publishing current state" as separately
  unverified, and the SRI-hash-lookup UI is not itself cited in research). If jsDelivr's site doesn't
  show a hash for a given URL, compute it locally rather than skipping SRI.

## Exit checks (phase 4, plan §4 row 4)

Run all of these; phase 4 is done only when every one passes:

```bash
# 1. The three required artifacts exist
test -f README.md && test -f docs/guide.md && test -f demo/index.html

# 2. SaaS whitelisting constraint is stated
grep -in "whitelist" README.md

# 3. Config table is present and matches the TS interface (script diff, not eyeballed)
grep -q "CONFIG_TABLE:START" README.md
npm run docs:config-table -- --check

# 4. UI text implies a generated ui.translations block, diffed in CI (skip if no translations/ dir)
test -d translations && grep -q "UI_TRANSLATIONS:START" README.md && npm run i18n:snippet -- --check

# 5. Demo page: no floating CDN @latest URL, SRI present, enforcing CSP present
# (matches a real CDN URL, not prose warning against @latest -- README/docs/guide.md are
# expected to say "never @latest" in words, which isn't the thing this check guards against)
grep -En "(cdn\.jsdelivr\.net|unpkg\.com)/[^\"'[:space:]]*@latest" demo/index.html README.md docs/guide.md
grep -n "integrity=" demo/index.html
grep -n "require-trusted-types-for" demo/index.html

# 6. Trusted Types statement in the README names both upstream exceptions
grep -in "iframe" README.md
grep -in "prebid" README.md

# 7. Every documented npm script actually exists in package.json (see §5's fuller check)
grep -oE 'npm run [a-zA-Z0-9:_-]+' README.md docs/guide.md | sed 's/.*npm run //' | sort -u | \
  while read -r s; do grep -q "\"$s\":" package.json || echo "MISSING SCRIPT: $s"; done

# 8. Unisphere branch only: the four requirements and the license note are present
grep -in "unisphereLoaderUrl" README.md
grep -in "AGPL" README.md
```

If `authoring-kaltura-docs` was used, its own output still has to satisfy every check above; the skill
handles voice and structure, not the generation-from-source and CI-diff discipline this file owns.
