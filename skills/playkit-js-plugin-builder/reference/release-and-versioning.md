# Release and versioning

This file covers phase 7 (CI/CD and release) of the workflow in `docs/plans/2026-09-09-plugin-skill-plan.md`
§4: cutting the first tagged release and wiring the distribution path a consumer will actually use.
It applies after `reference/ci-cd-modes.md` has the CI workflow green. Read this file on its own; it
does not assume you have read the others.

Every fact below traces to `docs/plans/2026-09-09-plugin-skill-research.md` (research), cited inline
by section number. Where research flags a fact as unverified, this file repeats that flag instead of
asserting a current state.

## Versioning: SemVer, Conventional Commits, Keep a Changelog

Both modes use the same three conventions (research §8, §9, §13):

- **SemVer 2.0.0** for the version number. Breaking change bumps major, new backward-compatible
  feature bumps minor, fix bumps patch.
- **Conventional Commits 1.0.0** for commit messages: `feat:`, `fix:`, `feat!:`/`BREAKING CHANGE:`
  footer, `chore:`, `docs:`, `test:`, `refactor:`. The commit type drives the version bump.
- **`standard-version`** computes the bump from the commit log, writes `CHANGELOG.md` in
  **Keep a Changelog 1.1.0** format, and tags the release. This matches the official template
  (research §8) and the community reference plugin (research §9). Don't hand-write version numbers
  or changelog entries; let `standard-version` derive them from commits.
- Tag format is **`vX.Y.Z`** (a literal `v` prefix, e.g. `v1.2.0`). Both `dist/` distribution paths
  below depend on this exact tag shape.

Check before tagging: `git log --oneline <last-tag>..HEAD` should show only Conventional Commits
messages. A commit that doesn't follow the convention still gets bumped as a patch by default in
`standard-version`, which under-reports the actual change; fix the commit message convention going
forward rather than trying to fix history.

## `dist/` policy: gitignored, committed only at release

`dist/` stays in `.gitignore` for normal development (research §8, §9: both the template and the
community reference gitignore it). It gets force-added into exactly one commit, the release commit,
so that a git tag on GitHub always resolves to a working build without asking every consumer to run
a build step. This is the mechanism the jsDelivr `/gh/` path in the next section depends on.

Do not commit `dist/` on every commit, and do not leave it permanently committed on `main`; either
defeats the point of gitignoring it and bloats the repo history.

## Community mode: `scripts/release.sh`

Community mode ships a `scripts/release.sh` matching the pattern in research §9
(`playkit-js-aws-analytics` `4e226ff`). Unlike that plugin's runtime code (research §9 flags its
`destroy()` calling `eventManager.destroy()` directly instead of `super.destroy()`, a pattern
`reference/base-plugin-api.md` says not to copy), the release script itself has no such issue and is
copied as-is:

1. **Clean-tree check.** Abort if `git status --porcelain` is non-empty. A release must not carry
   uncommitted changes.
2. **Bump without committing or tagging yet.** `npx standard-version --skip.commit --skip.tag`. This
   updates `package.json`'s `version` and prepends the new `CHANGELOG.md` section, but leaves both
   as uncommitted working-tree changes so the script controls the commit contents.
3. **Build.** Run the project's build (`npm run build`) so `dist/` reflects the bumped version
   (webpack's `DefinePlugin` `__VERSION__`, research §9, needs the bumped `package.json` to be in
   place first).
4. **Force-add the release artifacts.** `git add -f dist package.json package-lock.json CHANGELOG.md`.
   The `-f` is required because `dist/` is gitignored; this is the one commit where that's intentional.
5. **Commit and tag.** Commit message `chore(release): vX.Y.Z`, then `git tag vX.Y.Z`.
6. **Push both.** `git push && git push --tags`. Nothing downstream (jsDelivr, GitHub Pages, an npm
   publish workflow) sees the release until the tag is on the remote.

