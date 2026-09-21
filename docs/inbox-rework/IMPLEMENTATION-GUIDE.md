# Inbox rework — implementation guide for the managing agent

Written 2026-09-21. **You are the managing agent.** Your job is to get the 2026-09-21 revision of
`docs/REQUIREMENTS.md` and `docs/STYLEGUIDE.md` into the app by running the subtasks below through
subagents, one brief each, and verifying every result yourself. You write almost no code; you
brief, check, merge, and keep the log at the bottom of this file.

Start by reading, in this order: `CLAUDE.md`, `docs/CONTRIBUTING-AGENTS.md`,
`docs/ARCHITECTURE.md`, this file, then `docs/REQUIREMENTS.md` §4/§5/§5a/§6/§7/§10/§11 and
`docs/STYLEGUIDE.md` §3.3/§3.5/§3.6/§4. `docs/inbox-rework/DECISIONS.md` is the decision log
(D1–D43) with the reasons and rejected alternatives — consult it when a requirement looks odd.

## 1. What changes (the delta in one page)

| Area | Old | New | Req. |
| --- | --- | --- | --- |
| Tiers | `next` / `backlog` / `maybe` | `next` / **`someday`** (one "not now" tier) | A3 |
| Trash | `status: trash` + `GTD/Trash/` for inbox items | **not a status**; every trashed note moves to `GTD/Trash/`; still never hard-deleted, no purge | I4c, D41 |
| Inbox card | one card, 4 swipes + 4 buttons | **two steps**: step 1 buttons only (Action / Knowledge or List / Trash + quiet Defer link) → opened action card (→ Next, ← Someday, ↓ collapse, `Waiting`/`Done` buttons, `⋯`) or Knowledge/List card (notes + navbar) | I2–I4c |
| Title | derived from `What?` | **the capture text is the title** (editable); file renamed on filing, ≤ ~60 chars, full text kept in the note | I2, D27, D30 |
| Required fields | Next/Backlog need `What?` | **Next: Why? + What? + ≥1 context + time**; Someday: What?; Waiting: What? + follow-up date; Done/lists/Knowledge/Trash: nothing | I4, D12 |
| Cap | demote one **or** send card to Backlog | demote one **or cancel** — no "send to Someday instead" | I4, D14 |
| Defer × Next | reducer refuses a future `defer` on a Next item | **allowed** (see §3, ruling R-2) | I4, D15 |
| Done while processing | — | `Done` button files the card as `done`, nothing required | I4, D13 |
| Project in inbox | Project target → sheet (pick/create + first actions) | **`+ project` chip** → picker (area tree + search, inline `Create project "<text>"` with name only); card stays an action | I4a, D32–D35 |
| Waiting | who **and** follow-up date required | **follow-up date required, who optional** | W1, D39 |
| Lists | — | new: `Lists/<name>/` folders, items as notes, `Done/` log, Make action, favourites, iPhone tab + Mac sidebar row, never in review | §5a |
| Contexts | 8 incl. `reading` | **`reading` removed** (defaults and on-the-go set) | A4 |
| Projects | area-less at `Projects/<P>/`; area change refused | area-less in **`Projects/no_area/`**; **re-assigning an area moves the folder** | P1, D40, D42 |
| Knowledge filing | folder tree | + active projects' folders as targets; optional notes body | I4b |
| Review deck | Next ↔ Backlog ↔ Maybe | Next ↔ Someday, with staleness ordering + `untouched > 30 days` count | §10.2 |
| Mac keys | fixed map | new defaults (I9); inbox-flow + deck single keys **rebindable** in Settings › Keyboard, per device; `⌘` shortcuts fixed | N7, I9 |
| Session quit | toolbar `Done` | toolbar **`Close`** (`Done` now files a card) | STYLEGUIDE §3.6 |
| Migration | `04_Maybe → maybe`, `readlist → reading` | `04_Maybe` → **inbox captures**; `readlist` notes → `Lists/Read/`; `backlog`/`to-do` → `next`/`someday` | M1, M2 |

Out of scope, do not build: everything in REQUIREMENTS §12; a trash purge; a split-capture
function (I8); rebinding `⌘` shortcuts; adding list items from inside the Lists tab (not
required — items arrive through the inbox).

## 2. Rules for you, the manager

1. **Never read from or write to the real vault** (`~/Library/Mobile Documents/iCloud~md~obsidian/`),
   and never let a subagent do it. Requirements and style guide are already snapshotted into
   `docs/`. `Tools/migrate/migrate.py` is only ever run by its tests.
