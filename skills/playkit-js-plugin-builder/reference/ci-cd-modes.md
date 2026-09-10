# CI/CD modes

Every generated plugin ships working CI on day one, in the mode that matches the operator's access
(research §8, §9, §11, §13; plan §2, §4 phase 7). This file is self-contained: it covers mode
detection, full workflow skeletons for both modes, the Dependabot config, the npm-12 browser-install
step, the vulnerability gate, and the phase-7 exit checks. It does not cover semver, changelog, or the
tag/release script; that's `reference/release-and-versioning.md`. It does not cover the security
checklist's own exit checks (package-name grep, secrets scan, Trusted Types sink list); that's
`reference/security-checklist.md`. Read those two alongside this one before wiring phase 5 and 7.

## Mode detection

`scripts/detect-mode.sh` prints exactly one of `community`, `internal`, or `ambiguous`. This file's
mode split must match that script exactly; if you change one, change the other.

- **`internal`**: both signals succeed. `npm view @kaltura/kaltura-tools version` resolves against
  the operator's npm auth, **and** `gh auth status` succeeds with a non-empty
  `gh api orgs/kaltura/repos` response (visibility into the org, not just a login).
- **`community`**: both signals fail. This is the default assumption whenever the script hasn't run
  yet, or can't run (no `npm`/`gh` on the machine).
- **`ambiguous`**: the two signals disagree. Ask the operator once, batched with any other open
  question from `reference/decision-tree.md` (plan §5). Don't guess.

Run it once during Intake (phase 0) and record the result in `PLAN.md`. Everything below is keyed off
that result.

## Community mode (default)

