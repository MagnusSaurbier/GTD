# FeatureSettings

Onboarding, synced settings (contexts, on-the-go subset, Next cap, routine times), device-local
settings (notification toggles, morning time, vault display name) and the vault-issues list.

`docs/STYLEGUIDE.md` is binding, including its §9 checklist.

## Public API

`OnboardingView(onVaultPicked:onFinished:)` (`onFinished` is optional and defaulted — the
shell presents onboarding, so only the shell can take it down; it backs the last step's `Start`
button), `SettingsView(deviceSettings:onChangeVault:)`, `VaultIssuesView()`.

The Contexts section edits differently per platform: iOS uses stock list editing (`Edit` in the
section header → drag handles + delete, swipe for Rename / Remove); macOS keeps the
Up / Down / Rename / remove buttons in each row. Both go through the same `SettingsSession` calls.

Linux-compilable (unit-tested, no SwiftUI):
- `DeviceSettings` — device-local state, `Codable`, including `keyBindings: GTDAppCore.KeyBindings`
  (R-10, N7) — the Mac key rebinds, defaulted to `.defaults`. The Keyboard settings pane (T13)
  edits it through `DeviceSettings.keyBindings` directly; `KeyBindings` itself lives in
  `GTDAppCore` (not here), because `FeatureInbox.KeyMap` and `FeatureReview.ReviewSession` also
  resolve keys through it and neither may depend on this target or on each other (ARCHITECTURE §2).
- `SettingsStore` protocol + `InMemorySettingsStore` / `UserDefaultsSettingsStore` +
  `DeviceSettingsStore` (load/save `DeviceSettings` through an injected store).
- `ContextsEditing` — pure add/rename/remove/reorder/on-the-go-toggle over `GTDConfig`, plus
  `affectedActionCount(for:in:)` for the removal-confirmation count (A4).
- `NextCapPolicy` — the Next-cap stepper's "raised past 15" warning threshold.
- `NotificationKindOption` — mirrors `GTDNotifications.NotificationKind`'s raw values/labels so
  the notification toggles can be built without importing `GTDNotifications` (features depend on
  `GTDAppCore` + `DesignSystem` only). **Keep in sync if `GTDNotifications` renames a kind.**
- `SettingsSession` (`@MainActor @Observable`, wraps `AppModel`) — sends every synced edit as
  `GTDCommand.updateConfig`/`.setRoutineTime`. Same shape as `RoutineRun`/`WaitingListModel`.
- `DayTime.asDate` / `DayTime.init(_:calendar:)` — bridges to `Date` for `DatePicker`.

This target must **not** import `GTDVault`: folder picking returns a plain `URL` that the shell
(the app shell) turns into a `VaultBookmark`.

## Design notes

- Removing/renaming a context only edits `GTDConfig`; it never rewrites existing action
  frontmatter. `affectedActionCount` is shown so the user knows what stays behind (no lying
  defaults — nothing is silently fixed up).
- `VaultIssuesView`'s "Reveal"/"Open in Obsidian" actions only have the vault-relative
  `VaultIssue.path` (no root URL, by contract) — best-effort, documented as a known limitation.

## Platform guards (ARCHITECTURE §5)

`SettingsViews.swift` is wrapped entirely in `#if canImport(SwiftUI)` and was written without a
compiler — **unverified on Apple platforms**, list below. Every other file in this target compiles
and is tested on Linux.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureSettingsTests` — 31 tests (persistence
round-trip incl. `keyBindings`, context editing incl. the affected-action count, `SettingsSession`
against `InMemoryBackend`+`GTDFixtures`, the `DayTime`/`Date` bridge, notification-kind mirror).
`GTDAppCoreTests/KeyBindingsTests` covers the `KeyBindings` model itself (defaults, rebind,
conflicts, reset, Codable, legends).

## Unverified on Apple platforms

`Sources/FeatureSettings/SettingsViews.swift` — `OnboardingView`, `SettingsView`,
`VaultIssuesView`, `RoutineTimeRow`, and their `#Preview`s. Build with Xcode 26 to confirm; likely
risk spots: `.confirmationDialog(presenting:)` + `Binding<String?>`, `NSWorkspace.selectFile`,
and the `#Previewable @State` preview macro usage.
