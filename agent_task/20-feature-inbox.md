# T20 — Inbox processing (`FeatureInbox`)

**Wave 1 · needs T00 · develop against `InMemoryBackend` + fixtures**

## Model recommendation

**Difficulty:** Medium–hard (largest Wave-1 feature) · **Recommended model:** Sonnet — borderline

Very explicitly specified, runs entirely on the in-memory backend (no data risk), and the tricky logic lives in `InboxSession`, which is unit-tested without SwiftUI. That makes it Sonnet-feasible. It is borderline because of sheer surface (card + 5 sub-flows + swipe/keyboard parity + undo restoring the draft) and because it is the UX centrepiece. Run Sonnet at high effort; if the first result cuts corners on the sub-flows or the cap/undo paths, hand the remainder to Opus rather than iterating.

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
  context(s) and time bucket, optional value chips `+ defer` `+ due` `+ project`. A second checkbox in *What?* shows the inline `Turn into project` button (→ Project flow). Nothing pre-filled (§1).
  Title for the action note is derived from the first line of *What?* (editable before filing).
- Targets defined once in `CardTargets.swift`: swipe → Next, ← Backlog, ↑ Maybe, ↓ Trash; buttons
  Project, Knowledge, Waiting; `⋯` menu → Defer to review. Mac: arrow keys for the four swipe targets,
  `P K W R`, `⌘Z` undo, `Esc` quit, `1…8` contexts, `⇧1…⇧4` time bucket (only when no field is focused).
  **STYLEGUIDE §3.5–§3.6 is the full spec** (card content order, drag thresholds, axis lock, tints, swipes disabled
  while a field is focused, shake-instead-of-alert validation, action bar, key legend, counter) — follow it exactly.
  Validation before leaving: Next/Backlog require a non-empty *What?*.
- Sub-flows (sheets):
  - **Knowledge**: category list + free browsing/creating folders in the `knowledgeFolders` tree, last used preselected (device-local), editable title.
  - **Project**: pick existing (grouped by area) or create new (title, area pick/create, outcome, why), then define first next action(s) → `.newProject` / `.existingProject`.
  - **Waiting**: `DesignSystem.WaitingInfoSheet` (who + follow-up date both required; +7 d appears as a *suggested* chip the user must confirm).
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

**Status: done.** All five sub-flows, both input styles, the cap choice and undo are implemented;
`scripts/check.sh` passes with 49 `FeatureInboxTests` (119 in the package).

### What was built

**Linux-compilable (all logic, all tested):**

- `InboxSession` — `@MainActor @Observable`. LIFO queue from `Rules.inboxQueue`, `draft`
  (text/why/what/title/contexts/time/defer/due/project), `sheet`, counter, `validation`,
  `capCandidates`, per-target session summary, `elapsedMinutes`. One entry point `choose(_:)` for
  swipe, key and VoiceOver action alike; `confirmKnowledge/Waiting/NewProject/ExistingProject/
  DeferToReview`, `demoteAndRetry(_:)`, `sendToBacklogInstead()`, `cancelSheet()`, `undo()`.
- `CardTargets.swift` — `CardTarget` (8 targets: key, swipe, symbol, `title`, `requiresWhat`,
  `undoToastLabel`, `keyLegend`), `SwipeDirection`, `DragResolver` (axis lock, thresholds,
  `commitment`, `lockedTranslation`), `KeyMap` (`P K W R`, `1…8`, `⇧1…⇧4`, `⌘Z`, `Esc`).
- `InboxPickers.swift` — `KnowledgeTree` (folder tree incl. materialised parents + in-sheet
  folder creation), `ProjectPicker` (grouping by area, ungrouped first and headerless;
  `statusForFirstAction`), `InboxDefaultsStore` / `InboxDefaults` / `EphemeralInboxDefaults`
  (device-local last-used folder and one-time hint flag — never in the vault).
- `InboxCopy.swift` — inbox-only strings (shared ones stay in `DesignSystem.Copy`), the capture
  timestamp wording, and `ChecklistText` (checklist toggle, `- ` auto-format, title derivation).

**SwiftUI (blind):** `InboxProcessingView` + `InboxStartButton` (unchanged signatures),
`InboxSessionView` (card stack with peek, drag with tint + destination label, iPhone glass action
bar with `⋯` menu, Mac key legend + `onKeyPress` map, counter in the toolbar, `⌘Z`, undo toast,
inbox-zero reward moment with the session summary), `InboxCardView` (STYLEGUIDE §3.5 content
order, `Turn into project` on the second checkbox, shake-on-validation, all 8 targets as
`accessibilityActions`), `InboxSheets.swift` (Knowledge / Project / Defer to review / `Next is
full` / full raw text; Waiting uses `DesignSystem.WaitingInfoSheet`), `InboxPreviews.swift`
(card light/dark/AX1, filled-in card, every sheet, inbox zero, start button).

### Deviations (and why)

1. **The title field is a sixth element on the card**, between `What?` and the chips. STYLEGUIDE
   §3.5 fixes five; the brief requires the derived title to be editable before filing. It only
   appears once a title can be derived, in `Typo.meta` + `Typo.body`. Style guide vs brief
   disagreement, reported per ARCHITECTURE §5.
2. **A mid-session capture does not displace a card that is being edited.** It goes on top when
   the draft is pristine (literal LIFO) and directly behind the current card otherwise, so a typed
   draft is never lost. Both behaviours are tested.
