#!/usr/bin/env bash
# Package the shortscast-rec CLI into a minimal, ad-hoc-signed .app bundle.
#
# ScreenCaptureKit will not deliver frames to a bare command-line executable:
# macOS gates frame delivery on the capturing process being a TCC-recognized
# screen-recording client, which in practice means a signed .app bundle. This
# wraps the same executable in a bundle (with a stable bundle identifier) and
# ad-hoc signs it so it can be granted Screen Recording in System Settings.
#
# The bundle is written under .build/ (git-ignored). Run the inner executable
# directly with the normal CLI flags — it still receives argv, and inherits the
# bundle's TCC identity:
#
#   .build/ShortsCastRec.app/Contents/MacOS/shortscast-rec --seconds 5 --out /tmp/test.shortscast --direct
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Build a universal (arm64 + x86_64) release so the bundle runs on both Apple
# Silicon and Intel Macs when copied to another machine. With multiple --arch the
# products land outside .build/release, so resolve the real dir via --show-bin-path.
ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

VERSION="${SHORTSCAST_VERSION:-0.1.0}"

# Sign with a STABLE identity so macOS keeps the app's permission (TCC) grants —
# Screen Recording, Accessibility, Input Monitoring — across rebuilds. Ad-hoc
# signing (--sign -) changes the code identity every build, so macOS forgets the
# grants and re-prompts. Create the identity once: ./Scripts/make-signing-cert.sh
SIGN_ID="${SHORTSCAST_SIGN_ID:-ShortsCast Dev}"
if [ "$SIGN_ID" = "-" ]; then
  SIGN="-"
  echo "Signing ad-hoc (release mode)."
elif security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
  SIGN="$SIGN_ID"
  echo "Signing with stable identity: $SIGN_ID"
else
  SIGN="-"
  echo "warning: no '$SIGN_ID' code-signing identity found — signing ad-hoc."
  echo "         macOS will re-ask for permissions on every rebuild."
  echo "         Run ./Scripts/make-signing-cert.sh once to stop the re-prompts."
fi

APP="$ROOT/.build/ShortsCastRec.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/shortscast-rec" "$APP/Contents/MacOS/shortscast-rec"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.shortscast.rec</string>
  <key>CFBundleName</key><string>ShortsCastRec</string>
  <key>CFBundleExecutable</key><string>shortscast-rec</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.3</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign "$SIGN" "$APP"

echo "Built $APP"
echo "Grant it Screen Recording (System Settings > Privacy & Security > Screen Recording > +),"
echo "then run:"
echo "  $APP/Contents/MacOS/shortscast-rec --seconds 5 --out /tmp/test.shortscast --direct"

# --- GUI editor app ---
APP="$ROOT/.build/ShortsCastApp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/shortscast-app" "$APP/Contents/MacOS/shortscast-app"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.shortscast.app</string>
  <key>CFBundleName</key><string>ShortsCast</string>
  <key>CFBundleExecutable</key><string>shortscast-app</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign "$SIGN" "$APP"
echo "Built $APP"
echo "Launch the editor: open $APP"

# --- MCP server (background helper; frame delivery needs a signed .app) ---
APP="$ROOT/.build/ShortsCastMCP.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/shortscast-mcp" "$APP/Contents/MacOS/shortscast-mcp"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.shortscast.mcp</string>
  <key>CFBundleName</key><string>ShortsCastMCP</string>
  <key>CFBundleExecutable</key><string>shortscast-mcp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.3</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --deep --sign "$SIGN" "$APP"
echo "Built $APP"
echo "Grant it Screen Recording, Accessibility, Input Monitoring, then point your MCP client at:"
echo "  $APP/Contents/MacOS/shortscast-mcp"