2. **Branch:** create `feature/inbox-rework` from the branch that is checked out when you start
   (`fix/walkthrough-2026-09-19`; it is far ahead of `main`). First commit = the already-modified
   `docs/REQUIREMENTS.md`, `docs/STYLEGUIDE.md` and `docs/inbox-rework/`. **One commit per
   subtask**, message `Rework T<nn>: <what>`, ending with the attribution line your session
   prescribes. **Do not push, do not open a PR, do not merge into `main`** — the user does that.
3. **Sequential by default.** T01–T05 change shared types and must run one after another. Tasks
   marked ∥ in §4 may run in parallel **only** in isolated worktrees, each touching only the paths
   its brief owns; merge them back one at a time and run the gate after each merge. When in doubt,
   run sequentially — the package build is fast, merge conflicts in `Copy.swift` are not.
4. **The gate** after every subtask, run by *you*, not trusted from the report:
   `scripts/check.sh` must exit 0. For every task marked **UI**, additionally build the app into
   a scratch location (never `scripts/check.sh --app` and never the default DerivedData — the
   user may be running their own instance from Xcode):

   ```bash
   xcodegen generate
   xcodebuild build -project GTD.xcodeproj -scheme GTD -destination 'platform=macOS' \
     -derivedDataPath "$TMPDIR/gtd-rework-dd" -skipMacroValidation \
     PRODUCT_BUNDLE_IDENTIFIER=com.magnussaurbier.gtd.walkthrough CODE_SIGN_IDENTITY=- | tail -30
   xcodebuild build -project GTD.xcodeproj -scheme GTD \
     -destination 'generic/platform=iOS Simulator' \
     -derivedDataPath "$TMPDIR/gtd-rework-dd" -skipMacroValidation | tail -30
   ```

   This Mac has Xcode 27 / Swift 6.4, so "written blind" no longer applies to new UI code: a UI
   task is not done until both builds are warning-free for the files it touched.
5. **Baseline first.** Before T01, run the gate and record the test counts per target in the log
   (§6). A later drop in a target's test count without an explanation in the task report is a
   failed task.
6. **Verify, don't relay.** For each finished subtask: read the diff (`git diff --stat`, then the
   risky files), run the gate, run the task's own acceptance checks, grep for leftovers the task
   was meant to remove. Reject with a precise list rather than fixing it yourself; after two
   failed rounds on a Sonnet task, re-run it on Opus with the two reports attached.
7. **Never:** disable, skip or weaken a test to get green; change `GTDMarkdown`'s round-trip
   guarantees; add a hard-delete path to `GTDVault`; let a feature target import `GTDVault` or
   `GTDServices`; put a literal string, colour, symbol name or size into feature code.
8. **When the requirements are silent or contradict the code,** use the rulings in §3. For
   anything not covered: choose the option that cannot lose or silently rewrite a note, record it
   as one row in `docs/ARCHITECTURE.md` §6 (with date), list it under "Decisions taken" in the
   log, and keep going. Stop and ask the user only if a choice would (a) write to existing vault
   files in a new way on first launch, or (b) contradict a D-numbered decision.
9. **Docs travel with the code.** Every brief ends with: fix the module READMEs,
   `docs/ARCHITECTURE.md` §3/§4/§6, `docs/TRACEABILITY.md` rows and `docs/KNOWN_ISSUES.md`
   entries your change made untrue. `scripts/check-docs.sh` (part of the gate) checks paths.
10. **Brief template** — give every subagent exactly this, filled in:
    *Read first* (CLAUDE.md, CONTRIBUTING-AGENTS, the module READMEs named, the REQUIREMENTS /
    STYLEGUIDE sections named, §3 of this guide) · *Goal* · *Owns* (paths) · *Must not touch* ·
    *Deliverables* · *Acceptance* · *Report back*: files changed, tests added (and proof one of
    them fails when the code is broken), decisions taken, anything not verified, tail of
    `scripts/check.sh`.

## 3. Rulings on points the requirements leave open

Made while planning; treat them as decided. Each becomes a row in `docs/ARCHITECTURE.md` §6 when
its task lands (the old rows they replace are edited, not kept alongside).

- **R-1 Legacy status values.** `GTDMarkdown` decodes `status: backlog` and `status: maybe` as
  `.someday` (tolerant read). Because the encoder only patches lines whose *decoded* value
  changed, such a file keeps its old word until the status really changes — no silent rewrite.
  `status: trash` on a note in `Actions/` decodes to a closed, hidden state that is not
  user-settable (keep it out of `ActionStatus.allCases`-driven UI); `archiveCompleted` moves such
  notes to `GTD/Trash/` instead of `Archive/`. Tests for all three.
