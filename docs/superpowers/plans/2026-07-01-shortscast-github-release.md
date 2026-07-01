# ShortsCast GitHub Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local `Scripts/release.sh` that builds, packages (signature-safe `.zip`), verifies, and publishes a downloadable ShortsCast release to GitHub, plus a tester-facing `INSTALL.md`.

**Architecture:** Reuse the existing `make-app.sh` universal build. Parametrize it for a release (version + ad-hoc signing). A new `release.sh` stages the bundle as `ShortsCast.app`, zips it with `ditto`, verifies the round-trip with `codesign`/`spctl`, and publishes via the `gh` CLI. `INSTALL.md` doubles as the release notes.

**Tech Stack:** bash, `codesign`, `ditto`, `spctl`, `/usr/libexec/PlistBuddy`, GitHub `gh` CLI. No new app code, no Swift changes.

## Global Constraints

- Distribution is **unnotarized** (no paid Apple Developer account). Testers hit a one-time Gatekeeper "Open Anyway" step — this is expected, not a bug.
- Release artifacts are signed **ad-hoc** (`--sign -`), independent of the developer's local `ShortsCast Dev` cert.
- Universal binary (arm64 + x86_64); macOS floor 12.
- Zip the bundle with **`ditto -c -k --keepParent`**, never `zip` (a plain `zip` corrupts the code signature → "app is damaged").
- Artifact bundle is named **`ShortsCast.app`**; asset file is **`ShortsCast-<version>-macOS.zip`**; git tag is **`v<version>`**.
- These are shell/doc changes; each task's "test" is a runnable verification command, not an XCTest.

---

### Task 1: Parametrize `make-app.sh` (version + ad-hoc release mode)

**Files:**
- Modify: `Scripts/make-app.sh`

**Interfaces:**
- Consumes: existing `make-app.sh` (universal build; `SIGN_ID`/`SIGN` resolution; two `Info.plist` heredocs with hardcoded `<string>0.1.0</string>`).
- Produces: `make-app.sh` honors two env vars — `SHORTSCAST_VERSION` (default `0.1.0`) sets both bundles' `CFBundleShortVersionString`, and `SHORTSCAST_SIGN_ID=-` forces ad-hoc signing without a keychain lookup. Consumed by Task 3's `release.sh`.

- [ ] **Step 1: Add a version variable**

In `Scripts/make-app.sh`, immediately after the `BIN="$(...)"` line, add:
```bash
VERSION="${SHORTSCAST_VERSION:-0.1.0}"
```

- [ ] **Step 2: Treat `SHORTSCAST_SIGN_ID=-` as explicit ad-hoc**

Replace the existing signing-identity resolution block:
```bash
SIGN_ID="${SHORTSCAST_SIGN_ID:-ShortsCast Dev}"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
  SIGN="$SIGN_ID"
  echo "Signing with stable identity: $SIGN_ID"
else
  SIGN="-"
  echo "warning: no '$SIGN_ID' code-signing identity found — signing ad-hoc."
  echo "         macOS will re-ask for permissions on every rebuild."
  echo "         Run ./Scripts/make-signing-cert.sh once to stop the re-prompts."
fi
```
with:
```bash
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
```

- [ ] **Step 3: Inject the version into both Info.plist heredocs**

Both `.app` bundles are written with a `cat > "$APP/Contents/Info.plist" <<'PLIST'` heredoc whose delimiter is single-quoted (`<<'PLIST'`), which blocks variable expansion, and each has `<key>CFBundleShortVersionString</key><string>0.1.0</string>`.

For **both** heredocs: change the opening delimiter from `<<'PLIST'` to `<<PLIST` (the plists contain no `$` or backticks, so unquoting is safe), and change that version line to:
```
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
```
Leave `CFBundleVersion` as `1`.

- [ ] **Step 4: Verify version injection + ad-hoc mode**

Run:
```bash
SHORTSCAST_VERSION=9.9.9 SHORTSCAST_SIGN_ID=- ./Scripts/make-app.sh >/tmp/mk.log 2>&1
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' .build/ShortsCastApp.app/Contents/Info.plist
codesign -dvvv .build/ShortsCastApp.app 2>&1 | grep -i "Signature"
grep -c "Signing ad-hoc (release mode)." /tmp/mk.log
```
Expected: prints `9.9.9`; prints `Signature=adhoc`; prints `1`.

