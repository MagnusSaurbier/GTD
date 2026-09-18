# T01 — Spike: access Obsidian's iCloud vault from our own app

**Wave 0 · parallel to T00 · needs the user (real iPhone + Mac, real iCloud)**

## Model recommendation

**Difficulty:** Medium (small code, high stakes) · **Recommended model:** Opus

Only ~300 lines, but it depends on exact platform knowledge — security-scoped bookmarks into *another app's* iCloud container, sandbox entitlements, `NSFilePresenter` vs `NSMetadataQuery` semantics. A subtly wrong spike produces a false no-go that would overturn the whole architecture, and the go/no-go + fallback evaluation is a judgment call. Sonnet could write the app; Opus should own the verdict.

## Goal

Prove or disprove the one assumption the whole stack rests on: a third-party app can durably
read/write a user-picked folder inside Obsidian's iCloud container
(`iCloud Drive/Obsidian/<vault>`) on iOS and macOS, offline, and see remote changes.

## Requirements covered

N1, N2, N3, D2 (notification permission smoke test), C1 (Shortcut writes into `Inbox/`).

## Owns

`Spikes/VaultAccess/` (throw-away Xcode project, may be hand-made in Xcode or XcodeGen) and
`Spikes/VaultAccess/REPORT.md`. Nothing here is reused as production code.

## What to build

A single-screen multiplatform SwiftUI app:

1. "Pick vault folder" → `.fileImporter`/`UIDocumentPickerViewController` for folders →
   store a security-scoped bookmark (macOS: app-scoped bookmark + sandbox entitlement
   `com.apple.security.files.bookmarks.app-scope` and user-selected read-write) → restore on relaunch.
2. List `Actions/*.md` with download status (`URLResourceKey.ubiquitousItemDownloadingStatusKey`);
   button to `startDownloadingUbiquitousItem` for evicted items.
3. "Write test file": coordinated atomic write of `Inbox/<timestamp>-spike.md`.
4. "Edit first action": coordinated read-modify-write of one throw-away note created by the spike
   (never an existing user note).
5. Live change feed: compare `NSFilePresenter` on the folder vs `NSMetadataQuery` vs
   `DispatchSource` directory watching; log which one fires for remote (other device) edits.
6. Schedule a local notification 1 min ahead.

## Test protocol for the user (write the results into REPORT.md)

| # | Check | iPhone | Mac |
| --- | --- | --- | --- |
| 1 | Bookmark survives app relaunch and device reboot | | |
| 2 | File written on device A appears on device B and in Obsidian; latency | | |
| 3 | Edit made in Obsidian shows up in the change feed; which mechanism fired | | |
| 4 | Airplane mode: read + write work; changes sync after reconnect | | |
| 5 | Evicted file ("Remove Download" in Files) can be re-downloaded by the app | | |
| 6 | Simultaneous edit of the same file on both devices → what conflict artefact appears | | |
| 7 | Apple Shortcut "Save File" into `Inbox/` works with the app not running (< 3 s) | | |
| 8 | Notification fires with the app terminated | | |
| 9 | Access still works after 7 days / after Obsidian updates (note date) | | |

## Acceptance

`REPORT.md` with the filled table, a go / no-go verdict, the recommended change-detection
mechanism for T15, the required entitlements/Info.plist keys, and — if no-go — an evaluation of
the fallback (app-owned iCloud container as the vault location, opened in Obsidian on Mac only, or
"Obsidian vault in a plain iCloud Drive folder").

## Notes

- Free provisioning is enough for the spike (7-day expiry); note whether the user has a paid team.
- Agents cannot run steps on physical devices: prepare the app and the protocol, then hand over to the user.

## Result

Skipped by user decision on 2026-09-19: assume local file access works; fallback per brief if it doesn't.

Recorded in `docs/ARCHITECTURE.md` §6 ("Vault access on device (T01)"). T15 builds against a
security-scoped bookmark to a user-picked folder without waiting for a device spike; if the
assumption breaks in real use, the fallback evaluation above is still the plan.
