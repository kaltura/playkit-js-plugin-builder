#!/usr/bin/env bash
# Community-mode release script (reference/release-and-versioning.md, "Community mode:
# scripts/release.sh"). Cuts one tagged release: bump version, build, commit the release
# artifacts, tag, push. Never run this with uncommitted changes in the working tree.
set -euo pipefail

# 1. Clean-tree check. A release must not carry uncommitted changes.
if [ -n "$(git status --porcelain)" ]; then
  echo "release.sh: working tree is not clean. Commit or stash your changes first." >&2
  exit 1
fi

# 2. Bump without committing or tagging yet. Updates package.json's version and prepends the
#    new CHANGELOG.md section, leaving both as uncommitted working-tree changes so this script
#    controls the commit contents.
npx standard-version --skip.commit --skip.tag

# 3. Build. dist/ must reflect the bumped version (webpack's DefinePlugin __VERSION__ reads
#    package.json, which is only correct after step 2 has run).
npm run build

# 4. Force-add the release artifacts. -f is required because dist/ is gitignored; this is the
#    one commit where that is intentional.
git add -f dist package.json package-lock.json CHANGELOG.md

# 5. Commit and tag.
VERSION="$(node -p "require('./package.json').version")"
git commit -m "chore(release): v${VERSION}"
git tag "v${VERSION}"

# 6. Push both. Nothing downstream (jsDelivr, GitHub Pages) sees the release until the tag is
#    on the remote.
if git remote get-url origin >/dev/null 2>&1; then
  git push
  git push --tags
else
  echo "release.sh: no 'origin' remote configured; skipping push. Tag v${VERSION} was created locally." >&2
fi
