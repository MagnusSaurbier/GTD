# T27 — Weekly review wizard (`FeatureReview`)

**Wave 2 · needs T12, T14, T20 (and the public views of T22/T23)**

## Goal

The guided, resumable Mac weekly review.

## Requirements covered

All of §10; I5 (deferred items with reason), P3/P4 (on-hold, someday, stalled), §1 staleness.

## Owns

`Sources/FeatureReview/`, `Tests/FeatureReviewTests/`.

## Public API

```swift
public struct WeeklyReviewView: View { public init(onFinished: @escaping () -> Void) }
public struct ReviewResumeBanner: View { public init(onResume: @escaping () -> Void) }   // shown by the shell when a review is in progress
```

## Deliverables

- `ReviewSession` (`@Observable`, `Codable` state persisted device-locally in Application Support
  → resumable across launches; keyed by ISO week; stale sessions from earlier weeks offer discard/continue).
- Steps:
  1. **Sweep** — (a) inbox to zero: embeds `InboxProcessingView`; (b) items deferred to review,
     each shown **with its reason** → process via the same card + a "system fix" note field
     collected into the review note; (c) waiting-for: chase / bump / resolve per item;
     (d) stalled active projects → add next action (`WhatsNextSheet`) or change status.
  2. **Deck** — card stack (reuse `SwipeCard`): Next (keep / demote), then Backlog and Maybe
     (promote / keep / trash), then on-hold & someday projects (activate / keep / drop).
     Live `CapMeter`; cannot leave the step while Next > cap.
  3. **Systems check** — the prompts from §10.3 as short free-text fields, next to live stats from
     `WeeklyStats` and the **routine audit heatmap** (rows = steps, 7 columns, completion %, trend
     arrow vs last week) from `RoutineAudit`. Heatmap built with plain SwiftUI grid (Swift Charts optional).
  4. **Reflection** — reminder to review the reMarkable journal; the 8 questions with last week's
     "goal for next week" shown alongside (`VaultSnapshot.lastReview`);
     save → `GTDCommand.saveWeeklyReview` → `GTD/Reviews/<yyyy>/KW <ww>.md`.
- Progress rail with per-step completion, keyboard-driven (`⌘→` next step, card keys as in T20).
- Summary screen: what changed this review (processed, demoted, promoted, trashed, projects touched).

## Acceptance

- Unit tests: session persistence/resume, step gating (Next ≤ cap), deck ordering, review note content.
- Previews per step with fixtures.
- `scripts/check.sh` passes.

## Result

_(fill in when done)_
