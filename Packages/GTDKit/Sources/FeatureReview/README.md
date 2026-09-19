# FeatureReview

The guided, resumable weekly review (§10). **Owned by T27.** `docs/STYLEGUIDE.md` §3.10 is the
binding spec for the wizard frame, deck cards, stat tiles and heatmap.

## Public API

- `WeeklyReviewView(onFinished:)` — the wizard. `WeeklyReviewView(store:onFinished:)` injects a
  `ReviewStateStore` (previews, tests, an app shell that wants its own location).
- `ReviewResumeBanner(onResume:)` / `(store:onResume:)` — renders **only** while a review is in
  progress; the shell can show it unconditionally.

Linux-compilable (all the logic, all of it unit-tested):

- `ReviewSession` — `@MainActor @Observable`. Pages, the two gates, every sweep and deck action,
  the stats, `save()`. Views hold no decisions.
- `ReviewPage` / `ReviewStage` / `ReviewRailItem` — the wizard is a flat, ordered page list; the
  four stages of §10 are a grouping over it (the rail).
- `ReviewSessionState` (+ `WeeklyReviewAnswers`, `ReviewQuestion`, `SystemsCheckAnswers`,
  `SystemsCheckPrompt`, `ReviewChanges`) — the persisted state.
- `ReviewStateStore`: `FileReviewStateStore` (one JSON file in Application Support) and
  `InMemoryReviewStateStore`.
- `ReviewDeck` / `DeckPhase` / `DeckCard` / `DeckChoice` — deck order and choice → command.
- `DeferredSweep` / `WaitingSweep` / `StalledSweep` — one decision → one `GTDCommand`.
- `ReviewStats` / `ReviewStatTile` / `ReviewHeatmap` — `GTDStats` output turned into tiles and
  heatmap rows. `ReviewCopy` / `ReviewSymbols` — review-only strings and the §7 symbol lookups.

## Invariants

- **The two gates**: the sweep cannot be left while the inbox has items; the deck cannot be left
  while Next is over the cap. `blockReason` says why, so the button is never dead without a reason.
- Every state change persists immediately, keyed by ISO week. A session from an **earlier** week
  is offered (`continueStale()` / `discardStale()`), never silently adopted or dropped. A saved
  review is not resumable. A corrupt file means "no session", never a half-restored wizard.
- Decided items are remembered by `NoteID.path`, so a card demoted in the Next phase is not dealt
  again in the Backlog phase, and a relaunch resumes the exact position.
- A refused command lands in `lastError` and leaves the card on the deck — never a silent skip.
- Captured/processed is an approximation (no filed-at timestamp exists); the screen says so.
- `resolve` on a waiting item goes to **Backlog**, not Next — it can never fail on the cap.
- `drop` is offered only for on-hold projects: a Someday project has nowhere left to drop to.

## Platform guards (ARCHITECTURE §5)

`ReviewViews.swift`, `ReviewSweepViews.swift`, `ReviewDeckViews.swift`, `ReviewSystemsViews.swift`,
`ReviewReflectionViews.swift` and `ReviewPreviews.swift` are wrapped entirely in
`#if canImport(SwiftUI)` and were written **without a compiler** — unverified until built on a Mac.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureReviewTests` (76 tests).
