# T41 — QA, traceability & hardening

**Wave 3 · after T40**

## Model recommendation

**Difficulty:** Hard (judgment-heavy) · **Recommended model:** Opus

An adversarial audit is only worth as much as the auditor: tracing every requirement to evidence, hunting data-safety violations, designing sync torture tests. A weaker model tends to confirm rather than challenge. The follow-up fixes it spawns can go to Sonnet.

## Goal

Prove the app meets REQUIREMENTS v1 and is safe to point at the real vault.

## Owns

`docs/TRACEABILITY.md`, `docs/MANUAL_TEST.md` (extend), new tests anywhere; bug fixes anywhere
(keep them small and list each in Result; large ones become follow-up task docs `5x-*.md`).

## Deliverables

1. **Traceability matrix:** every requirement ID (N1–N6, C1–C4, I1–I7, A1–A5, P1–P7, W1–W2, D1–D3,
   E1–E4, R1–R6, §10 steps, M1–M6) → implementing module, test(s), status (met / partial / missing) with evidence.
2. **Data-safety review** of everything that writes: confirm ARCHITECTURE §7 rules hold; grep for
   `FileManager` use outside `GTDVault`; confirm no hard deletes; fuzz the codec with the sample
   vault + mutated files; verify unknown frontmatter survives every command (golden-file tests).
3. **Sync torture tests** on a temp vault: external edits during a commit, rename while open in
   detail view, conflict copies, evicted-file placeholders, two simulated devices writing routine logs for the same day.
4. **"No lying defaults" audit:** walk every form; no pre-filled values at all; the only proposals (follow-up +7 d,
   last-used knowledge folder) render as *suggested* chips/rows and are not persisted until confirmed. Also run the STYLEGUIDE §9 checklist over every screen.
5. **Performance:** cold launch to usable Next view with 1 000 notes; snapshot rebuild; typing latency in the detail editor.
6. **Accessibility pass** (VoiceOver through inbox card + routine runner, Dynamic Type XXL, keyboard-only on Mac).
7. **First-real-use checklist** for the user: back up vault → run T02 migration dry run → apply →
   pick vault in the app → first weekly review to settle Next vs Backlog.

8. **Docs drift check:** list every place where CLAUDE.md / ARCHITECTURE / module READMEs disagree with the code as input for T42 (list only — T42 fixes).

## Acceptance

- `docs/TRACEABILITY.md` complete; every "partial/missing" has a follow-up task doc.
- All new tests pass in `scripts/check.sh`; no test touches the real vault.

## Result

**Status: partial — by design.** The orchestrator scoped this run to four priorities
(cross-module correctness on Linux, round-trip/data-safety fuzzing, a blind SwiftUI +
STYLEGUIDE §9 review, and the named duplication cleanup). Those are done. **Deliverable 1
(`docs/TRACEABILITY.md`) was not written**, nor were 3 (in part), 5 (performance), 6
(accessibility) and 7 (first-real-use checklist) — see "Not done" below. `scripts/check.sh`
exits 0 with **838 tests** (820 at the start of this run).

### Bugs found and fixed

Each one is a real defect, found by a test or by reading; all fixes are small and none disables
anything.