Plain GitHub Actions, no Kaltura-internal access, no secrets. Two files: `.github/workflows/ci.yml`
and `.github/dependabot.yml`. (`.yml`, not `.yaml`: GitHub Actions accepts either extension, but
`.yml` is this skill's convention for a generated community-mode workflow file, matching what every
dry-run generation of this skill has actually produced. `aws-analytics`'s own file is named `ci.yaml`
elsewhere in this doc and in the research doc — that's a citation of a real upstream repo's filename,
not this skill's own naming choice.)

### `ci.yml` skeleton

Jobs, in order: install/build/type-check/lint, unit test, vulnerability scan, e2e, and a Pages deploy
gated to `push` on `main`. This corrects the two gaps research §9 found in `playkit-js-aws-analytics`'s
own `ci.yaml` (the only public example): its actions are pinned to a tag (`@v7`), not a SHA, and it has
no OSV scan. Both are fixed below.

Resolve each SHA once per action, don't fabricate one: `gh api repos/<owner>/<repo>/commits/<tag>
--jq .sha`. Re-resolve when Dependabot opens a bump PR for that action.

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions: {}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@<sha>          # v5.x.x
      - uses: actions/setup-node@<sha>        # v5.x.x
        with:
          node-version-file: .nvmrc
          cache: npm
      - run: npm ci
      - run: npm run build
      - run: npm run type-check
      - run: npm run lint
      - run: npm test

  e2e:
    needs: build
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@<sha>
      - uses: actions/setup-node@<sha>
        with:
          node-version-file: .nvmrc
          cache: npm
      - run: npm ci
      - run: npm run build
      # npm 12 default-denies install scripts (research §13): the Playwright postinstall
      # browser download no-ops silently under npm ci. Install browsers explicitly.
      - run: npx playwright install --with-deps
      - run: npm run test:e2e

  audit:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@<sha>
      - uses: actions/setup-node@<sha>
        with:
          node-version-file: .nvmrc
          cache: npm
      - run: npm ci
      - run: npm audit --omit=dev --audit-level=high
      - uses: google/osv-scanner-action/osv-scanner-action@<sha>   # vX.Y.Z
        with:
          scan-args: |-
            --lockfile=./package-lock.json

  pages:
    needs: [build, e2e, audit]
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pages: write
      id-token: write
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@<sha>
      - uses: actions/configure-pages@<sha>   # v5.x.x
      - uses: actions/upload-pages-artifact@<sha>   # v3.x.x
        with:
          path: docs
      - id: deployment
        uses: actions/deploy-pages@<sha>   # v4.x.x
```

Rules this skeleton encodes, all from research §11/§13 (market report C6/C7):

- **`permissions: {}`** at the workflow level denies everything by default; each job grants only what
  it needs. Only the `pages` job gets `pages: write` and `id-token: write` (OIDC, no long-lived Pages
  token). `audit` and `build`/`e2e` need only `contents: read`.
- **Every `uses:` line is a full commit SHA**, with the released version as a trailing comment. A tag
  or branch ref can be repointed by the action's maintainer or by an attacker who compromises their
  account; a SHA can't. `security-checklist.md`'s exit check (comparing the total `uses:` count against
  the `@[0-9a-f]{40}`-pinned count) fails the build if any line still has a tag.
- **Node version from `.nvmrc`**, not hardcoded in the workflow, so the plugin's CI and a
  contributor's local `nvm use` never drift.
- **The e2e job installs browsers as its own step**, not a postinstall hook, because npm 12
  (2026-07) default-denies install-time lifecycle scripts (research §13). This applies whichever e2e
  runner the plugin uses; swap `npx playwright install --with-deps` for `npx cypress install` only if
  this specific plugin is community-mode-with-Cypress by explicit operator choice (the skill's default
  is Playwright in community mode, `reference/testing-strategy.md`).
- **Do not** fix the npm-12 install-script block by running `npm config set ignore-scripts false` or
  adding `--ignore-scripts=false` globally. That re-enables install scripts for every dependency in the
  tree, including transitive ones, and throws away the exact protection npm 12 shipped. Install only
  the one tool that needs it, as its own explicit step.
- **OSV scan is a second, independent gate from `npm audit`.** `npm audit --audit-level=high` reads
  the npm advisory database; `osv-scanner` reads OSV, which is the database that carries
  `MAL-2025-41390`, the malicious `kaltura-player-js` (bare name) release (research §13). Either gate
  alone would have missed different incidents; run both.
- **Pages deploy is gated to `push` on `main`**, never a PR from a fork, so a PR can't trigger a
  deploy with elevated `pages`/`id-token` permissions.

### `dependabot.yml` skeleton

```yaml
version: 2
updates:
  - package-ecosystem: npm
    directory: /
    schedule:
      interval: weekly
    groups:
      minor-and-patch:
        update-types:
          - minor
          - patch
    # Major bumps land as individual PRs, not grouped, so a breaking change is reviewed on its own.

  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

Both ecosystems, weekly, matches research §9's finding for `aws-analytics` and closes the loop this
skill's own SHA-pinning opens: a pinned action needs *something* to notice when a new release exists.

### Optional hardening for community repos

Two add-ons from market report C6, worth offering (not mandatory to reach phase 7 green):

- **`step-security/harden-runner`** as the first step of every job, monitoring egress and blocking
  unexpected outbound network calls from the runner:

  ```yaml
      - uses: step-security/harden-runner@<sha>   # vX.Y.Z
        with:
          egress-policy: audit
  ```

  Start with `egress-policy: audit` (log, don't block) for a few CI runs before switching to `block`
  with an explicit allow-list, so a legitimate endpoint (npm registry, jsDelivr, the Playwright CDN)
  doesn't get cut off on day one.
- **OpenSSF Scorecard** workflow plus a badge in the README. Scorecard scores things this file already
  does (Pinned-Dependencies, Token-Permissions, Dependency-Update-Tool) alongside things it doesn't
  control (Branch-Protection, Code-Review), so it's a useful outside check, not a duplicate gate.

## Internal mode (opt-in, Kaltura employees only)

Only when `scripts/detect-mode.sh` prints `internal`. Three workflow files, each a thin wrapper calling
a Kaltura-internal reusable workflow. The generated repo never inlines the actual test/build/deploy
logic; that logic lives in the reusable workflow repos (research §8). This skill does not hardcode
those repos' exact org/name or workflow file paths in any tracked file — that's internal-only
infrastructure detail, and this repo is public. The shape (not the exact paths) is:

```yaml
# .github/workflows/run_tests.yaml
name: Run tests
on:
  push:
  pull_request:
jobs:
  cypress:
    uses: <internal-org>/<internal-reusable-workflow-repo>/.github/workflows/<cypress-workflow>@master
    secrets: inherit
  player-tests:
    uses: <internal-org>/<internal-reusable-workflow-repo>/.github/workflows/<player-tests-workflow>@master
    secrets: inherit
```

```yaml
# .github/workflows/run_canary.yaml
name: Canary
on:
  push:
    branches: [main]
jobs:
  canary:
    uses: <internal-org>/<internal-reusable-workflow-repo>/.github/workflows/<canary-workflow>@master
    secrets: inherit
```

```yaml
# .github/workflows/run_prod.yaml
name: Production release
on:
  workflow_dispatch:
jobs:
  prod:
    uses: <internal-org>/<internal-reusable-workflow-repo>/.github/workflows/<prod-deploy-workflow>@master
    secrets: inherit
```

Get the real `<internal-org>/<internal-reusable-workflow-repo>` values and each `<...-workflow>` file
name from your org's existing Kaltura-internal CI setup docs before generating these files; this
skill never sources or writes them itself, and an internal-mode PR should never introduce them into
this (public) skill repo.

Notes specific to this mode:

- These reusable workflows expect the eight `PLAYER_*` repository secrets (research §8) to already be
  configured on the repo. This skill never creates, prints, or writes those secret values, or even
  their exact names, into a tracked file. That's an operator/org-admin setup step outside this
  skill's scope, and this repo is public. Point the operator at their org's existing Kaltura CI setup
  docs instead of inventing the values.
- The scaffold itself comes from cloning `playkit-js-plugin-example` and running its bundled
  `rename-plugin` skill (research §8), not from this skill's own `templates/`. Community-mode's
  SHA-pinning and OSV-scan hardening above do **not** apply here; the reusable workflows and their
  pinning policy belong to the workflow repos, not to this plugin repo.
- Cypress here, not Playwright: the reusable workflow and the cloned template both already assume
  Cypress (`reference/testing-strategy.md` has the full runner split and the reasoning).
- `npm audit`/OSV scanning, Dependabot, and Pages deploy may still be worth adding on top (nothing
  stops an internal-mode repo from also running community-style hardening jobs), but they're additive
  extras here, not the phase-7 gate. The phase-7 gate for internal mode is the canary workflow going
  green (see Exit checks below).

## Unisphere consumer branch: npm resolution, not a registry switch

If this plugin is on the Unisphere consumer branch (`reference/unisphere-integration.md`), its CI
needs no special workflow job, only a correct `.npmrc` (or none at all):

- `@playkit-js/unisphere-service` and every `@unisphere/*` package it depends on resolve from the
  public npm registry, in both modes. No internal registry, no token, is needed to install them.
- The reference Unisphere plugins' own `.npmrc` scopes packages to an internal registry with a
  registry token. That file is internal-only tooling for the Kaltura employees who maintain those
  specific repos. Never copy it into a community (or even internal-mode-but-consumer-only) scaffold.
  If the generated repo has no other reason to talk to an internal registry, it should ship with the
  default public-registry npm config, i.e. no custom `.npmrc` at all.
- The Unisphere e2e job (both modes) reads its loader URL from a CI secret or repository variable
  named in the plugin's own CI docs (call it `UNISPHERE_LOADER_URL` in that plugin's workflow, not in
  this shared reference file), and **skips, not fails**, when it's unset:

  ```yaml
      - name: Unisphere e2e
        if: ${{ env.UNISPHERE_LOADER_URL != '' }}
        run: npm run test:e2e:unisphere
        env:
          UNISPHERE_LOADER_URL: ${{ secrets.UNISPHERE_LOADER_URL }}
      - name: Unisphere e2e (skipped)
        if: ${{ env.UNISPHERE_LOADER_URL == '' }}
        run: echo "Skipping Unisphere e2e: UNISPHERE_LOADER_URL not set"
  ```

  A production loader URL for self-hosted players isn't publicly documented (research §14), so most
  CI runs will legitimately hit the skip path. That's expected, not a failure to chase down.

## Do not copy

Real repos research looked at each have at least one CI anti-pattern. Don't reproduce these:

- `aws-analytics`'s `ci.yaml` actions are pinned to a tag (`actions/checkout@v7`), not a SHA. It works
  until the tag moves. SHA-pin from the start.
- `aws-analytics`'s `ci.yaml` has no OSV or malicious-package scan, only `npm audit`. That's exactly
  the gap `MAL-2025-41390` (the `kaltura-player-js` typosquat) would slip through if it were a
  transitive dependency instead of a direct one.
- The template's (`playkit-js-plugin-example`) `preinstall` gate (`npx --registry=https://npm.pkg.
  github.com --package @kaltura/kaltura-tools@latest kaltura-tools check --root=.`) fails hard for
  anyone without a Kaltura org token. That gate belongs to internal mode's cloned scaffold only.
  Never add an internal-registry `preinstall` check to a community scaffold; it would break `npm ci`
  for every community operator.
- The template's README documents `npm run dev`, `lint:check`, `prettier:fix`, `types:check`, none of
  which exist in its own `package.json` (research §8). Don't let a generated README describe a script
  the generated `package.json` doesn't have; generate the scripts table from `package.json` itself.

## Known gaps (say so in `PLAN.md`, do not guess)

- npm provenance / Trusted Publishing's current state was not re-verified for this skill (research
  §13). Don't add it to the publish job without checking first; `reference/release-and-versioning.md`
  owns that decision.
- Cypress WebKit support is still experimental as of the research date (research §13); that's why
  community mode defaults to Playwright. If an operator insists on Cypress in community mode, record
  it in `PLAN.md` as a deliberate deviation from the default; don't silently swap runners.
- The eight internal `PLAYER_*` secrets' exact names and values are an operator/org-admin concern, not
  something this skill sources or verifies. If `run_tests.yaml` fails because a secret is missing,
  that's a signal to check with the repo's org admin, not to guess a value.

## Exit checks (phase 7, plan §4)

Run these before calling phase 7 done. All must pass; none is a self-rating.

```bash
# Mode detection matches what CI was actually wired for
scripts/detect-mode.sh   # community | internal | ambiguous, must match the workflow files present

# Community mode: right files exist, right runner, right hardening
test -f .github/workflows/ci.yml
test -f .github/dependabot.yml
grep -n "permissions: {}" .github/workflows/ci.yml
grep -c "uses: .*@[0-9a-f]\{40\}" .github/workflows/ci.yml   # every action line SHA-pinned
grep -n "osv-scanner" .github/workflows/ci.yml
grep -n "playwright install\|cypress install" .github/workflows/ci.yml

# Internal mode: the three wrapper workflows exist and call the expected reusable workflows
test -f .github/workflows/run_tests.yaml
test -f .github/workflows/run_canary.yaml
test -f .github/workflows/run_prod.yaml
grep -n "^\s*uses: " .github/workflows/run_*.yaml   # each wrapper calls a real internal reusable workflow

# Workflow actually ran and passed on a push (read back via gh, not assumed)
gh run list --branch main --limit 1
gh run view --job <job-id>   # or: gh run watch, on the run just triggered by the push

# First tag cut and, in community mode, dist/ resolvable from jsDelivr
git tag --list 'v*' | tail -1
git show <tag>:dist/<bundle-file>.js >/dev/null   # dist/ was committed at the tag
curl -fsSL "https://cdn.jsdelivr.net/gh/<org>/<repo>@<tag>/dist/<bundle-file>.js" >/dev/null

# Internal mode: canary workflow's most recent run on main is green
gh run list --workflow=run_canary.yaml --branch main --limit 1
```

Community mode is done when the CI workflow above is green on a real push, the tag exists, and the
jsDelivr URL for that tag resolves (a 404 here means `dist/` wasn't force-added at release time; see
`reference/release-and-versioning.md`). Internal mode is done when the canary workflow's latest run on
`main` is green.
