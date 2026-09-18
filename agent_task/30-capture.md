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

_(fill in when done)_
