# T30 — Capture: Shortcuts & App Intents (`GTDIntents`, `Shortcuts/`)

**Wave 2 · needs T15 (`InboxWriter`, `VaultBookmark`)**

## Model recommendation

**Difficulty:** Medium · **Recommended model:** Sonnet

Half documentation (the Shortcut recipe), half small App Intents with a fake-writer test suite. One platform subtlety to verify on device: resolving the security-scoped bookmark from a background intent without launching the app — flag it in Result for T40/T41 rather than guessing.

## Goal

Capture in under 3 seconds without Obsidian or the app running, by text and by voice.

## Requirements covered

§3: C1, C2, C3 (C4 is out of scope), R3 (start routine via Shortcut).

## Owns

`Sources/GTDIntents/`, `Tests/GTDIntentsTests/`, `Shortcuts/`.

## Deliverables

Two capture paths — ship both, recommend A as the default because it has zero dependency on our app:

- **A. Pure Shortcut recipe** (`Shortcuts/README.md`, step-by-step with screenshots-as-text, since
  `.shortcut` files can't be authored from code): *Ask for Input / Dictate Text* → *Format Date*
  (`yyyy-MM-dd HHmmss`) → *Text* (frontmatter `created:` + body) → *Save File* to
  `<vault>/Inbox/<date>.md` (no "ask where to save", no overwrite). Variants: text (Mac global
  hotkey, iPhone home screen / Back Tap), voice (Action Button → Dictate Text, C2). Include the
  exact file template so it matches `NoteCodec.decodeInboxItem`, and troubleshooting
  (iCloud folder permission prompt, evicted `Inbox/` folder).
- **B. App Intents** (run in the background, `openAppWhenRun = false`):
  `CaptureToInboxIntent(text:)` using `InboxWriter` + the persisted bookmark — must not load or
  index the vault; `StartRoutineIntent(routine:)` (opens the app at the runner via `gtd://routine/<id>`);
  `ProcessInboxIntent` (opens processing). `AppShortcutsProvider` with phrases; parameter summary;
  dialog result "Captured."
  Failure modes return a useful spoken/visible error (no vault picked yet, bookmark stale).
- Optional if trivial: interactive Control Center / Lock Screen control (`ControlWidget`) that runs `CaptureToInboxIntent`. Skip if it needs a widget extension the project doesn't have yet — note it for T40 instead.

## Acceptance

- Unit tests for the intent logic with a fake writer (file name format, collision on two captures in the same second, empty text rejected, whitespace trimmed, multi-line kept).
- Files produced by both paths decode with `NoteCodec.decodeInboxItem` (test with literal strings from the README template).
- README states measured/expected latency for both paths and how the user verifies C1's 3-second target.
- `scripts/check.sh` passes.

## Result

**Status: done.** `scripts/check.sh` passes (build clean, 523 tests pass, docs check ok,
`xcodebuild` step correctly `SKIPPED` on Linux).

### What was built

- **Linux-testable pipeline** (`Sources/GTDIntents/`): `CaptureRequest` (normalise → stamp →
  route to `GTDVault.InboxWriter`, unchanged from T00's stub except typed-throws error mapping),
  `CaptureError` (`.emptyText`, `.noVaultSelected`, `.bookmarkStale`, `.writeFailed(String)`, now
  `LocalizedError` so a thrown one is a usable spoken/visible message on its own — acceptance
  bullet 3), `CaptureStamp` (unchanged). New: `RoutineDeepLink`/`InboxDeepLink` (build the
  `gtd://routine/<id>` / `gtd://inbox` strings, `DeepLinks.swift`) and `PendingRoute` +
  `PendingRouteStore`/`InMemoryPendingRouteStore`/`UserDefaultsPendingRouteStore`
  (`PendingRoute.swift`) — the hand-off `StartRoutineIntent`/`ProcessInboxIntent` use to tell the
  app where to navigate once foregrounded (see Gotchas).
- **App Intents shell** (`CaptureIntents.swift`, `#if canImport(AppIntents)`, compiled blind):
  `CaptureToInboxIntent(text:)` (`openAppWhenRun = false`, dialog "Captured.", errors surface via
  `CaptureError.errorDescription`), `StartRoutineIntent(routine:)` and `ProcessInboxIntent`
  (`openAppWhenRun = true`, both set a `PendingRoute`), `GTDAppShortcuts: AppShortcutsProvider`
  with phrases/short titles/symbols for all three. No `AppEntity` and no `ControlWidget` — see
  Deviations.
- **Tests** (`Tests/GTDIntentsTests/`, 21 tests, replacing T00's placeholder): `CaptureRequestTests`
  (normalisation, file-name format, same-second collisions, multi-line body, empty-text rejection
  before touching the writer, error mapping incl. the stale-bookmark gotcha below, every
  `CaptureError` has a non-empty message), `DeepLinkTests`, `PendingRouteTests`,
  `CaptureCodecRoundTripTests` (gated on a local `codecIsImplemented` probe, mirroring
  `GTDVaultTests` — currently self-skips since T10 hasn't landed; pins both the App-Intents path's
  output and the Shortcut recipe's literal template to `NoteCodec.decodeInboxItem`).
- **`Shortcuts/README.md`**: Recipe A (pure Shortcut: Ask for Input/Dictate Text → Format Date
  ×2 → Text → Save File, exact action settings, the literal file template, Mac/iPhone
  hotkey/home-screen/Back-Tap/Action-Button variants, iCloud-permission and evicted-folder
  troubleshooting) and Recipe B (the three App Intents, when to prefer each). A latency section
  states the expected budget (~1 s / ~1.5 s) and how to stopwatch-verify C1's 3-second target on
  a real device, since neither path can be timed from this Linux container.

### Contract changes

- **`Package.swift`** (test-only): added `GTDVault` and `GTDMarkdown` to `GTDIntentsTests`'
  dependencies (was `["GTDIntents", "GTDFixtures"]`). Needed so the test target can exercise
  `CaptureRequest` against `InboxWriter` + `InMemoryFileSystem` (the "fake writer" the brief asks
  for — both live in `GTDVault`, already a *production* dependency of `GTDIntents`, but a
  separate test target needs its own `import`) and can call `NoteCodec.decodeInboxItem` for the
  round-trip tests. `GTDIntents`'s own production dependencies are unchanged
  (`["GTDModel", "GTDVault"]`); the ARCHITECTURE §2 module graph is unaffected.

### Deviations

- **No `AppEntity` for routines.** `StartRoutineIntent.routine` is a plain `String` (matched
  against the routine's title/filename stem), not an `AppEntity` with a live `EntityQuery`,
  because that would need the intent to query the loaded vault/backend — out of `GTDIntents`'s
  dependency reach (`GTDModel`, `GTDVault` only) and unverifiable blind. Acceptable given R1 names
  only two routines today; flagged if T40/a later task wants the nicer Shortcuts picker.
  `ProcessInboxIntent` and `CaptureToInboxIntent` need no entity either.
  - **No `ControlWidget`.** Skipped per the brief's own escape hatch: it needs a separate widget
    extension target, which `project.yml` doesn't declare. Noted for T40.

### Files unverified on Linux (no Xcode here)

`Sources/GTDIntents/CaptureIntents.swift` in full (`CaptureToInboxIntent`, `StartRoutineIntent`,
`ProcessInboxIntent`, `GTDAppShortcuts`) — standard, well-known `AppIntents` APIs only
(`AppIntent`, `@Parameter`, `ParameterSummary`/`Summary`, `IntentDialog`, `ProvidesDialog`,
`AppShortcutsProvider`/`AppShortcut`), no iOS-26-only or exotic API guessed at. Verify with
`brew install xcodegen && scripts/check.sh --app` on a Mac, then build a Shortcut per
`Shortcuts/README.md` and time it on a device.

### Gotchas for T40/T41

1. **`CaptureError.bookmarkStale` is currently unreachable through `InboxWriter`.**
   `GTDVault.VaultBookmark.startAccess()` does `try? resolve()`, so a stale/corrupt bookmark and a
   never-picked one both surface as `VaultError.noVaultSelected` — confirmed by
   `aStaleBookmarkCurrentlySurfacesAsNoVaultSelectedToo`. `CaptureError.noVaultSelected`'s message
   is worded to cover both causes; `.bookmarkStale` is kept in case `GTDVault` starts
   distinguishing them later. Not a bug I could fix here (GTDVault is T15's, frozen for T30).
2. **`PendingRoute` needs a consumer.** `StartRoutineIntent`/`ProcessInboxIntent` have
   `openAppWhenRun = true` but no built-in way to hand the app a navigation target (no separate
   App Intents extension in this project, so the intent runs in-process but may finish before any
   SwiftUI scene subscribes to anything). They persist the target via
   `PendingRoute().set(...)` (`UserDefaults`-backed by default). **T40 must call
   `PendingRoute().consume()` on launch and on every foreground** and route on the result the same
   way it already routes a `gtd://` URL from `onOpenURL`/`NotificationRoute`. `"gtd://inbox"`
   (from `ProcessInboxIntent`) is not a `NotificationRoute` case today — T40 should either add one
   or special-case it.
3. **`RoutineDeepLink` assumes `VaultLayout.default`** for the routine's path, since the intent
   must not load the live `GTDConfig`. A customised `routines` folder produces a path that won't
   resolve directly; fall back to matching by title.
4. **On-device subtlety flagged, not guessed at:** whether `CaptureToInboxIntent` can resolve the
   security-scoped bookmark and write while the app is fully suspended (`openAppWhenRun = false`,
   no separate extension target) is unverified here. If it turns out the OS won't run it without
   at least a brief launch, `openAppWhenRun` may need to flip to `true` for this intent, and
   Shortcuts recipe A stays the only truly app-free capture path (already the default for exactly
   this reason).

### Commits

Two commits on this branch: the Wave 1 fast-forward merge (`git merge --ff-only
claude/sharp-volta-p59pxh`, unchanged files, not authored by me) and `T30: capture pipeline, App
Intents shell, Shortcuts recipes`.