- **R-2 Defer × Next.** Reverses the 2026-09-19 "refuse" decision (D15). A Next item may carry a
  future `defer`. While hidden it **does not count toward the cap**. On its date it reappears in
  Next with the `back` badge. If Next is then over the cap, nothing is demoted automatically:
  the existing over-cap signal (`16/15`) shows, and the Next view presents the `Next is full`
  sheet once per foreground until the user demotes something. Reducer + `Rules` + a
  `NextListModel` flag; the sheet is the same component the inbox uses.
- **R-3 Required fields live in the reducer.** `GTDError.missingFields([RequiredField])` is
  thrown for **every new transition into `next`** (inbox filing, Make action, promote in the
  deck, status change in the editor, step promotion) when Why?, What?, a context or the time
  estimate is missing, and for a transition into `someday` without What?. Notes that are
  *already* in Next with gaps are left alone (the vault stays repairable, as with the old
  defer rule). The inbox and Make-action cards handle the error themselves (shake + asterisks,
  STYLEGUIDE §3.6); every other caller uses `perform`/`report`, so the shell's alert names the
  missing fields — acceptable for v1, note it in `docs/KNOWN_ISSUES.md`.
- **R-4 Title and body on filing.** The note's title is the (edited) capture text: first line,
  sanitised by `VaultLayout.sanitize`, cut at a word boundary to ≤ 60 characters. If anything was
  cut, the full capture text is written as the first paragraph of the body, above `# Why?`
  (actions) or above the notes (Knowledge / list items), so nothing the user dictated is lost.
  The old "title derived from What?" logic (`ChecklistText` title derivation) goes away.
- **R-5 Lists are folders; the app needs a folder move.** A list is a direct subfolder of
  `VaultLayout.lists` (default `Lists`). `Done/` inside a list is reserved and is not a list.
  Rename list, remove list and "move project to another area" all need to move a directory, so
  `GTDVault` gains **one** new primitive, `VaultFileOp.moveFolder(from:to:)` — atomic directory
  rename through the coordinator, never overwriting, with an inverse for undo and rollback. It is
  still not a delete. **Remove list** = `moveFolder` into `GTD/Trash/` (free name, undoable,
  `confirmationDialog` in Settings because it takes items with it). Favourite lists and their
  order are synced config: `favouriteLists:` in `GTD/Config.md` (absent ⇒ the first four lists
  alphabetically — a derived default, never written until the user changes it).
- **R-6 `no_area` is a folder, not an area.** `VaultLayout.noAreaFolder = "no_area"`. The
  classifier never yields an `Area` for it (there is no `no_area/no_area.md`); a project inside
  it has `area == nil`. Projects that already sit directly under `Projects/` keep working and
  are **not** moved automatically; `docs/MANUAL_TEST.md` §9 gets a line telling the user to move
  them. New area-less projects are created in `Projects/no_area/`. An area cannot be named
  `no_area` (`.invalid`).
- **R-7 Changing a project's area** = one command, one commit: `moveFolder` of the project folder,
  every action's `project:` wikilink rewritten, promoted-step links untouched (they point at
  actions), a `RenameMap` entry for the project and every note inside its folder so open detail
  views survive, undoable as one journal entry. Renaming a project's *title* stays refused.
- **R-8 Project chip in the inbox.** `ActionDraft` gains the means to say "create a project with
  this name and link it" (mirror `ProjectDraft.newAreaTitle`). The old inbox **Project target**
  and its sheet (pick/create + first actions) are removed. `Turn into project` (A2) stays and
  keeps using `convertActionToProject` semantics. Delete the `InboxDecision` cases that become
  unreachable rather than leaving them dormant.
- **R-9 Undo across steps.** Undo returns the card to the head of the queue in the step it was
  filed from, draft intact: opened action card for Next/Someday/Waiting/Done, opened
  Knowledge/List card for list and Knowledge filings, small card for Trash and Defer.
- **R-10 Key bindings** are device-local (`DeviceSettings`), a table *command → key* with the
  defaults of REQUIREMENTS I9 and STYLEGUIDE §3.10. `KeyMap` resolves through the table; legends
  render from it. `Esc`, `Tab`, `⌘Z`, `⌘↩` are fixed. A duplicate within one screen is refused
  by the settings model, not by the view.

