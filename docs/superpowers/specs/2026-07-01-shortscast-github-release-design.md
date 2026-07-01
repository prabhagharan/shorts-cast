# ShortsCast — Downloadable GitHub Release (design)

**Goal:** Let a handful of non-technical testers download and run ShortsCast from
GitHub Releases, with the smallest possible install friction, using a **local
release script** (no CI) and a plain **`.zip`** artifact.

## Constraints & decisions

- **Audience:** a few non-technical testers who expect it to "just open."
- **No paid Apple Developer account** → **no notarization**. macOS Gatekeeper will
  therefore show a one-time warning on first launch. This is unavoidable without
  notarization; the design minimizes and clearly signposts it rather than removing it.
- **Publish flow:** a local script run on the developer's Mac, uploading via the `gh` CLI.
  No GitHub Actions.
- **Package:** a `.zip` of the `.app` (not a DMG).
- **Signing for release:** ad-hoc (`--sign -`) — self-contained, no dependency on the
  developer's personal `ShortsCast Dev` cert. Self-signed vs ad-hoc makes no difference
  to testers since neither is notarized; both hit the same "Open Anyway" step.
- Supported OS floor: macOS 12 (unchanged). Universal binary (arm64 + x86_64).

## Components

### 1. `Scripts/release.sh`

Usage: `./Scripts/release.sh <version>` (e.g. `./Scripts/release.sh 0.1.0`).

Steps:
1. Validate the version arg (e.g. `0.1.0`), derive tag `v<version>`.
2. Build + package the universal `.app` via `make-app.sh`, signing **ad-hoc** for the
   release (pass an env var, e.g. `SHORTSCAST_SIGN_ID=-`, so the release doesn't use the
   dev's personal cert). The app's `Info.plist` `CFBundleShortVersionString` /
   `CFBundleVersion` are set from `<version>` so the bundle matches the tag.
3. Copy the built `ShortsCastApp.app` to a staging dir as **`ShortsCast.app`** (clean
   user-facing name; testers see "ShortsCast", matching `INSTALL.md`), then zip it
   **signature-safely**:
   `ditto -c -k --keepParent "<staging>/ShortsCast.app" "ShortsCast-<version>-macOS.zip"`.
   (`ditto`, not `zip` — a plain `zip` can strip/relocate signature resources and make the
   app report as "damaged." Re-`codesign` the renamed copy so the signature matches.)
4. **Verify the artifact** before publishing (see Verification).
5. Publish:
   `gh release create v<version> "ShortsCast-<version>-macOS.zip" --title "ShortsCast <version>" --notes-file INSTALL.md`.
   If the tag/release already exists, upload the asset to it instead (`gh release upload --clobber`).

Preconditions checked with clear errors: `gh` installed and authenticated
(`gh auth status`); working tree state is the developer's call (not enforced).

### 2. `INSTALL.md` (tester-facing; also the release notes body)

Written for non-technical users, covering the strictest current flow (macOS 15 Sequoia):

1. Download `ShortsCast-<version>-macOS.zip` from the release; double-click to unzip.
2. Drag **ShortsCast** into **Applications**.
3. Double-click it → a warning appears that it can't be verified → click **Done**.
4. Open **System Settings → Privacy & Security**, scroll to Security, and next to
   "ShortsCast was blocked" click **Open Anyway**; confirm with Touch ID/password.
5. On first launch, grant **Screen Recording**, **Accessibility**, and **Input
   Monitoring** in Privacy & Security (needed for capture + click-driven auto-zoom),
   then quit and reopen the app.

Also includes:
- A note that these permission grants are per-Mac and expected.
- An "advanced / faster" one-liner for Terminal-comfortable users:
  `xattr -dr com.apple.quarantine /Applications/ShortsCast.app`.
- A minimum-macOS note (12+).

### 3. Signing (unchanged local behavior)

`make-app.sh` keeps its current behavior for local dev (prefers the stable
`ShortsCast Dev` identity so TCC grants persist across rebuilds). The release script
overrides to ad-hoc via the identity env var so release artifacts don't depend on a
cert that only exists on the developer's machine.

## Verification

The script self-verifies the artifact before `gh release create`:
1. Unzip the produced `.zip` into a temp dir with `ditto -x -k`.
2. `codesign --verify --deep --strict` on the extracted `.app` → must pass (proves the
   zip round-trip didn't corrupt the bundle).
3. `spctl -a -vv` on the extracted app → expected to report "rejected / unnotarized";
   the script prints this so the exact Gatekeeper verdict is known and matches what
   `INSTALL.md` tells testers to expect.
4. Abort the release if `codesign --verify` fails.

Manual gate (once): run `./Scripts/release.sh` for a test version, download the asset
from the resulting release on a second Mac (or a clean user account), and confirm the
`INSTALL.md` steps open the app cleanly.

## Out of scope

- Notarization / DMG / GitHub Actions (explicitly deferred; each is a later change if
  the audience or account situation changes).
- Auto-update mechanism.
- Homebrew cask or other distribution channels.
