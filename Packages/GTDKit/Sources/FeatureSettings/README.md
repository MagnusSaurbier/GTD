# FeatureSettings

Onboarding, synced settings (contexts, on-the-go subset, Lists — add/rename/remove/favourites,
Next cap, routine times), device-local settings (notification toggles, morning time, vault display
name, Mac key rebinds) and the vault-issues list.

`docs/STYLEGUIDE.md` is binding, including its §9 checklist.

## Public API

`OnboardingView(onVaultPicked:onFinished:)` (`onFinished` is optional and defaulted — the
shell presents onboarding, so only the shell can take it down; it backs the last step's `Start`
button), `SettingsView(deviceSettings:onChangeVault:)`, `VaultIssuesView()`.

The Contexts and Lists sections edit differently per platform: iOS uses stock list editing (`Edit`
in the Contexts header → drag handles + delete, swipe for Rename / Remove; Lists/Favourites use
swipe actions and `onMove`); macOS keeps Up / Down / Rename / Remove buttons in each row. Both go
through the same `SettingsSession` calls. The **Keyboard** section (`SettingsView`'s
`keyboardSection`) is `#if os(macOS)` only — Mac is the only platform with a hardware keyboard to
rebind (STYLEGUIDE §4.5); the model it drives (`KeyBindingsEditing`, `GTDAppCore.KeyBindings`) is
platform-independent and Linux-tested.

Linux-compilable (unit-tested, no SwiftUI):
- `DeviceSettings` — device-local state, `Codable`, including `keyBindings: GTDAppCore.KeyBindings`
  (R-10, N7) — the Mac key rebinds, defaulted to `.defaults`. The Keyboard settings pane edits it
  through `DeviceSettings.keyBindings` directly; `KeyBindings` itself lives in `GTDAppCore` (not
  here), because `FeatureInbox.KeyMap` and `FeatureReview.ReviewSession` also resolve keys through
  it and neither may depend on this target or on each other (ARCHITECTURE §2).
- `SettingsStore` protocol + `InMemorySettingsStore` / `UserDefaultsSettingsStore` +
  `DeviceSettingsStore` (load/save `DeviceSettings` through an injected store).
- `ContextsEditing` — pure add/rename/remove/reorder/on-the-go-toggle over `GTDConfig`, plus
  `affectedActionCount(for:in:)` for the removal-confirmation count (A4).
- `ListsEditing` — the favourites math that stays entirely client-side (L2, R-5, I4b):
  `toggling`/`reordering` over the `[String]` favourites array, `storageLimit` (8, the Mac navbar
  limit — `GTDCommand.setFavouriteLists` itself has no count limit) and `isShownOnPhone(index:)`
  (the first four are what the iPhone navbar actually shows, STYLEGUIDE §3.6). List
  create/rename/remove themselves move a folder, so those go through `SettingsSession` →
  `GTDCommand`/the reducer, not through this type.
- `KeyBindingsEditing` — groups `KeyCommand` by `KeyScreen` for "one row per command, grouped by
  screen" (STYLEGUIDE §4.5), turns a captured character into the `KeyStroke` a rebind is attempted
  with, and wraps `KeyBindings.rebind(_:to:)`'s typed throw as a `Result` so a view can hold the
  outcome as state instead of unwinding a `catch`.
- `SettingsCopy` — wording this target needs beyond `DesignSystem.Copy` (list/favourite/keyboard
  refusals, per-screen and per-command titles), same pattern as `FeatureProjects.ProjectsCopy`.
- `NextCapPolicy` — the Next-cap stepper's "raised past 15" warning threshold.
- `NotificationKindOption` — mirrors `GTDNotifications.NotificationKind`'s raw values/labels so
  the notification toggles can be built without importing `GTDNotifications` (features depend on
  `GTDAppCore` + `DesignSystem` only). **Keep in sync if `GTDNotifications` renames a kind.**
