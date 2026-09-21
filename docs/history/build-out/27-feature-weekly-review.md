# T27 — Weekly review wizard (`FeatureReview`)

**Wave 2 · needs T12, T14, T20 (and the public views of T22/T23)**

## Model recommendation

**Difficulty:** Medium–hard (largest feature overall) · **Recommended model:** Opus

Composes four other modules (inbox card, projects, waiting, stats) into a gated, resumable multi-step wizard with persisted session state, a card deck with three phases, a heatmap and the review note. Each piece is ordinary; the difficulty is breadth plus state consistency across resume. Sonnet is likely to finish it shallowly. If budget matters: split into two Sonnet runs (steps 1–2, steps 3–4 + persistence) with Opus defining `ReviewSession` first.

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
     Live cap count/badge (STYLEGUIDE §2.2); cannot leave the step while Next > cap.
  3. **Systems check** — the prompts from §10.3 as short free-text fields, next to live stats from
     `WeeklyStats` and the **routine audit heatmap** (rows = steps, 7 columns, completion %, trend
     arrow vs last week) from `RoutineAudit`. Heatmap built with plain SwiftUI grid (Swift Charts optional).
  4. **Reflection** — reminder to review the reMarkable journal; the 8 questions with last week's
     "goal for next week" shown alongside (`VaultSnapshot.lastReview`);
     save → `GTDCommand.saveWeeklyReview` → `GTD/Reviews/<yyyy>/KW <ww>.md`.
- Wizard frame, deck cards (keys `K` keep · `D` demote · `P` promote · `T` trash), stat tiles and heatmap exactly per STYLEGUIDE §3.10; trends are not coloured.
- Summary screen: what changed this review (processed, demoted, promoted, trashed, projects touched).

## Acceptance

- Unit tests: session persistence/resume, step gating (Next ≤ cap), deck ordering, review note content.
- Previews per step with fixtures.
- `scripts/check.sh` passes.

## Result

**Status: done.** `scripts/check.sh` passes; `FeatureReviewTests` has **76 tests**, the package
total is 520 across 18 test targets.

### What was built

The wizard is a **flat, ordered list of `ReviewPage`s** (`sweepInbox · sweepDeferred ·
sweepWaiting · sweepStalled · deckNext · deckBacklogMaybe · deckProjects · systemsCheck ·
reflection · summary`); the four stages of §10 are a grouping over it (the rail). One stored
`page` is therefore the whole of "resume exactly where I stopped".

Linux-compilable (all logic, all unit-tested):

- `ReviewSession` (`@MainActor @Observable`) — navigation, the two gates, every sweep and deck
  action, the stats, `save()`. Views hold no decisions.
- `ReviewSessionState` / `WeeklyReviewAnswers` / `ReviewQuestion` / `SystemsCheckAnswers` /
  `SystemsCheckPrompt` / `ReviewChanges` — the persisted state, keyed by ISO week.
- `ReviewStateStore`: `FileReviewStateStore` (one atomic JSON file in Application Support,
  never in the vault) + `InMemoryReviewStateStore`.
- `ReviewDeck` / `DeckPhase` / `DeckCard` / `DeckChoice` — deck order, per-card choices,
  choice → `GTDCommand`.
- `DeferredSweep` / `WaitingSweep` / `StalledSweep` — one sweep decision → one `GTDCommand`.
- `ReviewStats` / `ReviewStatTile` / `ReviewHeatmap` — `WeeklyStats`/`RoutineAudit` turned into
  tiles and heatmap rows; `ReviewCopy` / `ReviewSymbols` — review-only strings, §7 symbol lookups.

