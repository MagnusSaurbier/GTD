# T21 — Next view (`FeatureNext`)

**Wave 1 · needs T00**

## Model recommendation

**Difficulty:** Easy–medium · **Recommended model:** Sonnet

A filtered list with chips, badges and row actions over ready-made `Rules` queries; view model is plain and unit-tested. Low risk.

## Goal

The default screen: "what can I do right now?" in one glance.

## Requirements covered

E1, E2, W2 (chase items), D1 badges, A2 (turn-into-project hint), A5, N5.

## Owns

`Sources/FeatureNext/`, `Tests/FeatureNextTests/`.

## Public API

```swift
public struct NextView: View { public init(mode: NextViewMode, onOpen: @escaping (NoteID) -> Void) }
public enum NextViewMode { case full, onTheGo }      // onTheGo = iPhone: hard-filtered to config.onTheGoContexts
```

## Deliverables

- Filter chips on top: context (multi) and time available (single); filters persist per device.
  In `.onTheGo` the context chips only offer the on-the-go set and the hard filter can't be removed.
- Plain list below via `Rules.nextList`: in-progress pinned, then Next; project shown as a label;
  badges for due-soon / overdue / returned-from-defer; "chase" items from overdue follow-ups in
  their own top section with quick actions *bump +7 d* / *resolved*.
- Cap display per STYLEGUIDE §2.2: plain count, turning into an attention badge `15/15` at cap (overdue style above cap). No meter component.
- Tick-off: completes immediately, row disappears with an undo toast (N6). Inline checkbox toggling
  for multi-checkbox actions; completing the last checkbox offers to complete the action.
- Row context menu / swipe actions: start (→ in-progress), demote to Backlog, set waiting (who + date sheet), defer (`DateValueChip`). iOS swipe actions exactly as STYLEGUIDE §3.3: trailing full-swipe `Done`, leading `Backlog`.
- Quick add (Mac `⌘N`, iPhone button) = capture to inbox and jump into processing of that one card (I7) — expose as a callback `onQuickCapture`, don't import `FeatureInbox`.
- The `whatsNext` prompt is **not** presented here — `AppModel.prompt` is handled by the shell. "Turn into project" is an inline button in the detail view (T25), not in rows.
- View model (`NextListModel`) is plain and unit-tested: filtering, sections, ordering, empty states ("nothing fits 10 min at `errands`").

## Acceptance

- Unit tests for the view model incl. on-the-go filtering and chase section.
- Previews for both modes, empty state, at-cap state.
- `scripts/check.sh` passes.

## Result

_(fill in when done)_
