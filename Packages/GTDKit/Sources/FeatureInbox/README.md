# FeatureInbox

Inbox processing: one card at a time, LIFO, forced order, exit only by quitting (I1–I7).
`docs/STYLEGUIDE.md` §3.5/§3.6 is the binding spec for the card, its steps and its gestures.

## Public API

- `InboxProcessingView(showsChrome:onFinished:)` — the whole session. `FeatureReview` embeds it (§10.1) with `showsChrome: false`, which drops the counter and `Close` from the toolbar.
- `InboxStartButton(action:)` — home-screen entry point with the live queue count.
- `MakeActionModel(model:item:bindings:)` — **Make action** (L4)'s state, for `FeatureLists`: see below.
  `MakeActionModel(model:action:target:missing:bindings:)` — the same card over an **existing
  action** that was dropped onto a tier it is not ready for (`MovePlan.card`): starts from the
  action's own values with `missing` already marked, opens the waiting sheet at once for
  `.waiting`, and sends `updateAction` (a project created from the picker is born first by
  `createProject`). `source` says which; `item` is `nil` for an action.
- `MoveCoordinator(model:bindings:)` + `View.moveNoteHost(_:)` — drag-to-category (E3): the
  shell applies the modifier once (the Mac window, the iPhone's Next tab); it sets the
  `\.moveNote` environment for every row and drop target below and presents the dialogue a drop
  needs over the coordinator: the action card, `DeferDateSheet`, the project picker
  (`ProjectChoiceSheet`, shared with the card's `+ project` chip) or the list picker
  (`ListChoiceSheet`, shared with the inbox's `More…` slot — a drop onto Lists sends
  `moveActionToList`). `move(_:to:)` runs `GTDAppCore.MovePlan`; `confirmDefer`,
  `chooseProject`, `createProject`, `chooseList`, `createListAndMove`, `cancel()`.
- `MakeActionCardView(model:onFinished:)` — **Make action**'s view: the opened action card alone
  (STYLEGUIDE §3.5 step 2a), the same field layout and `ActionCardBar` the inbox uses for its own
  action card, over a `MakeActionModel`. `FeatureLists` (T10) presents it as a sheet:
  ```swift
  .sheet(item: $listItemToPromote) { item in
      MakeActionCardView(
          model: MakeActionModel(model: appModel, item: item, bindings: keyBindings)
      ) {
          listItemToPromote = nil
      }
  }
  ```
  `onFinished` fires once the card is filed (`model.isFiled == true`) or cancelled (`Close` /
  `Esc` with no field focused and no step-1 to collapse to); the host owns dismissing the sheet.
  It carries its own `.toolbar` (`Close`, no counter — there is no queue here) and, on Mac, its
  own key handling and legend, exactly mirroring `InboxProcessingView`'s action-card step. Swipe
  → files Next, ← files Someday, `Waiting`/`Done` are bar buttons, `+ project` opens the same
  `ProjectPickerModel`-backed sheet as the inbox, the cap sheet is the same forced choice.

Linux-compilable (this is where all the logic lives, and all of it is unit-tested):

- `InboxSession` — `@MainActor @Observable`. The **state machine**: `step`, `queue`, `card`
  (draft + validation flags + cap state), `sheet`, counter, every sub-flow, keys, legend, undo.
  Views own no decisions; they render and call `take(_:)` / `collapse()` / `escape()` /
  `confirm*(…)` / `demoteAndRetry(_:)` / `undo()` / `handle(…)`.
- `CardTargets.swift` — the vocabulary, defined **once** for both platforms (ARCHITECTURE §6):
  `InboxStep` (`step1` / `actionCard` / `keepCard`, each with its `KeyScreen`), `InboxExit` (one
  case per row of STYLEGUIDE §3.6's three tables, with `step`, `title`, `symbol`), `CardTarget`
  (where a card *ended up* — the session summary and the undo toast), `SwipeDirection`,
  `DragContext`/`DragOutcome`/`DragResolver`, and `KeyMap`, which resolves every letter and digit
  through `GTDAppCore.KeyBindings` for the **current step's** screen (R-10/N7).
- `ActionCard.swift` — `InboxDraft`, `ActionCardState` (draft + per-field flags + shake trigger +
  cap state) and `ActionCardEngine` (pre-validate → send → fold every refusal back into the
  state). `InboxSession` and `MakeActionModel` both drive exactly this; neither owns a copy of a
  required field, the cap flow or the asterisk rule. `InboxRefusal` is the one list of ways the
  card says no.
- `CardKeyCursor.swift` — the Mac chip walk of the opened action card (#65): `CardKeyRow`
  (`context` → `time` → `outcome`), `CardOutcome` (`Next · Someday · Waiting · Done · Project`,
  each with its `InboxExit`) and `CardKeyCursor` (`first`, `advanced` = `⌘↩`, `moved(by:)` =
  `Tab`/`⇧Tab` wrapping in the row, `forMissing` = where a refusal sends it); #77 added the
  `dates` row (`CardDateStop`: `+ defer` · `+ due` · `+ project`) between time and outcome.
  `InboxSession` stores the one cursor (`keyCursor`) and drives it: `advanceKeyCursor()`,
  `moveKeyCursor(by:)`, `pressKeyCursor()`, `perform(_: CardOutcome)`, `pointKeyCursor(at:)` (a
  click); `↩` on `+ defer`/`+ due` sets `datePicker`, which the view binds the chip's popover to;
  `handle(.done)` walks instead of filing while a cursor exists; `escape()` clears it first
  (`.clearedCursor`); a focused field, a collapse, a filing and undo end it. Step 1 and the
  Knowledge / List card walk their bar instead (#77): `barStops`, the always-present `barCursor`
  (reset to the first stop on every new card and step), `barHighlight` (`nil` while `Notes` has the
  keyboard), `pointBar(at:)`; the same `moveKeyCursor`/`pressKeyCursor` drive it.
- `SheetWalks.swift` — what the walk stands on in each sheet (#77), row by row:
  `ProjectPickerModel.walkRows(canClear:)` (`ProjectPickStop`), `ListPickStop.walkRows`,
  `KnowledgePickStop.walkRows` (+ `KnowledgeTree.visible(_:expanded:)`), `DeferReviewStop`. The
  sheets keep a `DesignSystem.KeyWalk` in view state and press the stop under it.
- `MakeActionModel.swift` — L4's entry point: the opened action card alone, over a `ListItem`
  (sending `promoteListItem`) or an `Action` (sending `updateAction`; `ActionCardState.previousStatus`
  is set so the card asks exactly what `Reducer.normalize` asks of a note already in a tier).
  Same draft, same validation, same cap flow; exits → Next / ← Someday / Waiting / Done;
  `cancel()` leaves the note as it was — except that over an existing action the fields typed
  are kept on close (`keptEdits`/`keepEdits()`, #85: status and the waiting pair stay, only the
  move is cancelled; `MakeActionCardView` calls it on disappear). There is no step 1 under it, so `Esc` blurs then
  cancels, and `undo` belongs to the list, not to the card.
- `MoveCoordinator.swift` — a drop or `Move to…` → `MovePlan` → perform at once, or hold the
  `dialogue` (`card` / `deferDate` / `pickProject`) until it confirms or is cancelled.
- `InboxPickers.swift` — `KnowledgeTree` (+ `KnowledgePickerModel`: suggestion, tree, `Projects`
  section), `ProjectPicker` (+ `ProjectPickerModel`: filtered tree, `Create project "<text>"`),
  `InboxDefaultsStore` (device-local last-used folder + one-time hint; `EphemeralInboxDefaults`
  for tests).
- `InboxCopy.swift` — inbox-only strings (the shared ones stay in `DesignSystem.Copy`) and
  `ChecklistText` (checklist toggling, `- ` auto-format).

## Invariants

- **The card is a two-step state machine** (I2): `step1` → `actionCard` or `keepCard`, and back
  by `collapse()`. `take(_:)` **refuses** an exit that does not belong to the current step
  (`InboxRefusal.notAvailable`) rather than quietly doing it — that is what keeps **Trash and
  `Defer to review` reachable from step 1 only** (I4c, I5).
- **Collapsing keeps the draft.** It survives until the card is filed or the session ends; a
  fresh card always starts at step 1 with the draft its note holds — empty for a new capture.
- **Leaving the session keeps the card (#85).** `saveProgress()` writes the current card into
  its inbox note (`saveInboxProgress`: `InboxDraft.progress(over:)` — body with `Why?`/`What?`,
  chips, the notes panel joined to the capture text — then the title as a rename) and leaves it
  in the inbox; `InboxDraft(item:)` reads it all back. `InboxProcessingView` calls it on
  disappear (Close, `Esc`, swipe-away, the review moving on), `AppModel.flushHeldEdits` on ⌘Q /
  backgrounding (the session is a `HeldEdits`; `unsavedText` feeds the crash journal), and
  `Defer to review` writes the same before deferring. A list filing clears stored chips first
  (`persistEdits(clearingProgress:)`). The Knowledge sheet edits `draft.notes` itself, so
  `Cancel` there keeps them.
- Nothing is pre-filled and no suggestion is ever persisted: the last-used knowledge folder and
  the +7 d follow-up are **suggested** until the user taps them (§1, STYLEGUIDE §3.1). The
  suggestion travels as its own field of `KnowledgePickerModel`, never as a chosen folder.
- **The file name is the title** (C3, 2026-09-22): the card's title field shows `InboxItem.title`
  (the file name, never the body's first line) and a changed title **renames the file** before the
  card is filed or deferred — `InboxSession.persistEdits` sends `editInboxBody` (if the body
  changed) and then `renameInboxItem`, and the queue, the draft and the card's step follow the
  renamed note, so a cap refusal or a failed filing after the rename keeps the card intact. A taken
  name is `.titleCollision`, an empty one `.invalid`, both shown as `InboxRefusal.failed`.
  `InboxDraft.noteTitle` shows the name a title would give the file (`CaptureText.renamedTitle`).
  The body is shown under the title only when it has content (`InboxSession.showsBody`): the empty
  Why/What template skeleton of an Obsidian-made note is not.
- **Required fields are R-3's** (`RequiredField.missing`, shared with the reducer): Next asks for
  `Why?` + `What?` + a context + a time estimate, Someday for `What?`, Waiting for `What?` plus
  the sheet's date, and Done/Knowledge/lists/Trash for nothing. The session pre-validates *and*
  still handles the reducer's `GTDError.missingFields`, which is the authority. `missingFields` /
  `isMissing(_:)` drop a field as soon as it is filled, `shakeTrigger` counts refusals and
  `focusRequest` names the first missing **text** field — never an alert.
- The cap is a **forced choice**: demote a Next item, or cancel and decide differently. There is
  no "send to Someday instead" shortcut any more (STYLEGUIDE §3.6, D14).
- **The project is a chip on the card, not a target** (I4a/R-8): the card stays an action and
  names an existing project or one created with `createProject(named:)` — never both.
- **Undo is R-9**: the card returns to the head of the queue **in the step it was filed from**,
  draft intact — opened action card for Next/Someday/Waiting/Done, opened Knowledge/List card for
  a list or Knowledge filing, small card for Trash and Defer to review.
- A card being worked on — **opened, or with something typed** — is never displaced by a
  mid-session capture; the capture is queued next.
- Items deferred to the weekly review leave the queue and never come back to it (I5).
- **`More…` is never a dead end.** `hasNoLists` turns the sheet into an empty state naming
  `listsFolderName`, and `createListAndFile(name:)` sends `createList` then files the card like
  any list exit. The reducer owns the name rules; its refusal is `newListRefusal` (inline, the
  sheet stays open). Undo returns the card to the keep card; the list stays (`createList` has no
  inverse). The session never creates a list the user did not name.

### Invariants this rework replaced (T08)

| Old | New |
| --- | --- |
| One card, four swipe targets; `↓` = Trash | Two steps; `←`/`→` file, `↓` **collapses**, `↑` does nothing, and there is **no drag at all** on step 1 (`DragContext`) |
| `CardTarget` was the swipe **and** key map (`key`, `isDirect`, `keyLegend`, `buttonTargets`, `menuTargets`) | `InboxExit` is the map; `CardTarget` is only the outcome taxonomy. Keys come from `KeyBindings` per step, legends from `InboxSession.legendString` |
| `choose(_:)` / `validate(for:)` / `Validation` | `take(_:)` / `ActionCardState.preValidate` / `InboxRefusal` + `Refused(nonce:)` |
| Undo restored the draft but always showed the small card | R-9: undo restores the **step** as well |
| The swipe hint showed on the first card of a fresh device | It shows the first time an **action card opens** — there is nothing to hint at on the small card |
| `InboxSession.Draft` (nested) | `InboxDraft` (top level, `+ notes`), with the nested name kept as a typealias for `FeatureReview` |

## `Esc` on the Mac (gotcha)

`.onKeyPress(.escape)` on the focusable card area is **not** how `Esc` arrives: while a
`TextField` is first responder (and `Why?` is, the moment the action card opens) the field editor
turns `Esc` into `cancelOperation:`, the handler never fires, and the macOS sheet dismisses itself
— the ladder is skipped and the session closes. `EscapeKeyMonitor.swift` (`onEscapeKey`, macOS
only) therefore takes `Esc` from a local `NSEvent` monitor scoped to the view's own window and
swallows it: one press, one rung, whatever has focus. A nested sheet is another window, so its
`Esc` is left alone; so is an `Esc` that cancels an input-method composition.
`.interactiveDismissDisabled()` sits under it as the net. After a blur or a collapse the view
takes key focus back (`hasKeyFocus`), so the single keys and the next `Esc` still land.
`InboxSessionView` and `MakeActionCardView` both use it.

## The chip walk on the Mac (#65)

`⌘↩` in `What?` with no input line left calls `NoteEditor.onAdvance`, which `InboxCardView` hands
to its host (`onLeaveFields`): the view drops field focus, takes key focus back and calls
`advanceKeyCursor()`. From then on `InboxSessionView.macContent`'s `.onKeyPress(keys: [.tab,
"\u{19}"])` (`⇧Tab` may arrive either as a shifted tab or as the back-tab character) and
`.onKeyPress(.return)` route to the session; `⌘↩` goes through `perform(.done)` →
`handle(.done)`, which walks while a cursor exists. The chips draw the cursor through
`ContextChipGroup`/`TimeBucketChipGroup(highlighted:)` → `Chip(isKeyHighlighted:)` and
`DesignSystem.keyHighlight(_:in:)`; the rows carry `CardField.contextChips`/`.timeChips` ids so
`MacCardScroll` scrolls the highlighted row into view. On the outcome row the Mac action bar is
replaced by `outcomeRow` (bordered buttons, `Next`/`Someday` fly like their keys). iOS draws
none of this. `MakeActionCardView` (L4) has no walk yet.

**#77 — the whole flow.** Step 1's `StepOneBar(highlighted:)` + the `Defer to review` text
button and the navbar's `KnowledgeListNavbar(highlighted:)` draw `session.barHighlight`; `Tab`
and `↩` reach the session through the same `.onKeyPress` handlers. The chip groups and the date
chips report clicks (`onTap`) to `InboxCardView.onPoint`, which the host turns into "blur the
field, take key focus, `pointKeyCursor(at:)`". **Gotcha:** key focus must be taken back a
run-loop turn *after* a field lets go (`takeKeyFocus()`): set in the same update as
`focus = nil`, SwiftUI drops it again and `Tab` lands nowhere (seen in the probe). The same
happens after the day picker or a sheet closes, so the view re-takes it on
`session.datePicker`/`session.sheet` becoming `nil`. The sheets (`ProjectChoiceSheet` — the inbox's
`ProjectSheet` now wraps it —, `ListChoiceSheet`, `KnowledgeSheet`, `DeferToReviewSheet`,
`CapSheet`, and `DesignSystem.WaitingInfoSheet`) are separate windows, so each applies
`keyWalkKeys(focus:onMove:onPress:onNextRow:onArrow:)` itself, draws the ring with
`keyHighlight`, shows `KeyWalkLegendLine`, and scrolls the ringed row into view through a
`ScrollViewReader` keyed on the stop. Where a sheet's buttons live only in the toolbar
(`Defer to review`'s `Defer`/`Cancel`, the Knowledge sheet's `Done`) the walk shows them again
inside the sheet so the ring has something to sit on.

## Sheets on the Mac (gotcha)

Every `Form` in `InboxSheets.swift` and `MakeActionProjectSheet` ends in
`DesignSystem.sheetFormStyle()`, every `List` sheet in `scrollingSheetFrame()`. Without the first,
macOS picks the `.columns` form style: it does not scroll (projects past the sheet's bottom edge
were unreachable on a real vault) and it draws `TextField("Pick a project", …)` as a label in a
left column. For the same reason the text fields in these forms pass their placeholder as an
explicit `prompt:` and are `.labelsHidden()` — in a Mac form the title alone becomes a row label,
not a placeholder. The search field is the form's first row: it scrolls with the list, and typing
filters the list back to the top. The sheets' keyboard walk is described above (#77); `Esc` and
`Cancel` are the stock sheet behaviour (a nested sheet is its own window, so `onEscapeKey` of the
session underneath ignores it). `InboxPreviews.swift` has `Project — 40 projects, must scroll`
and a crowded `Knowledge` preview, because the fixtures have too few projects to overflow.

## Platform guards (ARCHITECTURE §5)

`EscapeKeyMonitor.swift` is wrapped in `#if canImport(SwiftUI) && os(macOS)`.

`InboxProcessingView.swift`, `InboxCardView.swift`, `InboxSheets.swift`, `InboxPreviews.swift` and
`MakeActionCardView.swift` are wrapped entirely in `#if canImport(SwiftUI)`. T08 adapted the views
**mechanically** to the state machine (per-step bar, per-step keys, per-step legend, the collapse
gesture, the `More…` sheet) so the package kept building; **T09 designed them** per STYLEGUIDE
§3.5/§3.6: `InboxCardView.body` is step-aware (step 1 is the meta line + the editable title — the
file name — and, when it has content, the note's body, scrolling inside the card, and nothing else; step 2a adds `Why?`/`What?`/chips; step 2b adds `Notes`),
the three real bars (`DesignSystem.StepOneBar`/`ActionCardBar`/`KnowledgeListNavbar`) are wired in
place of the ad hoc `GlassActionBar` reconstructions T08 left, the bar cross-fades between steps
and the card expands with `Motion.standard`, every `Why?`/`What?`/`Context`/`Time` label carries
`SectionLabel(isMissing:)`'s asterisk, focus goes to `Why?` when the action card opens, and
`InboxSession.Sheet.fullText`/`FullTextSheet`/`Show all` are gone — the raw-text field scrolls
inside the card past a `@ScaledMetric` height cap instead. `MakeActionCardView` reuses the same
field-rendering code so the inbox and "Make action" (L4) never draw two different cards. Verified
live on an iPhone 18 Pro simulator (fixtures): step 1, the opened action card (typed `Why?`/
`What?`, toggled a context and a time chip, filed with a right swipe, saw the "Moved to Next"
toast), the refusal state (asterisks on all four labels after an empty-draft filing attempt), the
keep card with its navbar, the project picker (area-less project first, no header, then
`Applications`), and Trash with its undo toast. Verified live on a Mac walkthrough build: the
step-1 sheet (bordered `Action`/`Knowledge / List`/`Trash` + `Defer to review` beside them) and
the opened action card with its per-step key legend. Not confirmed by an on-screen tap in this
session: a Knowledge/List navbar slot, the Waiting sheet, the cap sheet, and the full Mac keyboard
path — see `docs/KNOWN_ISSUES.md`.

`InboxProcessingView` carries its own `.toolbar` (card counter, `⌘Z` undo, `Close`) but **does
not** wrap itself in a `NavigationStack`: the review wizard embeds it inline, where a second
navigation bar would be wrong. Every other presenter must supply one — `PhoneShell` and
`FeatureOverview` do.

**iPhone keyboard.** On iOS the card sits in a `ScrollView` (`InboxSessionView.phoneContent`):
the keyboard shrinks the viewport, never the card. Every card `TextField` is `fixedSize`
vertically and carries its `CardField` as `.id`, so the focused one is scrolled into view; the
keyboard goes away by dragging the content (`.scrollDismissesKeyboard(.interactively)`), by the
`Done` button that rides above the keyboard (`keyboardBar` in the bottom inset, `focus = nil` —
`ToolbarItemGroup(placement: .keyboard)` did not render inside `PhoneShell`'s full-screen cover)
or by a tap next to a field. The view mirrors focus into `InboxSession.isFieldFocused`, which is
what turns the swipes and the single keys off (STYLEGUIDE §3.6) — it is a model flag, not a view
check. The Mac layout (`macContent`: counter, card, per-step legend, key handling) has no scroll
view. Placeholders go through `prompt:` in `textTertiary` — on macOS a plain field otherwise
draws them like a value.

The one-time swipe hint is the **stored** `InboxSession.isSwipeHintVisible`; the device-local
flag behind it is written the moment the hint appears, and `dismissSwipeHint()` (or the first
card filed along the commitment axis) hides it.

Inbox zero is `DesignSystem.RewardMoment.inboxZero`, not a local drawing of it (STYLEGUIDE §5
allows exactly two reward moments, so there is exactly one implementation). The card drag
geometry is still local (`DragResolver` + the gesture in `InboxProcessingView`) rather than
`DesignSystem`'s `CardFilingController`/`.cardSwipeFiling` — see
`docs/history/build-out/ORCHESTRATOR-NOTES.md`.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureInboxTests` — 179 tests, all Linux-compilable.
`CardKeyCursorTests` covers the #65 chip walk: the pure row order and wrapping, and in the session
`⌘↩` walking vs. Done, `↩` toggling, a refusal moving the cursor, `Esc`, focus and the legend,
and (#77) the date row, a click moving the ring, step 1's and the navbar's bar walk.
`SheetWalksTests` pins each sheet's stop list.

`InboxSessionTests` pins one transition or one refusal at a time: the LIFO queue, every step
change, every exit of STYLEGUIDE §3.6's three tables, the validation flags and the asterisk
lifecycle, the cap's demote-or-cancel, the sub-flows, undo per R-9 and the per-step keys and
legend. `CardTargetsTests` covers the pure vocabulary — `InboxExit`'s step ownership, `KeyMap`
resolution per screen, `DragResolver`, the pickers.

`InboxSessionJourneyTests` is the other shape: a **whole session**, card after card, the way
`docs/MANUAL_TEST.md` §1 asks a person to drive it — inbox zero through every exit with the
summary adding up, the field-refusal → cap-sheet → demote → undo run in one go, five wrong-step
refusals leaving the vault untouched, and collapse-and-reopen keeping the draft. It is the
session-layer twin of `GTDServicesTests/InboxFlowJourneyTests`, which walks the same journeys
down to the bytes on disk; this target may not import `GTDVault`/`GTDServices` (ARCHITECTURE §2),
so the two halves live apart on purpose.
