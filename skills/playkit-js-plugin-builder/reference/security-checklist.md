# Security checklist

No Kaltura plugin-security doc exists (research §14). Everything below is synthesized from OWASP
guidance, npm/GitHub Actions supply-chain best practice, the Trusted Types sinks actually grepped from
the player stack at pinned SHAs (research §6.6), and the CSP nonce contract documented for Unisphere
(research §16.8). Where a claim traces to a source, it says so inline. This is the fallback checklist for plan §4 phase 5 ("Secure") and applies
to both community and internal mode unless a bullet says otherwise.

Run this after the plugin builds and its tests pass, before the first tagged release. Every bullet
below has a command or grep next to it: run it, don't eyeball it.

## 1. Run `security-review` first, this checklist is the fallback

- Check whether the `security-review` skill is installed. If it is, run it against the plugin's diff
  and close every finding before continuing.
- If it is not installed, work through every section below and tick each one. Don't skip a section
  because it feels redundant with something the linter already does; the exit checks at the end are
  what plan §4 phase 5 actually gates on.
- Either path ends the same way: no open findings, and the exit checks in §8 below all pass.

## 2. Supply chain

**Dependency name.** The unscoped npm package `kaltura-player-js` has a known-malicious published
version (OSV `MAL-2025-41390`, versions `>=1.0.1`, research §13). The only correct dependency is the
scoped package `@playkit-js/kaltura-player-js`. Never depend on, import, or document the bare name.

- Lint hard-fail: `grep -n '"kaltura-player-js"' package.json` must find nothing outside a line that
  reads `"@playkit-js/kaltura-player-js"`. Wire this as a CI step, not just a one-time check, since a
  future contributor could reintroduce it in a new dependency or an example snippet.
- Same check on imports: `grep -rn "from ['\"]kaltura-player-js['\"]" src/ demo/` must return nothing.
  The only valid import path starts with `@playkit-js/kaltura-player-js`.

**Lockfile and install.** Use `npm ci`, never `npm install`, in CI and in any documented setup step.
`npm ci` fails on a lockfile/manifest mismatch instead of silently rewriting it, and (npm 12, 2026-07,
research §13) install scripts, git dependencies, and URL dependencies are default-denied, so a
compromised transitive dependency can't run arbitrary code at install time without an explicit
opt-in. The plugin's own `package.json` must not define a `postinstall`, `preinstall`, or `install`
script; if a build step is needed, put it in `prepare` and document it, or run it explicitly in CI.

**Vulnerability scanning, both required in CI:**
- `npm audit --audit-level=high` (research §13). Fails the build on any high or critical advisory.
- `osv-scanner` (the `google/osv-scanner-action`, research §13), which also catches OSV-only entries
  like the malicious `kaltura-player-js` release that npm audit alone won't flag.
- Dependabot enabled for both `npm` and `github-actions` update ecosystems, so both application
  dependencies and workflow actions get automated update PRs.

**GitHub Actions hardening** (research §13, step-security / OpenSSF guidance):
- Every action reference is pinned to a full commit SHA, not a tag or branch (`uses:
  actions/checkout@<40-char-sha>`, with the version as a trailing comment). A tag can be moved by the
  action's maintainer or an attacker who compromises their account; a SHA can't.
- Workflow-level `permissions: {}` (deny everything by default), then grant only what each job needs
  at the job level, e.g. `contents: read` for a test job, `contents: write` and `id-token: write` only
  on the release job that needs to push a tag or use OIDC.