Write this script to disk in phase 1 (scaffold) alongside the rest of `templates/`; don't defer it to
phase 7. There's nothing mode-specific to decide at release time if the script already exists.

## Distribution: jsDelivr exact tag + SRI vs npm dist-tag

Community mode defaults to **jsDelivr, not npm**, because it needs no publish step and no npm
account: research §13 and §9 confirm the community reference plugin ships this way and it's the
lower-friction default for an operator with only a GitHub repo.

- **Exact-tag URL:** `https://cdn.jsdelivr.net/gh/<org>/<repo>@vX.Y.Z/dist/<file>.js`. Static tags
  cache indefinitely on jsDelivr's CDN (research §13). This is the only form the README and demo
  should ever use.
- **Never `@latest` with SRI**, and don't recommend `@latest` at all in docs. `@latest` caches for
  7 days and that cache is not purgeable without jsDelivr access (research §9, §13). A consumer who
  pins `@latest` can be served a stale build for up to a week after a fix ships, and an SRI hash
  computed against one build will start failing integrity checks the moment jsDelivr rotates what
  `@latest` points to. Every README/demo snippet must show the exact tag, and every `<script
  integrity="sha384-...">` must be computed against that same exact tag's file.
- **Size limits:** jsDelivr caps at 20 MB per file and 150 MB per repo (research §13). Flag this in
  docs only if the plugin bundles large assets; most plugin bundles are far under this.
