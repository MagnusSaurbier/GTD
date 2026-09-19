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

### Where to look first (T41 blind review)

T41 read every `#if canImport(SwiftUI)` file and all of `App/` without a compiler and fixed what
was clearly wrong. These are the places most likely to break when the real compiler sees them,
**in the order worth trying**. Each one is a whole class of failures: if #1 or #4 breaks, a lot
of files break at once, so fix those before reading any other error.

1. **`DesignSystem/Components/Containers.swift`** — `.glassEffect()` and `GlassEffectContainer { }`
   are the only two APIs in the repo nobody could check the shape of. They sit behind
   `if #available(iOS 26, macOS 26, *)` with a `.ultraThinMaterial` fallback (ARCHITECTURE §6).
   If the call shape is wrong, fix it; if the API is not there at all, delete the `#available`
   branch and keep the fallback, and say so in the log.
2. **`DesignSystem/Tokens/Colors.swift`** — `UIColor(dynamicProvider:)` / `NSColor(name:_:)`
   closures under Swift 6, and the four `NSAppearance.Name` spellings
   (`accessibilityHighContrastAqua` / `…DarkAqua`) that `dynamicContrast` matches on.
3. **`App/GTDApp.swift`** — `.backgroundTask(.appRefresh(_:))` on a `WindowGroup`, the `Settings`
   scene, and the one `#if os(macOS)/#else` that wraps whole scenes (T41 rewrote it; it used to
   be three `#if`s inside a postfix modifier chain).
4. **Global-actor inference in `ViewModifier`s that hold `@Observable` models** —
   `DesignSystem/Interaction/CardSwipeFiling.swift`, `App/RootView.swift`'s `GlobalFlows` and
   `Lifecycle`. They rely on a `ViewModifier` conformance making the whole struct `@MainActor`.
   If that inference does not hold, every one of them errors the same way and the fix is one
   `@MainActor` per struct.
5. **`App/NotificationService.swift`** — `UNUserNotificationCenterDelegate` under strict
   concurrency (`@unchecked Sendable` + a `@MainActor` method hop).
6. **`FeatureInbox/InboxProcessingView.swift`** — `.onKeyPress(characters:phases:)` and
   `KeyPress.modifiers` on macOS, `.sensoryFeedback(.impact(weight:))`, and the two consecutive
   postfix `#if` blocks at the end of `content`'s modifier chain.
7. **`FeatureOverview/OverviewView.swift`** — `NavigationSplitView` three-column init,
   `List(selection:)` + `.tag` in a sectioned sidebar, `.listStyle(.sidebar)`, and
   `@State private var ownedNavigation = OverviewNavigation()` (a `@MainActor` type built in a
   property initialiser).
8. **`FeatureProjects/ProjectViews.swift`** — `OptionArrowShortcut`'s focus-gated
   `.keyboardShortcut`, `List { Section { … } }` mixing header rows with `.onMove` rows.
9. **String/asset catalogs** — the 11 `no rule to process file … xcstrings/assetcatalog`
   warnings are expected under `swift build`; under `xcodebuild` they must compile instead. No
   test asserts on a resolved colour, so a catalog problem must never fail a test.

Four behaviours T41 changed blind and could not run — check them in the app, not just the build:

- Inbox processing shows its **card counter, `⌘Z` undo and `Done`** (its toolbar only renders
  because the two presentation sites now wrap it in a `NavigationStack`).
- Inbox zero shows **`RewardMoment`** — bouncing tray with a green check badge, one haptic.
- Waiting → **"Move to Next" while Next is at the cap** shows the error alert instead of doing
  nothing. Same for un-deferring an item that cannot go to Next.
- Mac: **Settings → vault issues sheet closes** with its `Done` button.

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

Open questions T41 could not settle without a Mac. Nothing here blocks the build; each is a
judgement call someone with the real toolchain (or the user) should make.

**Style guide**

1. `DesignSystem/Components/RewardMoment.swift` uses `.font(.system(size: 56))` for the hero
   symbol. STYLEGUIDE §2.3 says "system text styles only, never `.system(size:)`". Changing it
   blind would change how the only two reward moments in the app look, so it was left alone.
   Decide on a Mac: keep it (and add the exception to §2.3) or move to `.largeTitle` +
   `.imageScale(.large)`.
2. `.sensoryFeedback(.impact(weight:))` is used on both platforms (`CardSwipeFiling`,
   `InboxProcessingView`). If `SensoryFeedback.impact` turns out to be iOS-only, guard those two
   call sites — do not drop the feedback on iOS.
3. `Symbols.checkboxOn/Off` and `Symbols.moveUp/moveDown` are stock SF Symbols with no entry in
   STYLEGUIDE §7's icon map. The map is a vault note, so no agent could edit it; either add the
   four rows there or accept them as stock control affordances.

**Known functional gaps (deliberate, not bugs)**

4. `⌘F` filters only `FeatureOverview`'s own lists. It travels through an **internal**
   `\.overviewQuery` environment value, so `NextView` / `WaitingView` / `ProjectsListView`
   cannot read it. Wiring them means promoting that environment key into `DesignSystem` — a
   shared-file change across four blind files, which T41 judged too risky to do unverified.
5. `⌘⏎`, `⌘⇧N/B/M` and `⌘⇧W` (STYLEGUIDE §4.5) are not in the menu bar: they act on the focused
   row and no feature view exposes a focus target to the shell (T40's decision #2, still open).
6. `FeatureInbox`'s `InboxSessionView` still implements its own drag geometry and fly-out rather
   than `DesignSystem`'s `CardFilingController` + `.cardSwipeFiling`. The GTD semantics
   (`CardTarget`, `KeyMap`, `DragResolver`) are unit-tested here and must stay; only the
   presentation would move. Rewriting a gesture in a file nobody can compile was not worth it —
   do it once the file has built once. The inbox-zero half of that duplication *is* done.
7. `AppComposition.shutdown()` is never called; see its doc comment. Process exit releases the
   security scope, and `scenePhase == .background` is not termination.
8. `FeatureSettings.RoutineTimeRow` seeds `@State` from the routine in `init`, so a routine time
   changed on another device while Settings is open does not move the picker. Harmless; listed
   so it is not mistaken for a sync bug.
9. `VaultIssuesView`'s "Open in Obsidian" builds `obsidian://open?path=<vault-relative path>`.
   That probably needs the vault name or root; the target cannot resolve one by contract.
10. `FeatureProjects`' views materialise their model in `.task` on first appearance. A tap
    between the first render and that task would mutate a throwaway instance (T22's note).
    Watch for it; it should be unreachable in practice.
