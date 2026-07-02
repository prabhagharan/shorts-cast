#!/usr/bin/env bash
# Build, package, verify, and publish a downloadable ShortsCast release to GitHub.
#
#   ./Scripts/release.sh 0.1.0          # build + verify + publish tag v0.1.0
#   DRY_RUN=1 ./Scripts/release.sh 0.1.0  # build + verify only (no GitHub release)
#
# Unnotarized (no paid Apple account): testers do a one-time "Open Anyway" — see INSTALL.md.
set -euo pipefail

VERSION="${1:?usage: release.sh <version>  e.g. 0.1.0}"
DRY_RUN="${DRY_RUN:-0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
TAG="v$VERSION"
ZIP="ShortsCast-$VERSION-macOS.zip"

command -v gh >/dev/null 2>&1 || { echo "error: GitHub CLI 'gh' not found (brew install gh)" >&2; exit 1; }

# 1. Build the universal app, ad-hoc signed, versioned to match the tag.
echo "==> Building universal app for $VERSION"
SHORTSCAST_VERSION="$VERSION" SHORTSCAST_SIGN_ID="-" ./Scripts/make-app.sh

# 2. Stage under clean user-facing names and re-sign the renamed bundles.
#    Ship the GUI editor and the MCP agent server side by side.
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/.build/ShortsCastApp.app" "$STAGE/ShortsCast.app"
codesign --force --deep --sign - "$STAGE/ShortsCast.app"
cp -R "$ROOT/.build/ShortsCastMCP.app" "$STAGE/ShortsCastMCP.app"
codesign --force --deep --sign - "$STAGE/ShortsCastMCP.app"

# 3. Zip signature-safely (ditto, NOT zip). Both apps sit at the zip root.
rm -f "$ZIP"
ditto -c -k "$STAGE" "$ZIP"
echo "==> Wrote $ZIP"

# 4. Verify the artifact round-trips (unzip -> codesign must still pass).
VERIFY="$(mktemp -d)"
ditto -x -k "$ZIP" "$VERIFY"
codesign --verify --deep --strict --verbose=2 "$VERIFY/ShortsCast.app"
codesign --verify --deep --strict --verbose=2 "$VERIFY/ShortsCastMCP.app"
echo "==> Gatekeeper verdict (expected: rejected / unnotarized):"
spctl -a -vv "$VERIFY/ShortsCast.app" || true
rm -rf "$VERIFY"

# 5. Publish (unless dry run).
if [ "$DRY_RUN" = "1" ]; then
  echo "==> DRY_RUN: built and verified $ZIP; not publishing."
  exit 0
fi
gh auth status >/dev/null
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "==> Release $TAG exists; uploading asset"
  gh release upload "$TAG" "$ZIP" --clobber
else
  echo "==> Creating release $TAG"
  gh release create "$TAG" "$ZIP" --title "ShortsCast $VERSION" --notes-file INSTALL.md
fi
echo "==> Published $TAG"
