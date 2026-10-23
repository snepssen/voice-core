#!/usr/bin/env bash
# Release voice-core and carry it into every app that depends on it.
#
#   scripts/release.sh 1.1.0 [--dry-run]
#
# Tests here, then the tag. Then, for each app checked out beside this
# repository that ecosystem.json says uses voice-core: update the dependency,
# run that app's own checks, and commit and push the new Package.resolved if
# they pass. That is the auto-merge chosen on 2026-10-14: one release, every
# app updated, none of them broken by it. A bump whose checks fail is reverted
# and reported, and that app stays on the version it had. The work is
# site-core's workshop script, which speech-core releases with too.
set -euo pipefail
cd "$(dirname "$0")/.."
WORKSHOP="../site-core/workshop"
[ -x "$WORKSHOP" ] || { echo "error: needs site-core checked out beside voice-core" >&2; exit 1; }
exec "$WORKSHOP" release voice-core "${1:?version, like 1.1.0}" ${2:+"$2"}
