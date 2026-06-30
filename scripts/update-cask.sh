#!/usr/bin/env bash
#
# Regenerate Casks/tokenholic.rb from a published GitHub release DMG.
#
# Usage:
#   scripts/update-cask.sh            # use the latest release (needs `gh`)
#   scripts/update-cask.sh v0.7.0     # pin a specific tag
#
# The CI release workflow (.github/workflows/build-dmg.yml) does the same bump
# automatically on a version tag; this script is for doing it by hand.
set -euo pipefail

REPO="conol-ai/tokenholic"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK="$ROOT/Casks/tokenholic.rb"

if [ "${1:-}" ]; then
  TAG="$1"
else
  command -v gh >/dev/null || { echo "need a tag arg or the gh CLI" >&2; exit 1; }
  TAG="$(gh release view -R "$REPO" --json tagName -q .tagName)"
fi
VERSION="${TAG#v}"
URL="https://github.com/$REPO/releases/download/$TAG/Tokenholic-$VERSION.dmg"

echo "Release: $TAG (version $VERSION)"
TMP="$(mktemp -t tokenholic-dmg.XXXXXX)"
trap 'rm -f "$TMP"' EXIT
curl -fsSL "$URL" -o "$TMP"
SHA="$(shasum -a 256 "$TMP" | awk '{print $1}')"
echo "sha256:  $SHA"

VERSION="$VERSION" SHA="$SHA" python3 - "$CASK" <<'PY'
import os, re, sys
path = sys.argv[1]
text = open(path).read()
text = re.sub(r'version "[^"]*"', 'version "%s"' % os.environ["VERSION"], text, count=1)
text = re.sub(r'sha256 "[^"]*"', 'sha256 "%s"' % os.environ["SHA"], text, count=1)
open(path, "w").write(text)
PY

echo "Updated $CASK"