- [ ] **Step 5: Restore a normal local build and commit**

Run (so the working tree's built app isn't left on a fake version — harmless, but tidy):
```bash
./Scripts/make-app.sh >/dev/null 2>&1 || true
git add Scripts/make-app.sh
git commit -m "chore: parametrize make-app.sh version + ad-hoc release mode"
```

---

### Task 2: Tester-facing `INSTALL.md`

**Files:**
- Create: `INSTALL.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `INSTALL.md` at the repo root — used verbatim by Task 3 as the `gh release create --notes-file`.

- [ ] **Step 1: Write `INSTALL.md`**

Create `INSTALL.md` with exactly:
```markdown
# Installing ShortsCast

ShortsCast is a free, open build that isn't distributed through the App Store, so
macOS shows a one-time warning the first time you open it. These steps clear it.
Works on macOS 12 or later.

## Install

1. Download `ShortsCast-<version>-macOS.zip` from the release below and double-click
   it to unzip. You'll get **ShortsCast**.
2. Drag **ShortsCast** into your **Applications** folder.
3. Double-click **ShortsCast**. macOS says it "cannot be opened because Apple cannot
   check it for malicious software." Click **Done**.
4. Open  **System Settings → Privacy & Security**. Scroll down to the **Security**
   section — you'll see *"ShortsCast was blocked to protect your Mac."* Click
   **Open Anyway**, then confirm with your password or Touch ID.
5. ShortsCast opens. You only need to do steps 3–4 once.

## Grant permissions (first launch)

For screen capture and the click-driven auto-zoom to work, ShortsCast needs three
permissions. When you first record, macOS will prompt for them — or grant them up
front in **System Settings → Privacy & Security**:

- **Screen Recording**
- **Accessibility**
- **Input Monitoring**

After granting them, **quit and reopen** ShortsCast (macOS applies Accessibility and
Input Monitoring only on the next launch).

## Faster path (if you're comfortable with Terminal)

Instead of steps 3–4 you can clear the download flag directly:

    xattr -dr com.apple.quarantine /Applications/ShortsCast.app

Then open the app normally.
```

- [ ] **Step 2: Verify it renders and commit**

Run:
```bash
head -3 INSTALL.md
git add INSTALL.md
git commit -m "docs: add INSTALL.md tester instructions"
```
Expected: prints the first three lines without error.

---

### Task 3: `Scripts/release.sh`

**Files:**
- Create: `Scripts/release.sh`

**Interfaces:**
- Consumes: `make-app.sh` (via `SHORTSCAST_VERSION` + `SHORTSCAST_SIGN_ID=-` from Task 1); `INSTALL.md` (Task 2); `gh` CLI; `ditto`; `codesign`; `spctl`.
- Produces: `Scripts/release.sh <version>` — builds, stages `ShortsCast.app`, zips to `ShortsCast-<version>-macOS.zip`, verifies, and publishes tag `v<version>`. Honors `DRY_RUN=1` to build+verify without publishing.

- [ ] **Step 1: Create the script**

Create `Scripts/release.sh` with exactly:
```bash
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

# 2. Stage under the clean user-facing name and re-sign the renamed bundle.
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/.build/ShortsCastApp.app" "$STAGE/ShortsCast.app"
codesign --force --deep --sign - "$STAGE/ShortsCast.app"

# 3. Zip signature-safely (ditto, NOT zip).
rm -f "$ZIP"
ditto -c -k --keepParent "$STAGE/ShortsCast.app" "$ZIP"
echo "==> Wrote $ZIP"