- `SettingsSession` (`@MainActor @Observable`, wraps `AppModel`) — sends every synced edit as
  `GTDCommand.updateConfig`/`.setRoutineTime`/`.createList`/`.renameList`/`.removeList`/
  `.setFavouriteLists`. Same shape as `RoutineRun`/`WaitingListModel`. `favouriteListNames` reads
  the stored choice or the derived default (`Rules.favouriteLists`) without ever writing it —
  only `toggleFavourite`/`reorderFavourites` write (R-5's "never written until the user changes
  something").
- `DayTime.asDate` / `DayTime.init(_:calendar:)` — bridges to `Date` for `DatePicker`.

This target must **not** import `GTDVault`: folder picking returns a plain `URL` that the shell
(the app shell) turns into a `VaultBookmark`.

## Design notes

- Removing/renaming a context only edits `GTDConfig`; it never rewrites existing action
  frontmatter. `affectedActionCount` is shown so the user knows what stays behind (no lying
  defaults — nothing is silently fixed up).
- `VaultIssuesView`'s "Open in Obsidian" goes through `GTDAppCore.ObsidianLink` with
  `\.vaultRootPath` (hidden without a root, i.e. on fixtures). "Reveal" still only passes the
  vault-relative `VaultIssue.path` — best-effort, a known limitation.
- List add/rename refusals (`GTDError.invalid`/`.titleCollision`) show inline in the row/field —
  never an alert (STYLEGUIDE §4.3). **Remove list** is the one exception that still gets a
  `confirmationDialog` despite being undoable, because it takes every item in the list with it
  (ARCHITECTURE §6, R-5) — the dialog names the list and its item count
  (`SettingsSession.itemCount(inList:)`).
- Favourites are one synced list capped at `ListsEditing.storageLimit` (8, the Mac limit); the
  iPhone shows only the first four (`ListsEditing.isShownOnPhone`), marked "Mac only" beyond that
  in the editor rather than modelled as two separate stored lists.
- The Keyboard pane's key-recorder is a single-shot capture (`.onKeyPress`): tapping a row starts
  recording, the next key press attempts the rebind through `KeyBindingsEditing.rebinding` and
  shows the refusal inline under that row — never an alert (STYLEGUIDE §4.5). `Esc`/`Tab`/`⌘Z`/
  `⌘↩` are not `KeyCommand`s, so they never get a row; the section footer names them as fixed.

## Platform guards (ARCHITECTURE §5)

`SettingsViews.swift` is wrapped entirely in `#if canImport(SwiftUI)`; `keyboardSection` and its
helpers are further `#if os(macOS)` inside it. Confirmed compiling (zero warnings) with Xcode 27
for both `platform=macOS` and `generic/platform=iOS Simulator` (T13). The Keyboard pane's rendering
(grouping, key legends) was confirmed on screen on fixtures; the Lists/Favourites section was not
driven on screen in the same session — see `TEST-INSTRUCTIONS.md`/T15.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureSettingsTests` — 73 tests (persistence
round-trip incl. `keyBindings` and its reset, context editing incl. the affected-action count,
list add/rename/remove incl. every refusal, favourites toggle/reorder/limit/derived-default,
key-binding grouping/capture/rebind wrapping, `SettingsCopy` wording, `SettingsSession` against
`InMemoryBackend`+`GTDFixtures`, the `DayTime`/`Date` bridge, notification-kind mirror).
`GTDAppCoreTests/KeyBindingsTests` covers the `KeyBindings` model itself (defaults, rebind,
conflicts, reset, Codable, legends).

## Unverified on Apple platforms

`Sources/FeatureSettings/SettingsViews.swift` — the Lists/Favourites sections and their
`confirmationDialog`/inline-refusal flows were not clicked through on a device or simulator in
this session (only the Keyboard pane's rendering was); `RoutineTimeRow` and the onboarding steps
remain as before. Risk spots: `.confirmationDialog(presenting:)` + `Binding<String?>` (used again
for list removal), `Menu` inside a `Form` `Section` (the "Add favourite…" picker), and
`.onKeyPress` inside a `Form` row (the key recorder) — T15 should drive both sections on screen.