SwiftUI (unverified, see below): wizard frame with `ReviewWizardRail` + `Back`/`Continue` bar,
the four sweep steps (step 1a embeds the real `FeatureInbox.InboxProcessingView`; 1d opens
`FeatureProjects.WhatsNextSheet`), the deck with `ItemCard` + `KeyLegendRow` + `K/D/P/T`
shortcuts, the systems check with `StatTile`s and one `RoutineHeatmap` per routine, the
reflection screen (8 questions, reMarkable reminder, last week's goal inline) and the summary
screen with `RewardMoment.reviewComplete`. 11 `#Preview`s, one per step plus dark and AX1.

### Decisions taken (the user could not be asked)

| Question the brief left open | Decision |
| --- | --- |
| Gating | Sweep cannot be left while the inbox has items (§10.1.1 "inbox to zero"); the deck cannot be left while Next is **over** cap (at cap is fine). `blockReason` states why — never a dead button. Rail jumps are backwards-only, so no gate can be skipped. |
| Waiting `chase` vs `bump` | Both rewrite `followUpDate` and stay `waiting`; they differ in the **suggested** date (chase +3 d = "I chased today", bump +7 d = "not now"). Neither writes until the user confirms (W1, §3.1). |
| Waiting `resolve` | Moves to **Backlog**, not Next: the end of a wait is not itself a commitment, and Backlog can never fail on the cap. The deck step right afterwards is where it earns a Next slot. |
| Project `drop` | `on-hold → someday`. A project already on Someday is offered **activate/keep only** — the app never deletes, and "drop" must not quietly mean "done". |
| §10.3 prompts in the note | `WeeklyReview` has no field for them, so each answered prompt becomes one `systemFixNotes` line **with its question**; unanswered prompts write nothing. Deferred-item notes come first, in `"<item> (deferred: <reason>) → <fix>"` form. |
| Deferred items and the inbox card | `InboxSession` builds its queue from `Rules.inboxQueue`, which excludes review-deferred items, and its sheets are internal — so the review reuses `CardTarget`, `InboxSession.Draft` and the same chips, and builds the `InboxDecision` itself (`DeferredSweep`). `deferToReview` is **not** offered (it would make the escape hatch a loop); Knowledge uses a stock folder list, Project uses `FeatureProjects.ProjectPicker`, Waiting uses `DesignSystem.WaitingInfoSheet`. |
| Stats anchor | `reviewDay` = the **last day of the week under review**, which is exactly what `WeeklyStats.compute` anchors on internally, and it is handed to `RoutineAudit.compute` too — so tiles and heatmap always describe the same seven days. |
| captured/processed honesty | Presented as the approximation T14 documents, with `ReviewCopy.capturedApproximation` under the tiles. |

### Contract changes

**None to shared files** — `Package.swift`, `docs/ARCHITECTURE.md`, `CLAUDE.md` and other
targets are untouched. Within `FeatureReview` (T00's stub, this task's to own), the API grew
**additively**: `ReviewSessionState` keeps its `init(year:week:stage:review:systemFixNotes:startedAt:)`
and `stage` (now computed from `page`) and gained a page-based initialiser plus the resume
bookkeeping; `WeeklyReviewAnswers` gained a `ReviewQuestion` subscript; `ReviewSession.init`
gained `store`/`now`/`calendar`; `WeeklyReviewView` and `ReviewResumeBanner` each gained a
`store:` overload beside the frozen signature. `FeatureOverview`'s
`WeeklyReviewView(onFinished:)` call site is unaffected.

### Files that could not be compiled on Linux (verify on a Mac)

`Sources/FeatureReview/ReviewViews.swift`, `ReviewSweepViews.swift`, `ReviewDeckViews.swift`,
`ReviewSystemsViews.swift`, `ReviewReflectionViews.swift`, `ReviewPreviews.swift`.
Most likely breakages, in order: `.keyboardShortcut(_:modifiers: [])` with bare letter/arrow
keys inside a `FlowLayout`/`HStack` (Mac focus behaviour); `TextField(_:text:axis:)` +
`lineLimit(2...6)` inside `ItemCard`; `.sheet(item:)` with the local `ProjectSheetItem` wrapper;
`LazyVGrid(.adaptive(minimum: 160))` inside a `ScrollView` that already constrains width; and
`ContentUnavailableView(_:systemImage:description:)` on macOS. Verify with
`brew install xcodegen && scripts/check.sh --app`, then walk all four stages in the app.

### Open issues / gotchas for later tasks

1. `FeatureInbox`'s sheets (`KnowledgeSheet`, `ProjectSheet`, `CapSheet`, …) and
   `InboxSession`'s queue are internal/fixed to `Rules.inboxQueue`. If T41 wants the review to
   run the *literal* inbox card over deferred items, `InboxSession` needs an injectable queue —
   that is a `FeatureInbox` contract change, not a `FeatureReview` one.
2. The wizard persists on **every keystroke** (a small atomic JSON write). Fine for a Mac-only
   review; if it ever shows up in a profile, debounce in `ReviewSession.mutate`.
3. `GTDMarkdown.encode(_: WeeklyReview)` is still T10's stub, so the note's **markdown** is
   untested end to end here; `saveWeeklyReview` → `snapshot.lastReview` is tested against
   `InMemoryBackend`. T16 should re-check `systemFixNotes` round-tripping (N2) — this task keeps
   an existing same-week note's `passthrough` when re-saving.
4. Layout dimensions with no `DesignSystem` token (rail 220 pt, content 720 pt from §3.10, sheet
   minimums) are literals in the view files, matching the precedent in `RoutineHeatmap`.
5. `StalledSweep.addNextAction` marks the project handled without a command — the promotion
   itself is `WhatsNextSheet`'s `promoteStep`. If T22's sheet ends up not promoting, the project
   silently leaves the sweep list; worth a look when T22 lands.

### `scripts/check.sh`

```
✔ Test run with 20 tests in 3 suites passed after 0.002 seconds.

=== docs check
checking backticked paths in CLAUDE.md README.md
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok

=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build system only — verify this step on a Mac.

=== check.sh finished
```