## 4. Subtasks

Order matters top to bottom. **Model** = recommended model for the subagent: Opus where the task
decides semantics, touches the codec/vault, or is a state machine; Sonnet where the brief fully
determines the result. **UI** = needs the two scratch app builds of §2.4.

| # | Task | Model | UI | Needs | Parallel |
| --- | --- | --- | --- | --- | --- |
| T00 | Branch, commit docs, baseline gate | you | — | — | — |
| T01 | Tiers: `someday`, trash-as-move, no `reading` | **Opus** | builds | T00 | — |
| T02 | Folder move primitive in `GTDVault` | **Opus** | — | T01 | — |
| T03 | Lists domain | **Opus** | — | T02 | — |
| T04 | Inbox & action semantics in the reducer | **Opus** | — | T03 | — |
| T05 | Projects: `no_area/` + area change | **Opus** | — | T02, T04 | — |
| T06 | DesignSystem: vocabulary, symbols, bars, asterisk | Sonnet | UI | T04 | ∥ with T07 |
| T07 | Key bindings model + `KeyMap` | Sonnet | — | T04 | ∥ with T06 |
| T08 | `InboxSession` two-step state machine | **Opus** | — | T04–T07 | — |
| T09 | Inbox views | Sonnet | UI | T08 | — |
| T10 | FeatureLists (new target) + shells | Sonnet | UI | T03, T06 | ∥ with T11, T12 (after T09) |
| T11 | Overview / Next / Waiting / Projects adaptations | Sonnet | UI | T05, T06 | ∥ |
| T12 | Weekly review deck | Sonnet | UI | T06, T07 | ∥ |
| T13 | Settings: lists, favourites, Keyboard pane | Sonnet | UI | T03, T07 | after T10–T12 |
| T14 | Migration script | Sonnet | — | T01 | any time after T01 |
| T15 | QA pass: journeys, walkthrough on fixtures, docs | **Opus** | UI | all | — |

### T01 — Tiers: `someday`, trash-as-move, no `reading` · Opus

The big rename; it has to land atomically so the package keeps building.
**Owns:** `GTDModel` (`Enums`, `Reducer`, `Rules`, `Signals`), `GTDMarkdown`, `GTDAppCore/UndoLabel`,
`GTDStats`, `GTDNotifications`, `GTDFixtures` (+ regenerate the sample vault), all their tests;
**plus the mechanical compile-fix** in `DesignSystem` and every `Feature*`/`App` file that names
`.backlog`/`.maybe`/`.trash` (rename, merge switch arms, drop the Maybe sidebar item and targets)
— no redesign there, that is T06–T12.
**Deliverables:** `ActionStatus` = `next, someday, inProgress, waiting, done` (+ the hidden legacy
state of R-1); tolerant decode per R-1; trashing an action or a list/inbox note = move to
`GTD/Trash/` via `extraOps`, undoable; `Rules.sidebarCounts` without backlog/maybe/with someday;
"stalled" rule: every `someday` action counts as *not open* (it replaces the old `maybe`
exception — record in ARCHITECTURE §6); `GTDConfig.default` without `reading`; a vault whose
`Config.md` still lists `reading` keeps it (it is the user's list) — only the default changes;
undo labels `Moved to Someday`. R-2 (Defer × Next) belongs here too.
**Acceptance:** `grep -rniw 'backlog\|maybe' Packages App AppTests AppUITests` hits only the
tolerant-decode code, its tests and migration inputs; round-trip/fidelity/patch/fuzz suites green
and extended with a `status: backlog` file that survives untouched; sample vault regenerated;
gate green; scratch app builds green (the mechanical fixes compile).

### T02 — Folder move primitive · Opus

**Owns:** `GTDModel/Commands` (`VaultFileOp`), `GTDVault` (`VaultFileSystem`, all three file
systems, `VaultTransaction`, `FileVaultStore`), `GTDServices` (diff/undo journal hashing for a
moved tree), tests. **Deliverable:** R-5's `moveFolder(from:to:)`: never overwrites, inverse op
in undo order, participates in all-or-nothing rollback, `CoordinatedFileSystem` uses one
coordinated move of the directory, undo-stale check covers the files inside. **Must not** add any
delete capability. **Acceptance:** transaction + fuzz tests extended; a commit of
`[moveFolder, put]` whose `put` fails leaves the tree where it was; `rollbackFailed` still surfaces.

### T03 — Lists domain · Opus

**Owns:** `GTDModel` (entities `GTDList`/`ListItem`, `VaultLayout.lists`, snapshot field,
commands, reducer, rules), `GTDMarkdown` (list-item note: title = filename, optional frontmatter
`created`, body = notes; unknown content round-trips), `GTDVault` (index/classifier: `Lists/<n>/*.md`
open, `Lists/<n>/Done/*.md` finished, nested deeper = ignored + `VaultIssue`), `GTDServices`,
`GTDAppCore` (undo labels `Added to <list>`, `Done`), `GTDFixtures` (Read/Watch/Wish with items,
one finished; regenerate sample vault), `GTDConfig.favouriteLists` (R-5).
**Commands:** `createList`, `renameList`, `removeList`, `setFavouriteLists`, `updateListItem`,
`completeListItem` (→ `Done/`), `trashListItem`, `promoteListItem(NoteID, ActionDraft)` (moves the
note to `Actions/`, then exactly the rules of an inbox action filing: R-3, cap), and
`InboxDecision.list(name:title:notes:)`. List items never appear in `Rules` queries for actions,
stats, notifications or the review. **Acceptance:** reducer tests per command incl. every
refusal; an end-to-end `GTDServicesTests` journey on a temp copy of the sample vault: file to
list → complete → undo → promote at cap → demote → lands in Next.

### T04 — Inbox & action semantics · Opus

**Owns:** `GTDModel` commands/reducer/rules for filing, `GTDAppCore` labels, tests.
**Deliverables:** R-3 (`missingFields`), R-4 (title/body), R-8 (project chip draft, removal of the
Project target decisions), Waiting with optional who (`WaitingInfo.who` optional; codec writes no
`waitingFor:` line when empty; W2 views must not print an empty who — see T11), inbox `Done`
filing, Knowledge filing with optional notes body and with a project folder as target, cap error
unchanged but the "send to backlog" path removed from the model layer. **Acceptance:** one reducer
test per row of §1's "Required fields"; title truncation tests (umlauts, long dictation, only
whitespace, collision → `titleCollision`); legacy inbox tests updated, none deleted without a
replacement.