- Exit check: every `uses:` line must resolve a full 40-char SHA, not a tag. Count them and compare
  against the total `uses:` count — they must match:
  `grep -c "uses: " .github/workflows/*.yml` vs. `grep -c "uses: .*@[0-9a-f]\{40\}" .github/workflows/*.yml`.
  (Don't grep for `@[a-z]` to find tag refs: a real SHA's first hex digit can itself be `a`-`f`, so
  that pattern matches SHA-pinned lines too and can't tell them apart from `@v7`/`@master`.) Also
  check `grep -L "permissions:" .github/workflows/*.yml` is empty (every workflow file declares its
  own permissions block).

## 3. Trusted Types and Content Security Policy

**The lint list.** ESLint must ban these sinks in the plugin's own `src/`: `innerHTML`, `outerHTML`,
`insertAdjacentHTML`, `document.write`, `eval`, `new Function`, and `script.src` / `script.text`
(the plan's phase-5 gate, and the exact set that `require-trusted-types-for 'script'` blocks per
research §6.6). Add `srcdoc` too; it's the same class of string-to-markup sink on an iframe.

Why this list and not a general "avoid XSS" rule: these are the specific DOM APIs a browser blocks
under an enforcing Trusted Types CSP, so failing on them now means the plugin still works when a host
page turns that policy on later. Preact (the player's UI runtime) renders through its own virtual DOM
and standard DOM property/attribute APIs, not through these sinks, so a plugin's UI components need no
Trusted Types policy of their own as long as they stick to Preact's normal component patterns.

**Never create a `default` Trusted Types policy inside a plugin.** Whether to enforce Trusted Types,
and what policy to register, is the host page's decision. A plugin that creates its own `default`
policy can silently override or conflict with the host's policy.

**What's already clean in the player stack, and what isn't** (research §6.6, grepped at pinned SHAs
2026-09-09): `playkit-js-ui` and `kaltura-player-js` have no Trusted Types sink hits in their own
`src/`. `playkit-js` has two: `player.ts:2116` (`title.innerHTML = metadata.name`) runs only when the
player is embedded inside an iframe, and `utils/jsonp.ts` / `utils/util.ts` assign `script.src`, but
only through `loadScriptAsync`, whose one caller is the prebid ad manager. So a top-level (non-iframe)
page with no prebid can run under an enforcing `require-trusted-types-for 'script'` CSP today. Name
both exceptions in the README if the plugin's demo uses an iframe embed or prebid; don't claim
Trusted Types compatibility without that caveat. The video/audio decoding engines (hls.js, dash.js,
Shaka) were not grepped for sinks (research §14); if the plugin's e2e or demo page switches from a
local mp4 to an HLS/DASH source, re-check before claiming compatibility.

**Enforce it in the demo and e2e pages, not just the linter.** Both must set:

```
Content-Security-Policy: require-trusted-types-for 'script'
```

and the test run must fail on any `securitypolicyviolation` event, not just log it. A lint rule alone
only stops new code in this plugin; the live enforcing header is what actually proves the plugin
(plus the player stack it depends on) is compatible with a strict host CSP.

**Unisphere consumer branch is the one exception to "verified".** If this plugin is a Unisphere
consumer (see `reference/unisphere-integration.md`), the host's CSP nonces reach Unisphere visuals
through `window.kalturaGlobalConfig = { stylesNonce, scriptsNonce }`, set before any Kaltura script
runs; document that contract in the README (research §16.8). The Unisphere loader is a dynamic
`import()` of a URL, so the page's `script-src` directive must allow the Kaltura region host serving
it. No Unisphere doc mentions Trusted Types, and whether that dynamic `import()` works under an
enforcing `require-trusted-types-for 'script'` policy is unverified (research §14). Treat the Trusted
Types e2e check on this branch as informational, not a hard gate, and say so in the plugin's docs
instead of claiming compatibility you haven't confirmed. Never hardcode a Kaltura environment URL or a
`ks` in tracked files. `@unisphere/*` and `@playkit-js/unisphere-*` are AGPL-3.0; record that license
implication in the README next to the plugin's own license.

## 4. Config and messaging as untrusted input

Plugin config comes from the host page integrator, not from the plugin author, so treat it exactly
like any other untrusted input (cross-reference `reference/config-and-validation.md` for the schema
and validation layer this sits on top of):

- Never pass a config value or any network response into `innerHTML`, `dangerouslySetInnerHTML`,
  `eval`, or `new Function`. This is the runtime consequence of the lint rule in §3; the rule catches
  the pattern in the plugin's own code, but a reviewer should also check that no config-derived string
  reaches one of these sinks indirectly (e.g. through a template string built at runtime).
- Any URL taken from config (a logo image, a click-through link, a webhook endpoint) goes through an
  explicit scheme allow-list (`https:`, and `http:` only if the plugin documents why) before use.
  Reject `javascript:`, `data:`, and `file:` schemes outright.
- If the plugin uses `postMessage` (to an iframe it embeds, or to the host page), always pass an
  explicit target origin, never `*`, and on the receiving side validate `event.origin` against an
  exact allow-list of expected origins (OWASP HTML5 Security Cheat Sheet). A wildcard origin on either
  side lets any page on the internet send or read that message.

## 5. Third-party SDKs loaded at runtime

If the plugin loads a third-party SDK (an analytics beacon, an ad SDK, a chat widget) as a script tag
or dynamic import rather than as a bundled dependency:

- Pin an exact version in the URL, never a floating tag like `@latest` or a bare major version.
- Add a Subresource Integrity (`integrity`) hash on the `<script>` tag wherever the CDN supports
  computing one for that exact pinned version. jsDelivr guidance (research §13): a static version tag
  caches forever and is safe to pair with SRI; `@latest` cache-busts every 7 days and must never be
  paired with SRI, because the hash would go stale the next time the CDN's `@latest` pointer moves.
- **jsDelivr's own `.min.js` path can be SRI-incompatible for a package that's already published
  minified.** Live-verified during a dry run (2026-09-09), for both `@playkit-js/kaltura-player-js` and
  `@playkit-js/unisphere-service`: fetching a jsDelivr `.min.js` URL for either returned jsDelivr's own
  auto-generated header, "Do NOT use SRI with dynamically generated files!" — because the package's
  published file was already minified, jsDelivr's own minifier no-ops and instead serves a
  dynamically-templated passthrough that isn't a stable, hashable static file. Fix: use the
  **un-minified path from the package's own `main` field** (still exactly version-pinned) instead of
  guessing a `.min.js` path, and compute the SRI hash (`openssl dgst -sha384 -binary <file> | openssl
  base64 -A`) from that exact fetched file. Check the response headers on whatever URL you actually
  ship before trusting an SRI hash computed against a different URL.
- Load it only after the plugin has validated its own config, so a bad config can't trigger a load of
  attacker-influenced content.
- Treat its failure to load as RECOVERABLE: log through the taxonomy in
  `reference/error-event-taxonomy.md` and degrade the plugin's own feature, don't let a blocked or
  failed third-party script take down playback.

## 6. Secrets, privacy, and CDN references in tracked files

- No secrets (API keys, tokens, session identifiers) in bundled JS, demo pages, test fixtures, or CI
  logs. `.env` is gitignored. Run a secrets scan before the first commit and again before the first
  tagged release; a secret that leaks into git history needs rotation even after it's deleted, so
  catching it before the first commit is much cheaper than after.
- Treat the generated repo as eventually public even in internal mode. Don't write Kaltura-internal
  hostnames, region lists, registry tokens, or credential environment-variable names into any tracked
  file, README included.
- Analytics-style plugins (anything that sends data off the page) document in the README exactly what
  fields they send and to what destination. Don't send personally identifiable information by default;
  if a feature requires it, make it an explicit opt-in the integrator turns on in config, and say so in
  the README's privacy section.
- CDN script tags in docs and the demo page use an exact semver tag plus an SRI hash, matching the
  jsDelivr guidance in §5 above. Never `@latest` with SRI on the plugin's own published bundle either.

## 7. Composable-skill fallback, in one place

This whole file is the fallback for the `security-review` skill (research §12). If a future version of
this skill also references other composable skills for narrower checks (a CSP-specific linter, a
secrets-scanning tool), and one of those isn't installed in the target environment, fall back to the
matching section above rather than skipping the check. Don't silently pass phase 5 because a tool was
missing; either run the manual equivalent or state in `PLAN.md` which check was skipped and why.

## 8. Exit checks (plan §4 phase 5)

Run all of these. Phase 5 is done only when every one passes:

```bash
# 1. No bare kaltura-player-js dependency or import
grep -n '"kaltura-player-js"' package.json | grep -v '@playkit-js/kaltura-player-js'
grep -rn "from ['\"]kaltura-player-js['\"]" src/ demo/
# both must print nothing

# 2. Vulnerability scans clean
npm audit --audit-level=high
osv-scanner --lockfile=package-lock.json

# 3. Trusted Types sinks banned in src/
grep -rnE "innerHTML|outerHTML|insertAdjacentHTML|document\.write|\beval\(|new Function|\.src\s*=|srcdoc" src/
# any hit must be a documented, justified exception, not a silent pass

# 4. Actions SHA-pinned, permissions least-privilege
grep -c "uses: " .github/workflows/*.yml                        # total uses: lines
grep -c "uses: .*@[0-9a-f]\{40\}" .github/workflows/*.yml        # SHA-pinned lines -- must match the count above
grep -L "permissions:" .github/workflows/*.yml  # expect empty output

# 5. No secrets in tracked files
git grep -nE "(api[_-]?key|secret|token|password)\s*[:=]" -- . ':!*.md' ':!package-lock.json'
# review every hit by hand; expect none to be a real credential

# 6. CDN tags pinned with SRI
grep -n "cdn\.jsdelivr\|unpkg\.com" README.md demo/*.html
# every match line has an exact version (not @latest) and an integrity= attribute
```

If `security-review` is installed and was run instead, its clean report substitutes for checks 3 and
5 above, but checks 1, 2, 4, and 6 still need to run explicitly since they're specific to this plugin's
supply chain and CI setup, not generic code-level findings.

## Known gaps (say so in `PLAN.md`, do not guess)

- No Kaltura plugin-security document exists to check this list against (research §14); it's built
  from general web-plugin and OWASP practice plus the two things actually grepped from the player
  source (research §6.6, §16.8).
- Trusted Types compatibility for hls.js, dash.js, and Shaka is unverified (research §14, §6.6). Only
  claim it for a plugin whose demo and e2e stay on a local mp4 through the native adapter.
- Trusted Types compatibility for the Unisphere dynamic `import()` loader is unverified (research
  §14). Treat it as informational on that branch, not a hard pass/fail.
- npm provenance / Trusted Publishing's current state was not re-verified for this skill (research
  §13). Don't recommend it in `reference/release-and-versioning.md` without checking first.
