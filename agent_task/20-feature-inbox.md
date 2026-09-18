# T20 — Inbox processing (`FeatureInbox`)

**Wave 1 · needs T00 · develop against `InMemoryBackend` + fixtures**

## Goal

The clarify flow: one card at a time, forced LIFO, swipe on iPhone, keys on Mac.

## Requirements covered

All of §4 (I1–I7), A3 cap behaviour, W1, N6 (undo last card). Decisions: ARCHITECTURE §6.

## Owns

`Sources/FeatureInbox/`, `Tests/FeatureInboxTests/`.

## Public API

```swift
public struct InboxProcessingView: View { public init(onFinished: @escaping () -> Void) }   // full session
public struct InboxStartButton: View { public init(action: @escaping () -> Void) }          // shows queue count
```
`FeatureReview` embeds `InboxProcessingView` for "inbox to zero".

## Deliverables

- `InboxSession` (`@Observable`, unit-testable, no SwiftUI): queue from `Rules.inboxQueue`, current
  card draft (edited text, why, what, contexts, time bucket, optional defer/due/project), counter
  "3 of 14 left", exit only via quit. New captures arriving mid-session go on top (LIFO).
- Card: editable raw text, **Why?**, **What?** (multi-line; checklist allowed), chips for
  context(s) and time bucket, optional `DateChip`s and project chip. Nothing pre-filled (§1).
  Title for the action note is derived from the first line of *What?* (editable before filing).
- Targets defined once in `CardTargets.swift`: swipe → Next, ← Backlog, ↑ Maybe, ↓ Trash; buttons
  Knowledge, Project, Waiting, Defer-to-review; Mac keys `N B M T K P W R`, `⌘Z` undo, `⎋` quit.
  Validation before leaving: Next/Backlog require a non-empty *What?*.
- Sub-flows (sheets):
  - **Knowledge**: category list + free browsing/creating folders in the `knowledgeFolders` tree, last used preselected (device-local), editable title.
  - **Project**: pick existing (grouped by area) or create new (title, area pick/create, outcome, why), then define first next action(s) → `.newProject` / `.existingProject`.
  - **Waiting**: `GTDDesign.WaitingInfoSheet` (who + follow-up date, default +7 d, both required).
  - **Defer to review**: reason required.
  - **Cap reached** (on `GTDError.nextCapReached`): list current Next items to demote one, or send the card to Backlog. No automatic choice.
- Undo last card → `AppModel.undo()` and the card returns with its draft restored.
- Empty state ("Inbox zero") and session summary (processed count per target).

## Acceptance

- `InboxSession` unit tests: LIFO order, no skipping, counter, mid-session capture, validation, cap flow, undo restores draft, deferred-to-review items never appear.
- Previews: iPhone card, Mac card with key legend, each sheet, empty state.
- VoiceOver: every target reachable as a custom action.
- `scripts/check.sh` passes.

## Result

_(fill in when done)_