### T05 — Projects: `no_area/` + area change · Opus

**Owns:** `GTDModel` (layout, reducer `createProject`/`updateProject`, rules `projectRows`),
`GTDVault` classifier/index, `GTDServices` tests, `FeatureProjects` model code only if it encodes
the old refusal. **Deliverables:** R-6, R-7. **Acceptance:** classifier tests (`no_area` is never
an area; top-level legacy project still indexed with `area == nil`); journey test: create project
by name only → lands in `Projects/no_area/` → assign area → folder moved, action links rewritten,
detail navigation remapped → undo restores everything byte for byte.

### T06 — DesignSystem · Sonnet · UI

**Owns:** `DesignSystem`. `Copy`/`Symbols` exactly per STYLEGUIDE §6.2/§6.3/§7 (add: Someday,
Lists, list symbols with `list.bullet` fallback for custom lists, Action kind, Knowledge / List
kind, More…, Back, Close, Make action, asterisk; remove Backlog/Maybe); `GlassActionBar` variants
for the three bars of §3.6 (equal neutral buttons; fixed-slot navbar); required-field label
decoration (leading `asterisk` in `signalAttention`); list-item row variant of `ActionRow`
(§3.3); `WaitingInfoSheet` per §3.6 (date required + suggested +7 d, who optional);
`ReviewPieces` wording; `DesignGallery` + previews for every new state. **Acceptance:** Linux-side
tests for new `Copy`/`Symbols`/`ChipState`-style logic; STYLEGUIDE §9 checklist in the report.

### T07 — Key bindings · Sonnet

**Owns:** `FeatureSettings/DeviceSettings` (+ store), `FeatureInbox/CardTargets.swift` (`KeyMap`
only), the deck's key resolution in `FeatureReview`. **Deliverable:** R-10: a `KeyBindings` value
(commands grouped by screen: inbox step 1, action card, Knowledge/List card, review deck),
defaults per I9/§3.10, `rebind` refusing duplicates per screen with the conflicting command in the
error, reset, persistence, legend strings generated from it. Pure, Linux-tested. No views.

### T08 — `InboxSession` two-step state machine · Opus

