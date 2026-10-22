#!/usr/bin/env bash
# Release voice-core and carry it into every app that depends on it.
#
#   scripts/release.sh 1.1.0
#
# Tests here, then the tag. Then, for each app checked out beside this
# repository whose package depends on voice-core: update the dependency, run
# that app's own checks, and commit and push the new Package.resolved if they
# pass. That is the auto-merge chosen on 2026-10-14: one release, every app
# updated, none of them broken by it. A bump whose checks fail is reverted and
# reported, and that app stays on the version it had.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?version, like 1.1.0}"
HERE="$(pwd)"
ROOT="$(dirname "$HERE")"

swift test
git diff --quiet && git diff --cached --quiet || { echo "error: uncommitted changes in voice-core" >&2; exit 1; }
git tag -a "$VERSION" -m "voice-core $VERSION"
git push -q origin main "$VERSION"
echo "released voice-core $VERSION"

# app folder (relative to ROOT) | package folder within it | its checks
APPS=(
  "interpreter-forge|apple|swift run -q tccheck && swift test"
  "voice-forge|macos|swift run -q vfcheck && ../scripts/check-shared-assets.sh"
  "gateway-forge|.|swift run -q gfcheck"
  "companion-forge|.|swift run -q cccheck"
)
failed=()
for entry in "${APPS[@]}"; do
  IFS='|' read -r app pkg checks <<< "$entry"
  dir="$ROOT/$app/$pkg"
  [ -f "$dir/Package.swift" ] && grep -q "voice-core" "$dir/Package.swift" || continue
  echo "== $app"
  # GitHub Actions bumps apps too (voice-core.yml): start from its latest.
  git -C "$ROOT/$app" pull -q --ff-only || { echo "   could not fast-forward; skipped"; failed+=("$app"); continue; }
  (cd "$dir" && swift package update voice-core >/dev/null)
  resolved=$(cd "$ROOT/$app" && git status --porcelain -- "$pkg/Package.resolved")
  if [ -z "$resolved" ]; then echo "   already on the newest voice-core"; continue; fi
  if (cd "$dir" && eval "$checks") >/tmp/voice-core-$app.log 2>&1; then
    (cd "$ROOT/$app" && git add "$pkg/Package.resolved" \
      && git commit -q -m "voice-core $VERSION" && git push -q origin HEAD)
    echo "   updated to $VERSION, checks passed, pushed"
  else
    (cd "$ROOT/$app" && git checkout -- "$pkg/Package.resolved")
    echo "   checks FAILED on $VERSION; left on its previous version (log: /tmp/voice-core-$app.log)"
    failed+=("$app")
  fi
done
[ ${#failed[@]} -eq 0 ] || { echo "not updated: ${failed[*]}" >&2; exit 1; }
