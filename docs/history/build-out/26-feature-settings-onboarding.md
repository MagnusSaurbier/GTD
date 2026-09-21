# T26 — Settings & onboarding (`FeatureSettings`)

**Wave 1 · needs T00**

## Model recommendation

**Difficulty:** Easy · **Recommended model:** Sonnet

Forms, a folder picker returning a `URL`, and a Codable settings struct. No GTD semantics, no file access. The simplest feature task.

## Goal

First-run vault selection and the few settings the requirements call for.

## Requirements covered

N2 (choose vault), A4 (contexts editable, on-the-go set configurable), R3 (routine times), D2 (notification toggles), ARCHITECTURE §3 layout.

## Owns

`Sources/FeatureSettings/`, `Tests/FeatureSettingsTests/`.

## Public API

```swift
public struct OnboardingView: View { public init(onVaultPicked: @escaping (URL) -> Void) }   // URL handed to the shell → VaultBookmark (T15/T40)
public struct SettingsView: View { public init(deviceSettings: Binding<DeviceSettings>, onChangeVault: @escaping () -> Void) }
public struct VaultIssuesView: View { public init() }
public struct DeviceSettings: Codable, Equatable, Sendable { … }   // device-local: notification toggles, morning time, last-used knowledge folder
```
This feature must **not** import `GTDVault`; folder picking returns a plain `URL`.

## Deliverables

- **Onboarding:** explain what to pick (the vault root containing `Actions/`), folder picker
  (`fileImporter` with `.folder`), validation preview (found N actions, N projects, Inbox folder
  present?) via a closure supplied by the shell, notification permission step, hint to install the capture Shortcut (links to `Shortcuts/README.md` content).
- **Settings (synced, via `updateConfig`):** contexts list — add / rename / remove / reorder
  (removing a context in use shows the affected count and requires confirmation); on-the-go subset;
  Next cap (default 15, stepper with a warning when raised); routine times (`GTDCommand.setRoutineTime`).
- **Settings (device-local):** notification kinds on/off, morning time, vault location + "Change vault…".
- **VaultIssuesView:** list of `snapshot.issues` with path, message, "Reveal in Finder/Files", "Open in Obsidian".
- About: version, link to requirements doc.

## Acceptance

- Unit tests: context rename/remove impact computation, `DeviceSettings` persistence round trip.
- Previews: onboarding steps, settings, issues list.
- `scripts/check.sh` passes.

## Result

**Status: done.**

### What was built

- **Linux-compilable (unit-tested):**
  - `DeviceSettings` (extended T00's stub with `vaultDisplayName: String?` — a friendly label for
    the picked vault, set by the shell; needed so `SettingsView` can show a "Vault" row without
    importing `GTDVault`).
  - `SettingsStore` protocol + `InMemorySettingsStore` (thread-safe, `NSLock`-backed) +
    `UserDefaultsSettingsStore` + `DeviceSettingsStore` (load/save `DeviceSettings`, falling back
    to `.default` on a missing or corrupt record — never a partial guess).
  - `ContextsEditing` — pure add/rename/remove/reorder/on-the-go-toggle over `GTDConfig`, plus
    `affectedActionCount(for:in:)` for the removal-confirmation count (A4). Renaming/removing only
    edits the config lists; existing action frontmatter is never rewritten silently.
  - `NextCapPolicy` (raised-above-15 warning threshold), `NotificationKindOption` (mirrors
    `GTDNotifications.NotificationKind`'s raw values/labels so the toggle section can be built
    without importing `GTDNotifications` — features depend on `GTDAppCore`+`DesignSystem` only).
  - `SettingsSession` (`@MainActor @Observable`, wraps `AppModel`, same shape as
    `RoutineRun`/`WaitingListModel`) — sends every synced edit as `GTDCommand.updateConfig` /
    `.setRoutineTime`, so it is testable end-to-end against `InMemoryBackend`+`GTDFixtures`.
  - `DayTime.asDate` / `DayTime.init(_:calendar:)` — bridges to `Date` for `DatePicker`.
- **Blind SwiftUI** (`SettingsViews.swift`, fully guarded, unverified — see below):
  `OnboardingView` (4 steps: explain+pick, validation preview, notification permission, capture
  Shortcut hint), `SettingsView` (Form: contexts list with rename/remove/reorder + confirmation,
  on-the-go `ContextChipGroup`, Next-cap stepper with warning, per-routine time toggle, device
  notification toggles + morning time, vault row + "Change vault…", About), `VaultIssuesView`
  (list + best-effort "Reveal"/"Open in Obsidian"). Previews for light/dark/AX1 on every screen.