**Owns:** `FeatureInbox` non-UI files (`InboxSession`, `CardTargets`, `InboxPickers`,
`InboxCopy`) + `FeatureInboxTests`. **Deliverable:** the session as an explicit state machine —
`step1` / `actionCard` / `keepCard` — with: open, collapse (draft survives), exits per step
(STYLEGUIDE §3.6 tables), `DragResolver` reduced to → ← ↓ with ↓ = collapse and up = nothing,
validation mapping `missingFields` to per-field flags, cap flow (demote-and-retry or cancel),
Waiting/Done/Defer flows, project picker model (tree with area-less first and no header, search,
`Create project "<text>"` row only when no exact match), Knowledge tree + project folders section,
navbar model (Knowledge, ≤ 4 favourites on iPhone / ≤ 8 on Mac, More…), undo per R-9, swipe hint
state, mid-session capture rule unchanged. **Acceptance:** the existing invariants in
`FeatureInbox/README.md` still hold or are consciously replaced (say which); tests for every
transition and every refusal; test count does not drop.

### T09 — Inbox views · Sonnet · UI

**Owns:** `InboxProcessingView`, `InboxCardView`, `InboxSheets`, `InboxPreviews`, the target's
string catalog. Build STYLEGUIDE §3.5/§3.6 on top of T08 — the views hold no decisions. Expand in
place, three bars, asterisks, `Close` in the toolbar, per-step Mac legend from `KeyBindings`,
VoiceOver custom actions for every exit of the current step, Reduce Motion path, previews for
each step × platform × light/dark/AX1. **Acceptance:** scratch builds green; run the app with
`-useFixtures` (Mac: the walkthrough bundle id from §2.4; iOS: `simctl launch booted
com.magnussaurbier.gtd -useFixtures`, `gtd://inbox`) and file one card through each exit;
screenshots in the report.

### T10 — FeatureLists + shells · Sonnet · UI

New target `FeatureLists` (follow "Add a target" in `docs/CONTRIBUTING-AGENTS.md`): `ListsModel`
(Linux-tested), Lists home (lists with counts → items), item editor (title + notes), `Done` swipe,
`Show done`, context menu `Make action` / `Trash`; **Make action** presents the opened action card
— reuse `FeatureInbox`'s card through a small public entry point rather than copying it (agree the
API with what T08/T09 built; `FeatureLists` may depend on `FeatureInbox`, as `FeatureReview`
does). `App/PhoneShell`: fourth tab in the order Inbox · Next · Lists · Routines (Next still
selected on launch). `FeatureOverview`: `SidebarItem.lists` (single row, count = open items),
content column with one section per list, detail editor with `Make action`; `⌘1…7` order per
STYLEGUIDE §4.1. Update `AppUITests/ShellSmokeUITests`.

### T11 — Overview / Next / Waiting / Projects · Sonnet · UI

Everything outside the inbox that still thinks in the old terms: Someday list and empty states,
leading swipe `Someday`, `⌘⇧N/S` in `OverviewCommands`, R-2's cap sheet in `FeatureNext`,
Waiting views with optional who (row reads `<what>` alone when who is empty; chase title
`Chase: <what>`), project detail: area picker that issues T05's move (with the refusal surfaced),
project lists showing `no_area` projects first without a header, `WhatsNext`/promotion flows
handling `missingFields` via `report`.

### T12 — Weekly review deck · Sonnet · UI

`ReviewDeck`/`ReviewSweep`/`ReviewCopy`/views: Next (keep / demote) → Someday (promote / keep /
trash) → on-hold & someday projects; Someday ordered stalest first, project-linked before
unlinked (total order, no reliance on sort stability); header count `untouched > 30 days`; promote
handles the cap and `missingFields`; keys through `KeyBindings`; resumable state
(`ReviewSessionState`) migrates or discards an in-progress pre-rework deck without crashing —
test it with a stored old state.

### T13 — Settings · Sonnet · UI

Lists section (add, rename, remove with `confirmationDialog`, choose and order favourites with the
4/8 limits), contexts editor unaffected except defaults, **Keyboard** pane (Mac only) per
STYLEGUIDE §4.5 on top of T07. All decisions in `SettingsSession`-style models with tests.

### T14 — Migration script · Sonnet

`Tools/migrate/`: M1 — `readlist` notes go to `Lists/Read/` (frontmatter stripped to what a list
item carries, body kept), context map without `reading`, `to-do`/`backlog` → decided in review as
before but with `someday` as the fallback word; M2 — `04_Maybe` items become **inbox captures**
(one file each in `Inbox/`, timestamp names, body = old title + old body) instead of `maybe`
actions; generated `Config.md` without `reading`; report and README updated; pytest suite updated
(currently 40 tests — the count may change, the coverage may not shrink). **Never run the script
outside its tests.**

