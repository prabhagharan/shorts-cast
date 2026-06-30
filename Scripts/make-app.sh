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

swift build -c release

APP="$ROOT/.build/ShortsCastRec.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/shortscast-rec" "$APP/Contents/MacOS/shortscast-rec"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.shortscast.rec</string>
  <key>CFBundleName</key><string>ShortsCastRec</string>
  <key>CFBundleExecutable</key><string>shortscast-rec</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.3</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "Grant it Screen Recording (System Settings > Privacy & Security > Screen Recording > +),"
echo "then run:"
echo "  $APP/Contents/MacOS/shortscast-rec --seconds 5 --out /tmp/test.shortscast --direct"

# --- GUI editor app ---
APP="$ROOT/.build/ShortsCastApp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/shortscast-app" "$APP/Contents/MacOS/shortscast-app"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.shortscast.app</string>
  <key>CFBundleName</key><string>ShortsCast</string>
  <key>CFBundleExecutable</key><string>shortscast-app</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"
echo "Launch the editor: open $APP"