- **If the plugin also publishes to npm**, prefer the `/npm/` jsDelivr path over `/gh/`
  (`https://cdn.jsdelivr.net/npm/<package>@X.Y.Z/dist/<file>.js`, no `v` prefix, npm's own semver).
  This is jsDelivr's own recommendation (research §13): the `/npm/` mirror is fed from the npm
  registry's tarball, which is the artifact that actually shipped, rather than raw GitHub tree
  contents. Only recommend `/npm/` once npm publish (below) is actually wired up; until then `/gh/`
  is correct and sufficient.

Generate the SRI hash from the exact release artifact, not by hand:

```bash
curl -fsSL "https://cdn.jsdelivr.net/gh/<org>/<repo>@vX.Y.Z/dist/<file>.js" | openssl dgst -sha384 -binary | openssl base64 -A
```

## Optional npm publish

npm publish is opt-in in community mode, only when the operator has an npm account and wants it
(plan §2, §6.2). Two ways to authenticate a publish from CI:

1. **Long-lived automation token in a repo secret.** Works everywhere but is a standing credential
   that must be rotated and can leak. Don't default to this if the alternative below is viable.
2. **npm Trusted Publishing (OIDC).** npm can accept a publish authenticated by a GitHub Actions
   OIDC token instead of a stored secret, tied to a specific repo and workflow file, with provenance
   attached to the published package. Prefer this over a long-lived token when the operator's npm
   account and npm CLI version support it.

**Flag, don't assert:** research §13 and §14 explicitly mark npm Trusted Publishing's *current
production state* as not re-verified in this audit ("npm provenance / Trusted Publishing current
state" listed as not verified, §13; "npm Trusted Publishing (OIDC) current state not re-verified
(§13). Check before recommending it in `release-and-versioning.md`" §14). Do not tell an operator
Trusted Publishing is available, stable, or works a specific way from this document alone. Before
wiring it into a real workflow: check the current npm CLI docs and GitHub's OIDC-for-npm guide for
the exact `id-token: write` permission, the `npm publish` flag or config needed, and any npm-side
one-time setup (linking the package to the repo/workflow on npmjs.com). If that check can't happen
in the session, use the long-lived-token path and say plainly that Trusted Publishing was not
verified this session, rather than guessing at a YAML shape.

Either way: never commit an npm token into a tracked file. It belongs in a GitHub Actions repo
secret (`reference/security-checklist.md` covers secrets handling in more depth).

## Internal mode: `run_prod.yaml`

Internal mode (Kaltura-employee, opt-in per `scripts/detect-mode.sh`) does not use `scripts/release.sh`
or jsDelivr. Kaltura's reusable workflow `run_prod.yaml` (dispatch-triggered, calling
`player_cicd.yaml@master`, research §8) handles both the npm publish to Kaltura's internal registry
and the CDN deploy, using the eight `PLAYER_*` repo secrets already covered in `reference/ci-cd-modes.md`.
Don't write a competing `scripts/release.sh` for internal mode; trigger the existing dispatch workflow
instead. This file's job in internal mode is limited to the version/changelog/tag conventions above,
which are mode-independent.

## Release PR checklist

Before cutting a tag, the release PR (or the commit right before tagging) should have:

- [ ] `CHANGELOG.md` has a new section for the version, generated by `standard-version` (not
  hand-written).
- [ ] Every version reference in `README.md` (badge, install snippet, CDN URL) points at the new
  tag, not the previous one.
- [ ] The demo page's script tag and any SRI hash point at the new tag.
- [ ] `package.json` `version` matches the tag with no `v` prefix (`1.2.0` in the file, `v1.2.0` as
  the tag).
- [ ] Working tree is clean before running `scripts/release.sh` (the script's own check enforces
  this, but verify before running it, not after it fails).

## Do not copy

- Don't SRI-pin a CDN URL that uses `@latest`. Integrity hashes and floating tags are incompatible
  (research §9, §13): the hash is only valid for one specific file.
- Don't copy `playkit-js-aws-analytics`'s GitHub Actions as SHA-pinned; research §9 notes its actions
  are **tag-pinned, not SHA-pinned** (`actions/checkout@v7` style). `reference/ci-cd-modes.md`
  requires full-commit-SHA pinning for the community scaffold; the release/publish workflow is no
  exception.
- Don't leave `dist/` permanently committed, and don't commit it outside the release commit.
- Don't assert Trusted Publishing "just works" or describe its exact current setup steps from
  memory; see the flag above.

## Known gaps (say so, do not guess)

- npm Trusted Publishing (OIDC) current production state: not re-verified in this audit (research
  §13, §14). Verify against live npm/GitHub docs before wiring it into a real workflow.
- A canonical, current best-practice guide for npm provenance beyond Trusted Publishing was not
  found in the market review (research §13, "not verified in that report").
- Whether Kaltura SaaS player configs accept a partner-supplied `ui.translations` override, versus
  only what the plugin bundle ships, is unverified (research §14) and can affect what a release note
  should promise about locale support; check `reference/ui-components.md` before writing that claim
  into a changelog entry.

## Exit checks (phase 7)

Run these after `scripts/release.sh` (community) or after the internal dispatch workflow completes,
to confirm the release is real and not just "the script exited 0":

```bash
# Working tree clean and the new tag exists
git status --porcelain            # expect empty
git tag --list 'v*' | tail -1     # expect the new version

# package.json version matches the tag (strip the leading v)
node -p "require('./package.json').version"

# dist/ is actually inside the tagged commit (community mode)
git ls-tree -r --name-only "$(git tag --list 'v*' | tail -1)" | grep '^dist/'

# CHANGELOG.md has a heading for the new version
grep -n "^## \[\?$(node -p "require('./package.json').version")" CHANGELOG.md

# jsDelivr resolves the exact tag (network required; best-effort, jsDelivr can lag briefly
# right after a push)
curl -fsSL -o /dev/null -w '%{http_code}\n' \
  "https://cdn.jsdelivr.net/gh/<org>/<repo>@$(git tag --list 'v*' | tail -1)/dist/<file>.js"
```

Community mode passes phase 7 when the tag exists, `dist/` is inside it, and the jsDelivr URL
returns `200`. Internal mode passes when the canary/production dispatch workflow run is green;
there is no jsDelivr check to run.