### T15 — QA pass · Opus · UI

Fresh eyes, no new features. (1) `EndToEndJourneyTests`: one journey through the whole new flow on
a temp vault (capture → step 1 → action card → cap → demote → Next; capture → list → Make action;
capture → Knowledge into a project folder; trash → undo; area change → undo). (2) Walk the app on
fixtures on Mac and the simulator against `docs/MANUAL_TEST.md`, which it first rewrites for the
new flow; fix what it finds or log it in `docs/KNOWN_ISSUES.md`. (3) Docs sweep: `CLAUDE.md`,
`README.md`, ARCHITECTURE §2 (19 targets) / §3 (vault layout: `Lists/`, `no_area/`, trash,
schema) / §4 / §6 (R-1…R-10 as rows, superseded rows edited), every module README,
`docs/TRACEABILITY.md` (new IDs N7, I4a–c, I8, I9, L1–L6; statuses now say **done** where a Mac
build verified them), `docs/follow-ups/50-mac-keyboard-map.md` reconciled with the new key map,
`TEST-INSTRUCTIONS.md` log entry. (4) Final: gate + both scratch builds + the grep of T01.

## 5. Definition of done (for you)

- Gate green on `feature/inbox-rework`; both scratch app builds green; test counts ≥ baseline in
  every pre-existing target, with the new targets' counts listed.
- Every row of §1 is demonstrably in the app on fixtures (T15's walkthrough says so, with
  screenshots) and every REQUIREMENTS ID touched has a truthful `docs/TRACEABILITY.md` row.
- No occurrence of Backlog/Maybe as a concept outside tolerant decode and migration input.
- The log below is complete. Your final message to the user: what was built, the decisions you
  took beyond §3, what is in `docs/KNOWN_ISSUES.md` because of this work, what only a human can
  check (real vault, device, Gate 3), and the reminder that **nothing was pushed**.

## 6. Manager's log (you keep this current; commit it with each task)

| Task | Status | Commit | Model used | Rounds | Notes |
| --- | --- | --- | --- | --- | --- |
| T00 | done | 8fa4105 | manager | 1 | gate green; baseline 904 Swift tests (Model 135, Markdown 115, Vault 113, Review 77, Projects 64, Overview 58, Services 54, Inbox 53, Stats 32, DesignSystem 30, Settings 30, Next 27, Notifications 27, AppCore 23, Intents 22, Waiting 21, Routines 17, Fixtures 6) — pytest is not installed on this Mac, so check.sh SKIPs the 40 migration tests (T14 runs them from a scratch venv); both scratch app builds green, one pre-existing warning (`FeatureNext/NextView.swift:446` separatorInset) |
| T01 | done | f78b347 | Opus | 1 | gate green, 920 tests, no target dropped; grep clean (only tolerant decode + its tests); both app builds green. `GTDCommand.trashAction` added; `SidebarItem.maybe` dropped; `Next is full` sheet for R-2 is only a `NextListModel` flag until T11; a stored pre-rework `DeckPhase` will not decode until T12 |
| T02 | done | 828b678^ | Opus | 1 | gate green, 945 tests (Vault 130, Services 63); no delete path added; `VaultStore.folderContents(_:)` added for the undo-stale guard; `scripts/check-docs.sh` now ignores `.claude/` (agent worktrees broke the gate); coordinated folder move never ran against a live iCloud vault |
| T03 | done | 48c6c1e | Opus | 2 | gate green, 1040 tests (Model 191, Markdown 139, Vault 143, Services 67). Round 1 rejected: sample vault's empty `Lists/Wish/` would vanish in a git clone — Wish got an item + a clone-fidelity test. `createList`/`setFavouriteLists` are not undoable; `VaultFileOp.createFolder` added (no inverse); action encoder appends headings below a promoted item's notes |
| T04 | done | 9658e01 | Opus | 1 | gate green, 1073 tests (Model 215, Markdown 145, Inbox 55); both app builds green. `InboxDecision` = action / knowledge / list / trash; filing moves the capture file; `Reduction.filedNotes` carries the Knowledge note; promotion sheets outside the inbox still offer `Send to Someday instead` (T11 to check against STYLEGUIDE) |
| T05 | done | d804276 | Opus | 1 | worktree, merged clean; gate green (1136 tests; Model 223, Vault 152, Services 71, Projects 67); both app builds green. `ProjectDetailModel.setArea(_:)` has no caller until T11; legacy top-level projects are never moved automatically (MANUAL_TEST §9 line added) |
| T06 | done | 38f8797 | Sonnet | 1 | worktree, merged clean; gate green (1113 tests, DesignSystem 46); both app builds green. New: `StepOneBar`, `ActionCardBar`, `KnowledgeListNavbar`, `NavbarLayout`, `SectionLabel`, `ListItemRow`, `shake(trigger:)`. Left for T09: `ItemCard`/`CollapsibleText` still truncates with `Show all` (§3.5 says the step-1 card scrolls instead) |
| T07 | done | e1616bc | Sonnet | 1 | worktree; merge conflicts with T04 in `CardTargets`/`InboxProcessingView` resolved by the manager (`P` opens the project sheet); gate green. `KeyBindings` lives in `GTDAppCore` (all three consumers depend on it; no Package.swift change). Legacy single-card letters still resolve via `CardTarget.key` until T08/T09 |
| T08 | **in progress** (started 2026-09-21, worktree, ∥ T05 — disjoint paths) | | Opus | 1 | |
| T09 | | | | | |
| T10 | | | | | |
| T11 | | | | | |
| T12 | **in progress** (started 2026-09-21, worktree, ∥ T05/T08 — its needs T06/T07 are in) | | Sonnet | 1 | |
| T13 | | | | | |
| T14 | done | 828b678 | Sonnet | 1 | worktree; 42 pytest green from a scratch venv (manager re-ran); script never writes `reading`/`backlog`/`maybe` |
| T15 | | | | | |

