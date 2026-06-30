# ShortsCast Editor App — Verification Results

Plan: `docs/superpowers/plans/2026-06-30-shortscast-editor-app.md` (Plan 5, SwiftUI app shell).

## Automated verification (done)

| Check | Result |
|---|---|
| `TimelineLayoutTests` (3) | PASS |
| `TimeLabelTests` (2) | PASS |
| Full suite `swift test` | PASS — 124 tests, 0 failures |
| `swift build` (debug, all view tasks) | PASS |
| `swift build -c release` | PASS |
| `./Scripts/make-app.sh` | Built `.build/ShortsCastApp.app` |
| `codesign -dv .build/ShortsCastApp.app` | `Identifier=com.shortscast.app` |
| Demo bundle `/tmp/shortscast-demo/demo.shortscast` | present (`events.json` + `raw.mov`) |

## Plan adaptation applied (Task 8)

The plan predates the AVFoundation capture migration. The macOS 12.3 availability
guards were dropped upstream (`AVCaptureScreenInput` is 10.7+), and neither
`EditorModel.record` nor `TargetResolver.resolve` is availability-gated. So:

- `RecordSheet` is **not** `@available(macOS 12.3, *)`; the Record button is **not** `#available`-gated.
- `TargetResolver.resolve(...)` is `throws` (not `async`), so the plan's `try await` became `try`.

Record is therefore functional on this macOS 12.6 machine (capture is live-verified here).

## Manual GUI steps (human-run — pending)

Launch: `./Scripts/make-app.sh && open .build/ShortsCastApp.app`

- [ ] Step 1: Window opens with toolbar + empty preview placeholder.
- [ ] Step 2: Open `/tmp/shortscast-demo/demo.shortscast` → preview renders framed 9:16 composite; slider scrubs; Play advances playhead; timeline shows segment blocks.
- [ ] Step 3: Select a segment block → zoom-× slider appears; dragging it changes preview zoom. Change Format to 1:1 → reframes. Adjust background/corner/padding → live updates.
- [ ] Step 4: Save → `project.json` appears in the bundle. Export → check 9:16 + 1:1 → choose folder → two MP4s produced, revealed in Finder, play correctly.
- [ ] Step 5: Record → set seconds → Record → captures main display, writes bundle, reopens it with real content. (Requires Screen Recording permission for the .app.)
