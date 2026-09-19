# TEST-INSTRUCTIONS — for a local agent (or human) with Xcode

<!-- ORCHESTRATION FILE. Remove it (git rm TEST-INSTRUCTIONS.md) once the build-out is finished
     (agent_task/42-docs-handover.md has a filled-in Result) and every section below has been
     verified on a Mac. Until then, keep the "Verification log" at the bottom current. -->

## Why this file exists

This app is being built by a swarm of agents in a **Linux container with Swift 6.4 and no Xcode**.
Everything Foundation-only was compiled and unit-tested there. Everything that needs an Apple SDK
(SwiftUI, AppKit/UIKit, UserNotifications, AppIntents, `NSFileCoordinator`, security-scoped
bookmarks, `#Preview`, the app target, the iOS-simulator build) was written **without ever being
compiled**. Your job is to run the real toolchain, report what breaks, and fix the mechanical
things (wrong API names, missing `import`, availability annotations) without changing behaviour.

Read `CLAUDE.md` first (durable rules, especially: never touch the real Obsidian vault). Then
`docs/ARCHITECTURE.md` §5 "Platform guards" for the `#if canImport(SwiftUI)` convention every
target follows.

## Setup (once)

```sh
brew install xcodegen
cd Packages/GTDKit && swift package resolve && cd ../..
```

## Gate 1 — package builds and tests on macOS

```sh
scripts/check.sh
```

This runs `swift build`, `swift test` in `Packages/GTDKit`, then (now that `xcodebuild` exists)
the iOS-simulator build of the package scheme, then `scripts/check-docs.sh`. On the Mac the
platform-guarded code compiles for the first time, so expect errors. Triage:

| Error class | What to do |
| --- | --- |
| Unknown API / wrong label / missing `import` in a `#if canImport(SwiftUI)` file | Fix in place, minimal edit. |
| Swift 6 strict-concurrency error in UI code (`@MainActor` isolation, non-Sendable capture) | Fix properly (`@MainActor`, `Sendable` value types). No `@unchecked Sendable`, no `nonisolated(unsafe)` unless you write a comment saying why. |
| Missing iOS 26 / macOS 26 API the agent guessed at | Replace with the closest real API; note it in the log below. |
| A test that fails only on macOS | Do **not** disable it. Find out whether the code or the test is wrong; if you cannot, report it verbatim in the log. |
| Resource bundle errors (`Bundle.module`, asset catalog, `Localizable.xcstrings`) | See ARCHITECTURE §5 and `agent_task/00-foundation.md` "Contract changes"; the intended behaviour is: colours fall back to code-defined values, so a missing catalog must never crash. |

Single target / single test, for iterating:

```sh
cd Packages/GTDKit
swift test --filter GTDModelTests
swift test --filter GTDModelTests.ReducerTests/testNextCapReached   # adjust name
```

## Gate 2 — the app builds and launches

```sh
scripts/check.sh --app       # xcodegen + xcodebuild of the macOS app
open GTD.xcodeproj           # then run the GTD scheme on "My Mac" and on an iPhone simulator
```

The shell is wired (T40): the app resolves a security-scoped bookmark, opens the vault through
`FileVaultStore` + `VaultBackend`, and shows `OnboardingView` when there is no vault yet. The
launch argument **`-useFixtures`** replaces that whole chain with `InMemoryBackend` +
`GTDFixtures.sampleSnapshot` — nothing is read or written on disk. Use it for this gate
(Product → Scheme → Edit Scheme → Arguments → `-useFixtures`).

Smoke test with `-useFixtures`:

1. App launches on Mac and on an iPhone simulator without crashing. Mac: sidebar · list · detail,
   minimum window 900×560. iPhone: three tabs — Next (on-the-go) · Inbox (count badge) · Routines.
2. Inbox shows ≈6 items; Next shows actions at cap − 1; Projects lists 5 projects incl. one
   stalled and one on hold; Waiting shows an overdue item; Routines shows Morning/Bedtime.
3. File one inbox item to Next → it appears in Next. File another → the "Next is full" forced
   choice appears (no silent drop). Undo (toast, and `⌘Z` on Mac) restores the previous state.
4. Complete a project action → the "What's next?" sheet appears.
5. Mac menu bar: `⌘1…⌘7` switch sections, `⌘N` opens the capture sheet, `⌘I` starts processing,
   `⌘Z` undoes, `⌘,` opens Settings. iPhone: the gear on Next opens Settings.
6. Deep links: `xcrun simctl openurl booted gtd://inbox` starts processing; `gtd://waiting` opens
   the waiting list; `gtd://routine/GTD/Routines/Morning.md` opens that routine's runner.
7. Dark mode + Dynamic Type (largest accessibility size) on iPhone: nothing clipped, nothing
   overlapping. Check `docs/STYLEGUIDE.md` §9 for the screens that exist.

The app's own test bundles (`AppTests`, `AppUITests`) build with the project and run with
`⌘U`; the UI tests launch with `-useFixtures` themselves.

Then run `docs/MANUAL_TEST.md` — the real-vault (on a **copy**), two-device and notification
checks that no simulator can cover.

## Gate 3 — vault access on device (replaces the skipped spike T01)

T01 was skipped on the user's instruction ("assume the app can read local files"). Verify the
assumption once the vault backend exists (T15/T16 landed):

**Never point the app at the real vault under `~/Library/Mobile Documents/iCloud~md~obsidian/`
while testing** — use a copy of it, or a copy of
`Packages/GTDKit/Sources/GTDFixtures/Resources/SampleVault`.

1. Onboarding (or Settings → "Change vault…") → pick the vault folder (a copy!).
2. Quit and relaunch: the app must reopen the folder from its security-scoped bookmark without
   asking again.
3. Edit a note in Obsidian (or any editor) while the app is running: the change shows up in the
   app within a few seconds.
4. Edit in the app: the file on disk changes, and unknown frontmatter keys / body sections in
   that file are untouched (compare with `diff`).
5. On iOS: same four steps with the vault in the Obsidian iCloud folder via the Files picker.
   If step 2 or 3 fails on iOS, that is the "no-go" case from `agent_task/01-spike-vault-access.md`;
   record it and stop, the fallback (app-owned iCloud container) is a design change for the user.

## Migration script (independent of Swift)

```sh
cd Tools/migrate && python3 -m pytest -q          # expect all green
python3 migrate.py /path/to/COPY/of/vault         # dry run; read migration-report.md
```

Review `Tools/migrate/README.md`'s checklist before anyone runs `--apply` on real data.

## How to report

Fill in the log below and commit it with the fixes on the branch you were given (the swarm works
on `claude/sharp-volta-p59pxh`; if you are on a different branch, say so in the log). For each fix:
one bullet, file path, one line what was wrong. For each thing you could not fix: the exact error
text in a fenced block and the file/line. Do not refactor, restyle or "improve" code that compiles.

## Verification log

| Date | Gate | Result | Notes |
| --- | --- | --- | --- |
| | 1 | | |
| | 2 | | |
| | 3 | | |
| | migrate | | |

### Fixes applied

(none yet)

### Unresolved

(none yet)