### Decisions taken beyond §3

- 2026-09-21 · T00 · `feature/inbox-rework` **is pushed** to `origin` after each finished epoch · the user asked for it in the session that ran this guide, overriding §2.2's "do not push"; still no PR and no merge into `main`.
- 2026-09-21 · T01 · a legacy `status: trash` note keeps the 30-day archive threshold, only its destination changes to `GTD/Trash/` · moving them at once would touch files on first launch unasked · ARCHITECTURE §6.
- 2026-09-21 · T01 · the sample vault keeps one `status: trash` note so R-1 is testable end to end · ARCHITECTURE §6.
- 2026-09-21 · T02 · `VaultStore.folderContents(_:)` is a required protocol member · the undo-stale guard of a folder move needs enumeration · ARCHITECTURE §6.
- 2026-09-21 · T02 · a commit that moves a folder away and writes a file back into its old path cannot be undone (refused, nothing changed) · undoing it would need a hard delete; no reducer emits such a pair · ARCHITECTURE §6.
- 2026-09-21 · T03 · `createList` is not undoable (`createFolder` has no inverse; the inverse would be a hard delete) · ARCHITECTURE §6.
- 2026-09-21 · T03 · list names compare case-insensitively; a case-only rename is refused · case-insensitive file systems · ARCHITECTURE §6.
- 2026-09-21 · T03 · `favouriteLists` is optional end to end: absent ⇒ derived default, `[]` is a real choice · ARCHITECTURE §6.
- 2026-09-21 · T03 · promoting a list item keeps its notes above the action headings · never drop user text · ARCHITECTURE §6.
- 2026-09-21 · T04 · step promotion obeys R-3; the step line fills an empty What?, so promoting into Someday always works and Next names the missing fields (`PromotionOutcome.missingFields`) · silently landing in Someday would rewrite the user's decision · ARCHITECTURE §6.
- 2026-09-21 · T04 · demoting an existing note is never blocked by required fields · an over-cap vault must stay repairable · ARCHITECTURE §6.
- 2026-09-21 · T04 · filing moves the capture file instead of delete + create; Knowledge notes travel as `Reduction.filedNotes` · keeps `created`/unknown keys, undo is one move · ARCHITECTURE §6.
- 2026-09-21 · T04 · check order: project active → missing fields → cap; a punctuation-only capture becomes `Untitled` with the text kept in the body · ARCHITECTURE §6.

_(one line each: date · task · decision · why — and the ARCHITECTURE §6 row it became)_
- 2026-09-21 · T07 · `KeyBindings` is a `GTDAppCore` type, persisted through `DeviceSettings` · FeatureInbox/Review/Settings all need it and may not depend on each other · ARCHITECTURE §6.
- 2026-09-21 · T05 · a stale `area:` key inside `Projects/no_area/` is reported as a `VaultIssue`, not corrected; `Projects/no_area/` is not a required folder (created by the first area-less project) · never rewrite a note unasked · ARCHITECTURE §6.