# 4. Verify the artifact round-trips (unzip -> codesign must still pass).
VERIFY="$(mktemp -d)"
ditto -x -k "$ZIP" "$VERIFY"
codesign --verify --deep --strict --verbose=2 "$VERIFY/ShortsCast.app"
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
```

- [ ] **Step 2: Make it executable**

Run:
```bash
chmod +x Scripts/release.sh
```

- [ ] **Step 3: Verify end-to-end in dry-run (no GitHub publish)**

Run:
```bash
DRY_RUN=1 ./Scripts/release.sh 0.0.1-test 2>&1 | tail -8
ls -1 ShortsCast-0.0.1-test-macOS.zip
```
Expected: the run reaches `DRY_RUN: built and verified …`; the `codesign --verify` line produces no error (script would have aborted via `set -e` otherwise); the `spctl` line reports rejection (unnotarized); the `ls` shows the zip exists.

- [ ] **Step 4: Confirm the zipped bundle opens as a valid signed app**

Run:
```bash
T="$(mktemp -d)"; ditto -x -k ShortsCast-0.0.1-test-macOS.zip "$T"
codesign --verify --deep --strict "$T/ShortsCast.app" && echo "SIGNATURE OK"
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$T/ShortsCast.app/Contents/Info.plist"
rm -rf "$T"
```
Expected: prints `SIGNATURE OK` and `0.0.1-test`.

- [ ] **Step 5: Clean up the test artifact and commit**

Run:
```bash
rm -f ShortsCast-0.0.1-test-macOS.zip
git add Scripts/release.sh
git commit -m "feat: add release.sh (build, package, verify, publish to GitHub)"
```

---

### Task 4: Cut the first real release (manual gate)

**Files:** none (operational).

This task is run by a human and requires a GitHub-authenticated `gh`.

- [ ] **Step 1: Ensure `gh` is authenticated**

Run: `gh auth status`
Expected: shows a logged-in account with `repo` scope for `prabhagharan/shorts-cast`. If not: `gh auth login`.

- [ ] **Step 2: Publish**

Run: `./Scripts/release.sh 0.1.0`
Expected: builds, verifies, and prints `Published v0.1.0`. The release appears at
`https://github.com/prabhagharan/shorts-cast/releases/tag/v0.1.0` with the zip asset
and `INSTALL.md` as the notes.

- [ ] **Step 3: Verify on a clean machine/account (the real test)**

On a second Mac or a fresh user account: download the zip from the release page in a
browser, and follow `INSTALL.md`. Confirm: the "Open Anyway" flow launches the app, and
after granting the three permissions it records. Note the actual macOS version tested.

- [ ] **Step 4: Record the result**

Append a one-line pass/fail note (macOS version + outcome) to the release description or
a short results file. If a step in `INSTALL.md` was wrong, fix it and re-run
`./Scripts/release.sh 0.1.0` (it re-uploads the asset via `--clobber`).

---

## Self-Review

**Spec coverage:**
- Local `release.sh` (build → rename `ShortsCast.app` → ad-hoc sign → `ditto` zip → verify → `gh` publish) → Task 3. Version/ad-hoc prerequisites → Task 1.
- Tester `INSTALL.md` (Sequoia "Open Anyway" + three permissions + `xattr` fast path) → Task 2.
- Ad-hoc release signing independent of the local cert → Task 1 (`SHORTSCAST_SIGN_ID=-`) + Task 3.
- `.zip` via `ditto`, not `zip` → Task 3, Global Constraints.
- Artifact named `ShortsCast.app`, asset `ShortsCast-<version>-macOS.zip`, tag `v<version>` → Tasks 1/3.
- Verification (`codesign --verify`, `spctl -a`) before publish → Task 3 Step 3/4.
- Manual clean-machine gate → Task 4.
- Out of scope (notarization/DMG/CI/auto-update) → not implemented, as specified.

**Placeholder scan:** No TBD/TODO; every step has the exact file edit, command, and expected output. `<version>` in `INSTALL.md` is intentional literal copy shown to testers, not a plan placeholder.

**Type/name consistency:** `SHORTSCAST_VERSION` and `SHORTSCAST_SIGN_ID` are defined in Task 1 and consumed identically in Task 3. Artifact/paths match across tasks: build output `.build/ShortsCastApp.app` → staged `ShortsCast.app` → asset `ShortsCast-<version>-macOS.zip`. `DRY_RUN` used consistently. `--notes-file INSTALL.md` matches the file created in Task 2.

## Notes

- `make-signing-cert.sh` / the `ShortsCast Dev` identity are unaffected; local dev builds still prefer the stable identity for TCC persistence. Only releases force ad-hoc.
- If a paid Apple Developer account is obtained later, notarization is a follow-on change: add `codesign` with a Developer ID identity + `xcrun notarytool submit` + `xcrun stapler staple` before the `ditto` zip, and simplify `INSTALL.md` to a plain drag-install.