- 30 unit tests across 5 suites (persistence round trip incl. corrupt/missing records, context
  editing incl. impact count, `SettingsSession` against a real `AppModel`, the `DayTime`/`Date`
  bridge, the notification-kind mirror).

### Deviations from the brief's literal wording

- "Validation preview... via a closure supplied by the shell": the frozen `OnboardingView` init
  has only `onVaultPicked`. Implemented the preview by reading `@Environment(AppModel.self)` after
  `onVaultPicked` fires (same pattern `SettingsView` already used) instead of a second closure
  parameter, since the public API in the brief is pinned to one parameter and ARCHITECTURE §5
  already routes all feature data through `AppModel`/environment.
- "link to requirements doc" (About) and the Shortcut-install link: neither a stable URL nor a
  bundled copy of `docs/REQUIREMENTS.md`/`Shortcuts/README.md` exists yet, so both are short
  static in-app text instead of a working hyperlink.
- Task-dispatch text mentioned wiring the picker through `GTDVault.VaultBookmark`; the brief's own
  "Public API"/"Deliverables" sections and ARCHITECTURE §2 are explicit that `FeatureSettings`
  must not import `GTDVault`, so the picker stays a plain `fileImporter` returning a `URL` — the
  brief and ARCHITECTURE take precedence, followed here.

### Contract changes

None — `Package.swift` and ARCHITECTURE §4 untouched. Noticed but did **not** fix (shared,
frozen file; affects every Wave-1 UI target equally, not specific to this task): the blind
`#Preview` blocks T00 wrote for every `Feature*` target (including this one) `import GTDFixtures`
in the main (non-test) source file, but `featureDeps` in `Package.swift` does not list
`GTDFixtures` as a dependency of any `Feature*` target — only its test target gets it. This is
invisible on Linux (the whole file, imports included, is compiled out by `#if canImport(SwiftUI)`
being false) but will very likely fail `import GTDFixtures` under Xcode. Whoever next touches
`Package.swift` (T40, or a docs-handover pass) should add `"GTDFixtures"` to `featureDeps`.

### Files unverified on Linux

`Sources/FeatureSettings/SettingsViews.swift` in full (`OnboardingView`, `SettingsView`,
`VaultIssuesView`, `RoutineTimeRow`, all `#Preview`s) — wrapped in `#if canImport(SwiftUI)`,
written without a compiler. Everything else in the target (`DeviceSettings.swift`,
`SettingsStore.swift`, `ContextsEditing.swift`, `NextCapPolicy.swift`,
`NotificationKindOption.swift`, `SettingsSession.swift`, `DayTimeBridge.swift`) is plain Foundation
and is built + unit-tested on Linux by `scripts/check.sh`.

### Open issues for the user to check on a Mac

- `VaultIssuesView`'s "Reveal"/"Open in Obsidian" only have `VaultIssue.path` (vault-relative, no
  root URL — by contract this target can't resolve one). "Reveal" is `NSWorkspace` on macOS only
  (no-op on iOS); "Open in Obsidian" builds `obsidian://open?path=<relative path>`, which likely
  needs the vault root or vault name to actually work. If that's not good enough in practice, it
  needs a small contract addition (e.g. handing this view a resolved root URL or vault name).
- `.confirmationDialog(_:isPresented:presenting:actions:message:)` and the two-parameter
  `.onChange(of:) { old, new in }` closures are iOS17+/macOS14+ APIs; should compile fine at the
  iOS 26/macOS 26 floor but were never run through a compiler here.
- `GTD.xcodeproj`/`xcodebuild` steps were not run (no Xcode in this container);
  `scripts/check.sh` prints `SKIPPED: xcodebuild not available (Linux)`.

### `scripts/check.sh` output (tail)

```
=== docs check
checking backticked paths in CLAUDE.md README.md
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok

=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's
build system only — verify this step on a Mac.

=== check.sh finished
```

`swift build` and `swift test` (full suite, all targets) both passed with no errors — only the
expected 11 `no rule to process file` xcstrings/xcassets warnings.