3. **Raw-text edits are persisted with `.editInboxText` right before filing**, because Knowledge
   moves the capture file itself and Trash moves it as is. Cost: that edit is a separate undo step
   (the single-level `InMemoryBackend` undo reverts the filing, not the edit).
4. **First actions of the project sub-flow** default to `next` for an active project and `backlog`
   otherwise (P3), instead of asking. The cap flow catches a refusal either way.
5. **The undo toast wording** comes from `CardTarget.undoToastLabel` (`Moved to Backlog`,
   STYLEGUIDE §6.3), not from `AppModel.undoLabel` (`Filed to Next`). Both exist.
6. `.buttonStyle(.borderedProminent)` instead of `.glassProminent`, following T00's decision to
   defer Liquid Glass to T12 (ARCHITECTURE §6).
7. The `What?` checklist control is a **text** button: no icon-map entry exists for it and §7
   forbids inventing symbols. `⋯` is `InboxSymbols.more`, documented as a stock control affordance.

### Contract changes

None. `Package.swift`, `docs/ARCHITECTURE.md` and `CLAUDE.md` are untouched; the public API is
exactly what T00 declared. `CardTarget`/`DragResolver` only gained additive members.

### Open issues for the orchestrator

- **Seven other feature targets will not build on a Mac**: `FeatureNext`, `FeatureProjects`,
  `FeatureWaiting`, `FeatureRoutines`, `FeatureOverview`, `FeatureSettings` and `FeatureReview`
  still `import GTDFixtures` in their `#if canImport(SwiftUI)` preview code, but `featureDeps` in
  `Package.swift` is `["GTDAppCore", "DesignSystem"]` only. Linux never sees it because the files
  are compiled out. `FeatureInbox` was fixed locally (`InboxPreviewData`); the others need either
  the same fix or one `Package.swift` edit — an orchestrator call, since that file is frozen.
- `InMemoryBackend` undo is single-level, so "demote, then file" is only undoable one step deep.
  T16's journal should make the pair one undo unit.
- **Merge follow-up with T12.** This worktree was based on the T00 commit; T12 has since landed
  `DesignSystem/Interaction/CardDragGeometry.swift`, `CardFilingController.swift`,
  `CardSwipeFiling.swift` and `RewardMoment.swift`, which cover the same drag geometry and the
  inbox-zero moment that `InboxCardView`/`InboxSessionView` implement locally. They are
  compatible (both read `DragThresholds`, and T12's file explicitly keeps `CardDragGeometry`
  distinct from `FeatureInbox.SwipeDirection`), but they are duplication: after the merge,
  `InboxSessionView` should adopt `.cardSwipeFiling(controller:isEnabled:onFile:)` and
  `RewardMoment`, keeping `CardTarget`/`KeyMap`/`DragResolver`'s *semantics* here. Coding against
  that API was not possible in this worktree — those files do not exist in it, so nothing could
  have been compiled or tested against them.
  Everything else T20 uses from the merged `DesignSystem`, `Rules` and `Reducer` was checked
  against the updated branch and is source-compatible (`Chip`, `ContextChipGroup`,
  `TimeBucketChipGroup`, `DateValueChip`, `ItemCard`, `GlassActionBar`, `UndoToast`,
  `WaitingInfoSheet`, `ActionRow`, `Badge`, the colour tokens, `Rules.inboxQueue/nextList/
  signals/countsTowardCap`).

### Files that could not be compiled on Linux (verify on a Mac)

`Sources/FeatureInbox/InboxProcessingView.swift`, `InboxCardView.swift`, `InboxSheets.swift`,
`InboxPreviews.swift` — everything inside `#if canImport(SwiftUI)`.
Check with `scripts/check.sh` (the `xcodebuild` step) on a Mac with Xcode 26. Most likely
breakages, in order: `.onKeyPress(characters:phases:)` + `KeyPress.modifiers` on macOS;
`.sensoryFeedback(.impact(weight:), trigger:)`; `OutlineGroup(_:children:)` inside a `Form`
section in `KnowledgeSheet`; `#if` inside the modifier chains of `content` and `card`;
`ContentUnavailableView`'s three-closure initialiser in `InboxZeroView`.

### `scripts/check.sh`

```
=== swift build (Packages/GTDKit)
Build complete! (1.44 secs)
=== swift test (Packages/GTDKit)
Build complete! (2.59 secs)
... ✔ Test run with 49 tests in 3 suites passed after 0.016 seconds.   (FeatureInboxTests)
... all 18 test targets pass
=== docs check
checking backticked paths in CLAUDE.md README.md
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok
=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build system only — verify this step on a Mac.
=== check.sh finished
```

### Gotchas worth keeping

1. Put nothing in the views: `InboxSession` is driven through `AppModel` + `InMemoryBackend` and
   is the only place a decision is made. That is what made every sub-flow testable without Xcode.
2. A suggestion is UI state. `suggestedKnowledgeFolder` and the +7 d follow-up never reach a
   `GTDCommand` until the user confirms them.
3. `Rules.inboxQueue` already excludes `reviewReason != nil`; the session never re-adds them.
4. `AppModel.send` throws `GTDError` — the cap case must reach `InboxSession.handle`, or the
   forced choice silently turns into a lost card.