| # | Where | What was wrong |
| --- | --- | --- |
| 1 | `GTDAppCore/InMemoryBackend.swift`, `GTDServices/UndoLabel.swift` | Two private copies of the N6 undoable rule and the label table. `UndoLabel` moved to `GTDAppCore`; both backends now call `Rules.isUndoable` (T11/T16 open item). |
| 2 | `GTDModel/Reducer/Reducer.swift` | `archiveCompleted` left `ProjectStep.promotedTo` pointing at the old `Actions/` path — a dead wikilink in the project note. It retargets to the archive path (T16 open item). |
| 3 | `GTDVault/InboxWriter.swift`, `App/AppComposition.swift` | The bookmark was resolved *after* scoped access started, so "never picked", "saved but unresolvable" and "access refused" were one message and `CaptureError.bookmarkStale` was unreachable (T30 gotcha #1). |
| 4 | `FeatureReview/ReviewSession.swift` | `markStalledHandled` trusted `WhatsNextSheet`; closing the sheet without promoting dropped a stalled project out of the §10.1.4 sweep. It now verifies the project is no longer stalled (T27 open item). |
| 5 | `GTDMarkdown/NoteCodec.swift` | **Data loss.** `decodeRoutineLog` read a damaged `entries:` (a scalar or a mapping instead of a list) as "no entries". `encodeRoutineLog` regenerates the file, so the next routine step logged that day would have overwritten the day's history with an empty log. It now throws `.unreadable`, which `GTDVault` surfaces as a `VaultIssue` and never writes over. Found by the damaged-file fuzz. |
| 6 | `FeatureWaiting/WaitingViews.swift` (10 call sites), `FeatureOverview/ActionListView.swift` | Every row command was `try? await model.send(…)`. "Move to Next" on a waiting item while Next is at the cap, and un-deferring an item the defer × Next rule refuses, silently did nothing — the lying UI STYLEGUIDE §1 forbids. |
| 7 | `App/PhoneShell.swift`, `FeatureOverview/OverviewView.swift` | `InboxProcessingView` carries its own toolbar (card counter, `⌘Z` undo, `Done`) but no navigation container, and neither presenter supplied one — only the previews did. The forced processing session would have had no visible way out on either platform. |
| 8 | `FeatureOverview/OverviewView.swift` | `VaultIssuesView` was presented in a bare sheet. On the Mac that is a trap: it brings only a `.navigationTitle`, no close control. |
| 9 | `App/GTDApp.swift` | The `Scene` body used three consecutive `#if`s, two continuing a postfix modifier chain and the third opening a `Settings` *statement* — the shape blind-written scene builders most easily get wrong. Now one `#if os(macOS)/#else` around whole scenes. |
| 10 | `DesignSystem/Tokens/Colors.swift` | `dynamicContrast` read `NSWorkspace.shared` inside `NSColor`'s dynamic provider: a main-actor hop out of a nonisolated closure under Swift 6, and it tracked Increase Contrast only by luck of redraw. It now matches the `NSAppearance` it is handed against the four `aqua`/`accessibilityHighContrast…` names. |
| 11 | `FeatureInbox/InboxProcessingView.swift` | `InboxZeroView` drew STYLEGUIDE §5.1's reward moment itself, without the `signalDone` check badge, and fired its `.success` haptic on every processed card. It composes `DesignSystem.RewardMoment.inboxZero` now. |
| 12 | `App/AppComposition.swift` | The daily `archiveCompleted` was `try?`. A failed archive — including `VaultError.rollbackFailed`, which T15 says must never be silent — is now reported. |

### Contract changes

| # | File | Change |
| --- | --- | --- |
| T41-1 | `Packages/GTDKit/Sources/GTDAppCore/AppModel.swift` | Additive: `perform(_ command:) async -> Bool` and `report(_ work:) async -> Bool`. A refused command lands in `lastError`, which the shell already shows in one alert. Views with a flow of their own for the error (the cap sheet, the waiting sheet) keep using `send` and are untouched. Module README updated. |
| — | `Packages/GTDKit/Sources/GTDAppCore/UndoLabel.swift` | Moved here from `GTDServices` and made public (bug #1). No signature changed. |
| — | `DesignSystem` | Additive tokens so feature code holds no literal: `Symbols.moveUp/moveDown`, `Typo.rowIcon/controlGlyph`, `Copy.processedSummary`. |

`Packages/GTDKit/Package.swift` and ARCHITECTURE §4 are untouched.

### New tests (+18, and three suites that did not exist)

- `GTDServicesTests/EndToEndJourneyTests` — one week through the **real** stack (`AppModel` →
  `VaultBackend` → `FileVaultStore` → `PlainFileSystem`, temp copy of the sample vault):
  external capture → file to Next → the cap refuses and writes nothing → Backlog → promote a
  project step → waiting needs who + follow-up → two levels of undo byte for byte → the `KW`
  note decoded back off disk (`systemFixNotes`, T27's open item) → a cold re-scan agreeing with
  the app. Plus the archive-retarget case and backend undo-parity.
- `GTDServicesTests/SyncScenarioTests` — N3 §7: two backends with different device ids logging
  the same routine on the same day; an undo refused after another writer touched the file; a
  conflict copy reported and never rewritten; an evicted iCloud file. All four passed as
  written.
- `GTDMarkdownTests/FuzzRoundTripTests` — a seeded SplitMix64 generator builds ~1 800 action,
  project and inbox notes (shuffled key order, block vs flow lists, nested mappings, block
  scalars, comments, unknown keys, unknown and oddly-spelled headings, CRLF, BOM, no final
  newline) and asserts both halves of N2 on each; then damages every sample-vault file twelve
  ways and requires each result to round-trip **or** be refused. Failures print the seed.
- `GTDVaultTests/TransactionFuzzTests` — 600 random op sequences, half against an injected
  write/move failure: a refused commit changes nothing outside `GTD/Trash/`, a successful one
  matches a plain simulation of its own ops and its inverse restores the vault byte for byte,
  and no byte that existed before is ever gone unless a `.put` overwrote the file it lived in.
- `GTDAppCoreTests/ErrorSurfacingTests` — `perform`/`report` (bug #6).

Two rewrites of a *damaged* file are deliberate and are now pinned by tests rather than being
accidents: a note that lost its `kind:` gets it back (it is otherwise unclassifiable), and a
file whose frontmatter lost its closing `---` gets a fresh frontmatter block **above** its
unchanged text. Nothing is deleted in either case.

### STYLEGUIDE §9 audit (by reading)

- **No literals in feature code.** `Feature*` and `App/` now contain no literal colour, font,
  padding, radius, duration or symbol name at all — the last three (`chevron.up/.down`,
  `.caption`, `.title2`) became `DesignSystem` tokens. Verified by grep, not by eye.
- **No lying defaults.** Every form was walked. No pre-selected chip, no pre-filled date. The
  two proposals (+7 d follow-up, last-used knowledge folder) are UI state and reach no command
  until confirmed. The one pre-filled value in the app — `RoutineTimeRow`'s 07:00 — appears only
  *after* the person turns the toggle on, which is the confirmation, and is documented as such.
- **Signal colour always with a symbol or text**: enforced in one place
  (`DesignSystem.SignalPresentation`) and unit-tested per §2.2 row.
- One deviation left open: `RewardMoment` uses `.font(.system(size: 56))`, which §2.3 forbids.
  Changing it blind would change how the only two reward moments look — `TEST-INSTRUCTIONS.md`
  "Unresolved" #1.
- `Symbols.checkboxOn/Off` and the new `moveUp/moveDown` have no row in §7's icon map; the map
  is a vault note no agent can edit ("Unresolved" #3).

### Duplication cleanup (deliverable 4)

Done: the inbox-zero reward moment (bug #11) and the `"14 processed · 6 min"` wording.
**Not done, on purpose:** `InboxSessionView` still implements the card drag geometry and fly-out
itself instead of `DesignSystem`'s `CardFilingController` + `.cardSwipeFiling`. Rewriting a
gesture in two files that have never been compiled is not low-risk, and `CardTarget`/`KeyMap`/
`DragResolver` (the GTD semantics, unit-tested) stay in `FeatureInbox` either way. Precise note
in `agent_task/ORCHESTRATOR-NOTES.md`.

### Files unverified on Linux

Every file this task touched under `#if canImport(SwiftUI)`: `App/GTDApp.swift`,
`App/PhoneShell.swift`, `App/AppComposition.swift`, `DesignSystem/Tokens/Colors.swift`,
`DesignSystem/Tokens/Typography.swift`, `DesignSystem/Symbols.swift`,
`DesignSystem/Copy.swift`, `DesignSystem/Components/RewardMoment.swift`,
`FeatureInbox/InboxProcessingView.swift`, `FeatureOverview/OverviewView.swift`,
`FeatureOverview/ActionListView.swift`, `FeatureProjects/ProjectViews.swift`,
`FeatureRoutines/RoutineViews.swift`, `FeatureWaiting/WaitingViews.swift`. Everything else
changed here (`GTDModel`, `GTDMarkdown`, `GTDAppCore`, `GTDVault`, `GTDServices`,
`FeatureReview/ReviewSession.swift`, `FeatureInbox/InboxCopy.swift` and all tests) builds and
runs on Linux.

`TEST-INSTRUCTIONS.md` gained **"Where to look first (T41 blind review)"** — the nine API and
concurrency spots most likely to break under the real compiler, in the order worth trying, plus
the four behaviours changed blind that must be checked in the running app — and an
**"Unresolved"** section with the ten judgement calls that need a Mac or the user.

### Not done (the rest of this brief)

- **Deliverable 1, `docs/TRACEABILITY.md`.** Not started. It is the largest remaining piece of
  T41 and the natural input to T42.
- **Deliverable 2's grep audit** was done but is not written up as a document; the invariants
  are now *tested* instead (`TransactionFuzzTests`). What the grep found: the only code outside
  `GTDVault` that uses `FileManager` is `GTDServices/UndoJournal.swift`,
  `GTDServices/Housekeeping.swift` and `FeatureReview/ReviewStateStore.swift` — all three write
  **device-local state into Application Support**, never the vault, which is exactly what
  ARCHITECTURE §3 prescribes — plus `GTDFixtures/SampleVault.swift`, which copies the bundled
  fixture. Nothing hard-deletes: `VaultFileSystem` has no delete member at all, and no test or
  source anywhere names `iCloud~md~obsidian`.
- **Deliverable 3** is covered for two-device routine logs, external edits, conflict copies and
  evicted files; "rename while open in detail view" is covered only by `AppRouter.prune`'s unit
  test.
- **Deliverables 5 (performance), 6 (accessibility), 7 (first-real-use checklist)** — 5 needs a
  1 000-note vault on real hardware, 6 needs a device, 7 is a user-facing document that should
  be written once Gate 2 has passed once.

### `scripts/check.sh`

```
=== swift build (Packages/GTDKit)
[11 expected "no rule to process file … xcstrings/assetcatalog" warnings]
Build complete!

=== swift test (Packages/GTDKit)
✔ 838 tests across all 18 test targets passed
  (GTDModelTests 134, GTDMarkdownTests 115, GTDVaultTests 112, FeatureReviewTests 77,
   FeatureProjectsTests 59, FeatureInboxTests 49, GTDServicesTests 47, FeatureOverviewTests 39,
   GTDStatsTests 32, FeatureSettingsTests 30, GTDNotificationsTests 27, FeatureNextTests 24,
   GTDIntentsTests 22, DesignSystemTests 20, FeatureWaitingTests 19, FeatureRoutinesTests 15,
   GTDAppCoreTests 11, GTDFixturesTests 6)

=== docs check
checking backticked paths in CLAUDE.md README.md
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok

=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build system only — verify this step on a Mac.

=== check.sh finished
```

(exit 0.)
