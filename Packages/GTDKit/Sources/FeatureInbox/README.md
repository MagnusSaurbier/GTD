# FeatureInbox

Inbox processing: one card at a time, LIFO, forced order, exit only by quitting (I1–I7).
Owned by **T20**. `docs/STYLEGUIDE.md` §3.5/§3.6 is the binding spec for the card and its gestures.

## Public API

- `InboxProcessingView(onFinished:)` — the whole session. `FeatureReview` embeds it (§10.1).
- `InboxStartButton(action:)` — home-screen entry point with the live queue count.

Linux-compilable (this is where all the logic lives, and all of it is unit-tested):

- `InboxSession` — `@MainActor @Observable`. Queue, `draft`, `sheet`, counter, validation,
  cap choice, every sub-flow, undo. Views own no decisions; they call `choose(_:)`,
  `confirm*(...)`, `demoteAndRetry(_:)`, `sendToBacklogInstead()`, `undo()`.
- `CardTargets.swift` — `CardTarget` (the 8 targets with key, swipe, symbol, title),
  `SwipeDirection`, `DragResolver` (axis lock, thresholds, commitment), `KeyMap` (Mac keys).
  The **single** definition of the swipe/key map (ARCHITECTURE §6).
- `InboxPickers.swift` — `KnowledgeTree`, `ProjectPicker`, `InboxDefaultsStore`
  (device-local last-used folder + one-time hint; `EphemeralInboxDefaults` for tests).
- `InboxCopy.swift` — inbox-only strings (the shared ones stay in `DesignSystem.Copy`) and
  `ChecklistText` (checklist toggling, `- ` auto-format, title derivation).

## Invariants

- Nothing is pre-filled and no suggestion is ever persisted: the last-used knowledge folder and
  the +7 d follow-up are **suggested** chips until the user taps them (§1, STYLEGUIDE §3.1).
- Next/Backlog require a non-empty `What?`; the card shakes and focuses the field — never an alert.
- The cap is a **forced choice**: demote a Next item or send this card to Backlog. Never automatic.
- Undo returns the card to the head of the queue **with its draft restored**.
- A card being edited is never displaced by a mid-session capture; the capture is queued next.
- Items deferred to the weekly review leave the queue and never come back to it (I5).

## Platform guards (ARCHITECTURE §5)

`InboxProcessingView.swift`, `InboxCardView.swift`, `InboxSheets.swift` and `InboxPreviews.swift`
are wrapped entirely in `#if canImport(SwiftUI)` and were written **without a compiler** — verify
them on a Mac (`scripts/check.sh`). Previews build their own sample data (`InboxPreviewData`).

`InboxProcessingView` carries its own `.toolbar` (card counter, `⌘Z` undo, `Done`) but **does
not** wrap itself in a `NavigationStack`: the review wizard embeds it inline, where a second
navigation bar would be wrong. Every other presenter must supply one, or the session has no
visible way out — `PhoneShell` and `FeatureOverview` do (T41 fixed both; only the previews had
one before).

Inbox zero is `DesignSystem.RewardMoment.inboxZero`, not a local drawing of it (STYLEGUIDE §5
allows exactly two reward moments, so there is exactly one implementation). The card drag
geometry is still local (`DragResolver` + the gesture in `InboxProcessingView`) rather than
`DesignSystem`'s `CardFilingController`/`.cardSwipeFiling` — see
`docs/history/build-out/ORCHESTRATOR-NOTES.md`.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureInboxTests` (49 tests).
