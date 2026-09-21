# FeatureReview

The guided, resumable weekly review (§10). `docs/STYLEGUIDE.md` §3.10 is the
binding spec for the wizard frame, deck cards, stat tiles and heatmap.

## Public API

- `WeeklyReviewView(bindings:onEditAction:onFinished:)` — the wizard. `WeeklyReviewView(store:bindings:onEditAction:onFinished:)`
  injects a `ReviewStateStore` (previews, tests, an app shell that wants its own location).
  `bindings` is the device's stored `KeyBindings` (R-10/N7, default `.defaults`); `onEditAction`
  is called with a `NoteID` when a deck card offers "open the action for editing" after a promote
  is refused for missing fields (R-3) — this target has no editor of its own (ARCHITECTURE §2:
  `FeatureOverview` depends on `FeatureReview`, not the other way around), so the shell supplies
  real navigation and the default is a no-op.
- `ReviewResumeBanner(onResume:)` / `(store:onResume:)` — renders **only** while a review is in
  progress; the shell can show it unconditionally.

Linux-compilable (all the logic, all of it unit-tested):

- `ReviewSession` — `@MainActor @Observable`. Pages, the two gates, every sweep and deck action,
  the stats, `save()`. Views hold no decisions.
- `ReviewPage` / `ReviewStage` / `ReviewRailItem` — the wizard is a flat, ordered page list; the
  four stages of §10 are a grouping over it (the rail).
- `ReviewSessionState` (+ `WeeklyReviewAnswers`, `ReviewQuestion`, `SystemsCheckAnswers`,
  `SystemsCheckPrompt`, `ReviewChanges`) — the persisted state. `migratedPage(fromRaw:)` tolerates
  a `page` value an older build wrote that this one no longer has (T12): the pre-rework merged
  deck phase, `deckBacklogMaybe`, maps straight onto `deckSomeday` (same position, unambiguous);
  anything else unrecognised restarts at `deckNext` rather than discarding the whole state or
  crashing — the sweep's own progress never depends on the deck's `page` value.
- `ReviewStateStore`: `FileReviewStateStore` (one JSON file in Application Support) and
  `InMemoryReviewStateStore`.
- `ReviewDeck` / `DeckPhase` / `DeckCard` / `DeckChoice` — deck order and choice → command.
  `DeckChoice.keyCommand` maps a choice to its `GTDAppCore.KeyCommand`; `ReviewSession.choice(forKey:on:bindings:)`
  resolves a Mac key press against a card through a `KeyBindings` value (default `.defaults`,
  R-10/N7) instead of the fixed `DeckChoice.key` string, so a rebind changes what a key does; so
  does `ReviewDeckViews`' key legend and `.keyboardShortcut`, both built from the same `bindings`
  value rather than the STYLEGUIDE default (T12). `ReviewDeck.cards(for:in:today:calendar:)`
  orders the Someday phase **stalest first, project-linked before unlinked, then by path** —
  `stalestFirst`/`untouchedDays` read `Action.modified` (the same field the §2.2 staleness badge
  reads: `GTDVault` fills it from the file's mtime, the reducer's `normalize` bumps it to
  `env.now` on every mutation, so it already *is* "file modification or last status change,
  whichever is later" — no second query exists to combine the two). A note with no `modified` at
  all sorts as the most stale of all, never as recent. `untouchedOver30DaysCount(in:today:)` is
  the Someday header's stat (STYLEGUIDE §3.10), counted over the whole tier, not just the cards
  still left to decide.
- `DeferredSweep` / `WaitingSweep` / `StalledSweep` — one decision → one `GTDCommand`.
- `ReviewStats` / `ReviewStatTile` / `ReviewHeatmap` — `GTDStats` output turned into tiles and
  heatmap rows. `ReviewCopy` / `ReviewSymbols` — review-only strings and the §7 symbol lookups.

## Invariants

- **The two gates**: the sweep cannot be left while the inbox has items; the deck cannot be left
  while Next is over the cap. `blockReason` says why, so the button is never dead without a reason.
- Every state change persists immediately, keyed by ISO week. A session from an **earlier** week
  is offered (`continueStale()` / `discardStale()`), never silently adopted or dropped. A saved
  review is not resumable. A corrupt file (or a state this build cannot decode at all, rather than
  just a `page` value it can migrate) means "no session", never a half-restored wizard.
- Decided items are remembered by `NoteID.path`, so a card demoted in the Next phase is not dealt
  again in the Someday phase, and a relaunch resumes the exact position.
- A refused command lands in `lastError` and leaves the card on the deck — never a silent skip.
  Two refusals the deck handles itself instead of falling through to `lastError` (STYLEGUIDE
  §3.10/§3.6, R-3, D14 — inline on the card, never the shell's alert): `nextCapReached` sets
  `capChoice`/`capCard` (the forced choice — `demoteAndRetryDeckCard(_:)` retries the same
  promote, `cancelCapChoice()` leaves the card undecided, never an automatic "send to Someday
  instead"), and `missingFields` sets `missingFieldsIssue` (the card names the fields and offers
  `dismissMissingFieldsForEditing()` or `keepDespiteMissingFields(_:)` — the latter records the
  decision as `keep` without writing anything). Both are cleared on `advance()`/`back()`/`go(to:)`
  so a stale notice never survives leaving the page.
- Captured/processed is an approximation (no filed-at timestamp exists); the screen says so.
- `resolve` on a waiting item goes to **Someday**, not Next — it can never fail on the cap.
- `drop` is offered only for on-hold projects: a Someday project has nowhere left to drop to.

## Platform guards (ARCHITECTURE §5)

`ReviewViews.swift`, `ReviewSweepViews.swift`, `ReviewDeckViews.swift`, `ReviewSystemsViews.swift`,
`ReviewReflectionViews.swift` and `ReviewPreviews.swift` are wrapped entirely in
`#if canImport(SwiftUI)`. The whole target now **compiles warning-free** on a real Xcode (both
scratch app builds, T12, 2026-09-21) — it has never been run on a device or the simulator, and no
one has interacted with a card, a sheet or a gesture, so "builds" is not "verified".

## Testing

`cd Packages/GTDKit && swift test --filter FeatureReviewTests` (91 tests).
