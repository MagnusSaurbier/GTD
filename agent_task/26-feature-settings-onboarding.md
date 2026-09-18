# T26 — Settings & onboarding (`FeatureSettings`)

**Wave 1 · needs T00**

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

_(fill in when done)_
