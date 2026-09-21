# Traceability — every requirement to the code that implements it

Covers `docs/REQUIREMENTS.md` v1 in full: every ID (N1–N7, C1–C4, I1–I7, I9, A1–A5,
P1–P7, L1–L6, W1–W2, D1–D3, E1–E4, R1–R6, §10's four steps, M1–M6) and §12's out-of-scope list.
(I8 — "captures containing several items" — predates this pass and still has no row; not part of
this update.)

Paths are relative to the repo root; `GTDKit/…` is short for
`Packages/GTDKit/Sources/…` and test names are suites under `Packages/GTDKit/Tests/`.

## How to read it

**Status** — about the code, not about the plan:

| | Meaning |
| --- | --- |
| **done** | Implemented, and covered by a test that runs in `scripts/check.sh`. |
| **done (blind)** | Implemented in platform-only code (`#if canImport(SwiftUI)` / `UserNotifications` / `AppIntents`) that **no machine in this project has ever compiled**. Its testable half is tested; the view is not. Confirmed by `TEST-INSTRUCTIONS.md` Gates 1–2 and `docs/MANUAL_TEST.md`, not by this repo. |
| **partial** | Something real is missing. Every one of these names a follow-up brief. |
| **missing** | Nothing implements it. |
| **out of scope** | REQUIREMENTS §12 or an explicit "v1: no" in the requirement itself. Deliberately absent; the check is that nothing implements it by accident. |

"done (blind)" is the honest status of most of the UI and is not a hedge: it is the direct
consequence of the app being written on Linux without an Apple SDK (`CLAUDE.md`).
`docs/history/build-out/41-qa-hardening.md` lists what was read rather than run.

## §2 Platform and data

| ID | Requirement | Implemented in | Tested by | Status |
| --- | --- | --- | --- | --- |
| N1 | macOS **and** iOS, fully offline | one multiplatform target (`project.yml`), `App/MacShell.swift` + `App/PhoneShell.swift`; no network code anywhere in the repo | — (no Apple SDK here) | **done (blind)** — Gate 2. Offline is structural: nothing in `Packages/` or `App/` opens a socket. |
| N2 | Markdown + YAML frontmatter in the vault, readable in Obsidian | `GTDKit/GTDMarkdown/` — `NoteCodec` patches the original file line by line out of `NotePassthrough` instead of re-serialising | `GTDMarkdownTests/RoundTripTests`, `FidelityTests`, `PatchTests`, `FuzzRoundTripTests` (~1 800 generated notes + every sample file damaged 12 ways) | **done** |
| N3 | Sync-safe: one writer per file, atomic writes, no shared append-only file | `GTDKit/GTDVault/` (`VaultTransaction`, `CoordinatedFileSystem`), routine log one file per day **per device** (`VaultLayout.routineLogPath`), undo refused on a changed file (`GTDServices/UndoJournal`) | `GTDVaultTests/TransactionFuzzTests` (600 op sequences), `GTDServicesTests/SyncScenarioTests` (6 scenarios: two devices, conflict copy, eviction, rename-while-open) | **partial** → `docs/follow-ups/53-stale-write-guard.md` |
| N4 | Replaces TaskNotes; the note-per-action data is kept | the whole app; the vault layout of ARCHITECTURE §3 is the existing one | `GTDVaultTests/SampleVaultScanTests` (a real vault tree scans to the expected snapshot) | **done** — a product statement, satisfied by N2 + M1–M6 rather than by code of its own. |
| N5 | Device split: iPhone capture/inbox/reduced Next/routines, Mac everything | `App/PhoneShell.swift` (three tabs), `App/MacShell.swift`, `Rules.onTheGoNextList` | `GTDModelTests/RulesTests`, `FeatureNextTests/NextListModelTests` (the on-the-go filter), `AppTests/AppShellTests` | **done (blind)** for the shells; the rule itself is **done**. |
| N6 | Undo for the last filing/status change | `Rules.isUndoable` (one definition, both backends), `GTDAppCore/UndoLabel`, `GTDServices/UndoJournal` (20 entries, hash-checked), `GTDAppCore/InMemoryBackend` | `GTDServicesTests/UndoTests`, `ParityTests`, `GTDAppCoreTests/AppModelAcceptanceTests` | **done** |
| N7 | Mac keybinds are rebindable in settings (defaults in I9) | `GTDAppCore/KeyBindings` (`KeyCommand`/`KeyScreen`/`KeyStroke`, R-10): pure `rebind`/`reset`/legend model, persisted per device via `FeatureSettings/DeviceSettings.keyBindings`; `FeatureInbox/CardTargets.KeyMap` and `FeatureReview/ReviewSession.choice(forKey:)` resolve a key press through it | `GTDAppCoreTests/KeyBindingsTests`, `FeatureSettingsTests/DeviceSettingsPersistenceTests`, `FeatureInboxTests/CardTargetsTests`, `FeatureReviewTests/ReviewDeckTests` | **partial** — the model, its persistence and both resolution points are **done**; the Settings › Keyboard pane a person actually rebinds a key in does not exist yet (`docs/inbox-rework/IMPLEMENTATION-GUIDE.md` §4 T13). `docs/follow-ups/50-mac-keyboard-map.md` is a different, unrelated gap (the fixed `⌘`-shortcuts of STYLEGUIDE §4.5). |

## §3 Capture

| ID | Requirement | Implemented in | Tested by | Status |
| --- | --- | --- | --- | --- |
| C1 | Shortcut on iPhone and Mac (global hotkey), under 3 s, app need not run | `GTDKit/GTDVault/InboxWriter` (writes without loading the vault), `GTDKit/GTDIntents/CaptureIntents`, `Shortcuts/README.md` recipes A/B (the Mac hotkey is assigned in Shortcuts.app) | `GTDVaultTests/InboxWriterTests`, `GTDIntentsTests/CaptureRequestTests`, `CaptureCodecRoundTripTests` | **done (blind)** for the App Intent; the writer is **done**. The 3 s budget is `docs/MANUAL_TEST.md` §5 — a stopwatch, not a test. |
| C2 | Voice dictation capture, stored as transcribed text | same path; `Shortcuts/README.md` "Dictate Text" variant + the Action Button row | `GTDIntentsTests/CaptureRequestTests` (the text path is identical) | **done** — dictation is Shortcuts' job; the app stores whatever text arrives. |
| C3 | One file per capture in `Inbox/`, timestamp name + `created` | `GTDModel/Core/VaultLayout.inboxPath`, `GTDVault/InboxWriter` (collision suffix `-n`) | `GTDVaultTests/InboxWriterTests`, `GTDModelTests/ReducerInboxTests`, `GTDServicesTests/EndToEndJourneyTests` | **done** |
| C4 | Photos / files / share sheet | — | a repo-wide grep for `PHPicker`, `UIActivity`, `photoLibrary` finds nothing | **out of scope** (§3 C4) |

## §4 Inbox processing

| ID | Requirement | Implemented in | Tested by | Status |
| --- | --- | --- | --- | --- |
| I1 | One item at a time, LIFO, forced order, no skipping; only exit is quitting | `Rules.inboxQueue` (LIFO, review-deferred excluded), `FeatureInbox/InboxSession` | `GTDModelTests/RulesTests`, `FeatureInboxTests/InboxSessionTests` | **done** |
| I2 | Card UI, editable capture text + `Why?` + `What?`; **the capture text is the title** and the file is renamed on filing (R-4) | `GTDModel/CaptureText` (title ≤ 60 characters, cut at a word boundary; the rest stays in the body), `Reducer.fileInbox`, `FeatureInbox/InboxStep` + `InboxSession` (the two-step state machine: open, collapse with the draft intact, per-step exits), `InboxCardView` over `DesignSystem.ItemCard` | `GTDModelTests/CaptureTextTests` + `ReducerInboxTests` (truncation, umlauts, multi-line, whitespace, collision), `GTDMarkdownTests/CaptureNoteTests` (the lead paragraph on disk), `FeatureInboxTests/InboxSessionTests` (every transition and every refusal) | **done** for the semantics and the **state machine** (T08); the card's *look* is **done (blind)** and is rebuilt in T09. |
| I3 | Chips for contexts and time bucket; optional defer, due, project | `DesignSystem/Components/Chip` + `ContextChipGroup`/`TimeBucketChipGroup`/`DateValueChip`, `FeatureInbox/InboxPickers` | `FeatureInboxTests/CardTargetsTests` (`InboxPickerTests`), `DesignSystemTests` | **done (blind)** for the controls; the state machine (`ChipState`, bucket mapping) is **done**. |
| I4 (fields) | **Required fields per tier** (R-3): Next needs `Why?` + `What?` + a context + a time estimate, Someday `What?`, Waiting `What?` + follow-up date, Done/lists/Knowledge/Trash nothing | `GTDModel.RequiredField.missing`, `GTDError.missingFields`, enforced in `Reducer.normalize` for every new transition into a tier, `FeatureInbox.ActionCardState` (`missingFields`/`isMissing(_:)` — a mark drops as soon as its field is filled — plus `shakeTrigger` and `focusRequest`), `DesignSystem.SectionLabel(isMissing:)` (the asterisk component, STYLEGUIDE §3.6) + `View.shake(trigger:)` (the validation shake, §3.6/§5) | `GTDModelTests/ReducerInboxTests` (one test per row, for inbox filing, `promoteListItem`, `promoteStep` and `setStatus`), `FeatureInboxTests/InboxSessionTests` (pre-validation, the reducer's refusal, the asterisk lifecycle, the focus request) | **done** for the semantics and the flag model (T08); drawing the asterisks and the shake on the card is T09 |
| I4a | Project chip: pick a project or create one **by name only**, in the same command (R-8) | `ActionDraft.newProjectTitle` + `Reducer.resolveProject` (area-less, via `addProject`), `InboxSession.chooseProject`/`createProject`, `FeatureInbox.ProjectPicker.model(_:search:)` (area-less first and headerless, search filters the tree, `Create project "<text>"` only when nothing matches exactly), `InboxSheets` picker view | `GTDModelTests/ReducerInboxTests`, `FeatureInboxTests/InboxPickerTests` + `InboxSessionTests`, `GTDServicesTests/VaultBackendScenarioTests` (project note, wikilink and undo on disk) | **done** for the semantics and the picker **model** (T08); the sheet's look is **done (blind)** and is rebuilt in T09 |
| I4b | Knowledge / List card: optional notes body, `Knowledge/**` **and an active project's folder** as targets | `InboxDecision.knowledge(KnowledgeTarget, notes:)` + `.list(name:notes:)`, `Reduction.filedNotes` (`GTDServices` encodes the note), `InboxSession` step `keepCard` (`InboxDraft.notes`, `confirmKnowledge`/`confirmList`, `navbarSlots`/`exits`/`allLists` over `NavbarLayout`, `KnowledgeTree.model(folders:projects:suggestion:)` — tree + `Projects` section + the last-used folder as a *suggestion*), `DesignSystem.KnowledgeListNavbar` | `GTDModelTests/ReducerInboxTests`, `GTDServicesTests/VaultBackendScenarioTests`, `DesignSystemTests/NavbarLayoutTests`, `FeatureInboxTests/InboxSessionTests` + `InboxPickerTests` | **done** for the semantics, the navbar model and the picker models (T08); the navbar and sheet views are T09 |
| I4 | The card's targets (Next / Someday / Waiting / **Done** / Knowledge / list / Trash) and the Next cap — demote one **or cancel**, never "send to Someday instead" | `FeatureInbox/CardTargets` (`InboxExit` — one case per row of STYLEGUIDE §3.6's three tables, each knowing its step; `CardTarget` for the summary/toast; `DragResolver` over a `DragContext`), `InboxSession.take(_:)` (the single entry point; an exit from the wrong step is refused), `InboxSheets` (knowledge tree with create, project picker, waiting, cap choice, `More…`), `Reducer.fileInbox` | `FeatureInboxTests/CardTargetsTests` + `InboxSessionTests` (every transition, every refusal, the cap's demote-or-cancel), `GTDModelTests/ReducerInboxTests`, `GTDServicesTests/VaultBackendScenarioTests` (files on disk) | **done** for the semantics and the state machine, **done (blind)** for the sheets |
| I5 | Defer to weekly review **with a reason** | `GTDCommand.deferInboxToReview`, `Rules.reviewDeferredInbox`, `FeatureReview/ReviewSweep` | `GTDModelTests/ReducerInboxTests`, `FeatureReviewTests/ReviewSweepTests` | **done** |
| I6 | Counter, undo last card — **undo returns the card in the step it was filed from** (R-9) | `InboxSession.counter` + `undo()` (the history entry carries the whole `ActionCardState` **and** the `InboxStep`), `DesignSystem.UndoToast` | `FeatureInboxTests/InboxSessionTests` (one test per exit kind: action card for Next/Someday/Waiting/Done, keep card for list/Knowledge, small card for Trash/Defer) | **done** |
| I7 | LIFO makes capture → process the "create action now" flow | `Rules.inboxQueue` ordering + `InboxSession` | `FeatureInboxTests/InboxSessionTests`, `GTDServicesTests/EndToEndJourneyTests` | **done** |
| I9 | Default Mac keys (rebindable, N7): step 1 `a k x d`, action card `→ ← Esc p w ⌘↩ Tab`, Knowledge/List navbar `1 2…9 0`, `⌘Z` undo | `GTDAppCore/KeyBindings.defaults` (`KeyCommand.defaultKey`) for the literal defaults; `Esc`/`Tab`/`⌘Z`/`⌘↩` are `KeyBindings.fixedKeys`, never rebindable | `FeatureInbox/KeyMap.resolve(_:step:bindings:)` resolves every letter and digit through the table for the **current step's** `KeyScreen`; `InboxSession.handle(…)` performs it and `legendString` renders it | `GTDAppCoreTests/KeyBindingsTests.defaultsMatchRequirementsI9`, `FeatureInboxTests/CardTargetsTests` (per-step resolution, a rebind, the fixed keys), `FeatureInboxTests/InboxSessionTests` (the keys' effects, the `Esc` ladder, the legend per step) | **done** for the defaults table (pinned by a test that fails if a default drifts from I9) and for inbox key routing (T08); **partial** — see N7 for the Settings pane gap. |

## §5 Actions

| ID | Requirement | Implemented in | Tested by | Status |
| --- | --- | --- | --- | --- |
| A1 | One note per action in `Actions/`, `# Why?` / `# What?` | `GTDModel/Entities.Action`, `GTDMarkdown/NoteCodec`, `VaultLayout.actionPath` | `GTDMarkdownTests/DecodeTests`, `EncodeFromScratchTests`, `GTDVaultTests/SampleVaultScanTests` | **done** |
| A2 | Second checkbox offers "Turn into project" | `Rules.suggestsProject`, `GTDCommand.convertActionToProject`, `FeatureProjects/ConvertToProjectModel` | `GTDModelTests/RulesTests`, `ReducerProjectTests`, `FeatureProjectsTests/ConvertToProjectModelTests` | **done** |
| A3 | Tiers (Next / **Someday** — one "not now" tier) and the hard Next cap of 15; trash is not a status (I4c) | `ActionStatus`, `Rules.countsTowardCap(_:today:)`/`isAtCap`/`capSignal` (a hidden deferred item holds no slot, R-2), the reducer's `checkCap` and `trashAction`, `FeatureSettings/NextCapPolicy` | `GTDModelTests/ReducerActionTests`, `RulesTests`, `GTDServicesTests/EndToEndJourneyTests` (the cap refuses and writes **nothing**) | **done** |
| A4 | Closed context list (no `reading`), chip picker, editable in settings; on-the-go subset | `GTDConfig.contexts`/`onTheGoContexts`, `FeatureSettings/ContextsEditing`, `GTDMarkdown.unknownContexts` | `FeatureSettingsTests/ContextsEditingTests`, `GTDModelTests/RulesTests` | **done** |
| A5 | Done vanishes immediately; files older than 30 days go to `Archive/YYYY/MM/` | `Rules.isVisible`/`archiveCandidates`/`closedDay`, `Reducer.archiveCompleted`, `GTDServices/Housekeeping` (once per day per device) | `GTDModelTests/RulesTests`, `GTDServicesTests/VaultBackendScenarioTests` (incl. a failed archive being retried at the next launch) | **done** |
| — | Dropped fields: `priority`, `type`, `tags`, `scheduled`, `Ressources` | — | a grep of `GTDModel` + `GTDMarkdown` finds none of them; unknown keys survive as passthrough instead (N2) | **out of scope** |

## §5a Lists

The domain landed with T03 (`GTDModel`/`GTDMarkdown`/`GTDVault`/`GTDServices`/`GTDFixtures`);
the views are T10 (Lists tab + Mac sidebar row) and T13 (settings: add / rename / remove /
favourites), so every row below says **domain done, UI pending**.

| ID | Requirement | Implemented in | Tested by | Status |
| --- | --- | --- | --- | --- |
| L1 | Lists hold items that are not commitments: no Why?/What?, no time, no cap, no `status` | `GTDModel.ListItem` (title, optional `created`, notes — nothing else), `GTDMarkdown.NoteCodec.decodeListItem`/`encode`, `DesignSystem.ListItemRow` (completion circle + title only, no second line/badges/age, STYLEGUIDE §3.3) | `GTDModelTests/ReducerListTests`, `GTDMarkdownTests/ListItemCodecTests`, `GTDModelTests/RulesListTests` (no action query, count or signal sees one) | **done** for the domain and the row component; the list screens and editor are **missing** → T10 |
| L2 | **Folders are the lists**: every subfolder of `Lists/` is one; settings add / rename / remove and choose favourites | `VaultLayout.lists`/`listFolder`/`listItemPath`, `GTDList`, `GTDCommand.createList`/`renameList`/`removeList`/`setFavouriteLists`, `GTDVault/VaultClassifier` + `VaultIndex` (empty folder = list; deeper nesting = `VaultIssue`), `GTDConfig.favouriteLists` + `Rules.favouriteLists` (R-5) | `GTDModelTests/ReducerListTests`, `RulesListTests`, `GTDVaultTests/ListsIndexTests`, `GTDServicesTests/ListJourneyTests` (folders on disk), `GTDMarkdownTests/ConfigFavouriteListsTests` | **done** for the domain; the settings section is **missing** → T13 |
| L3 | Finishing an item moves the note to `Lists/<name>/Done/` and keeps it as a log | `GTDCommand.completeListItem`, `VaultLayout.doneFolderName` (reserved), `ListItem.isFinished` from the path | `GTDModelTests/ReducerListTests`, `GTDVaultTests/ListsIndexTests`, `GTDServicesTests/ListJourneyTests` (a move, never a copy + trash) | **done** for the domain; the swipe and `Show done` are **missing** → T10 |
| L4 | "Make action" moves the note to `Actions/` and opens the normal action card (required fields, cap) | `GTDCommand.promoteListItem` — the note is moved and then goes through the *same* `makeAction` + `checkCap` as an inbox filing; `NoteCodec.encode(_ action:)` keeps the item's notes above `# Why?` | `GTDModelTests/ReducerListTests` (incl. the cap refusal), `GTDMarkdownTests/ListItemCodecTests`, `GTDServicesTests/ListJourneyTests` (cap → demote → Next), `FeatureInboxTests/MakeActionModelTests` | **done** for the domain and for the card entry point `FeatureInbox.MakeActionModel` (T08 — the opened action card alone over a `ListItem`, reusing `ActionCardState`/`ActionCardEngine`); the list **screens** that present it are **missing** → T10 |
| L5 | Lists fully available on iPhone (browse, finish, promote, edit) | `Rules.listRows`/`listItems`/`openListItemCount`, `GTDCommand.updateListItem`/`completeListItem`/`trashListItem`/`promoteListItem` — all platform-free | `GTDModelTests/RulesListTests`, `ReducerListTests` | **done** for the domain; the fourth tab is **missing** → T10 |
| L6 | Lists **never** appear in the weekly review | structural: `ReviewDeck.cards` deals `snapshot.actions` and `snapshot.projects`, and a list item is neither | `FeatureReviewTests/ListItemsNeverEnterTheDeckTests`, `GTDStatsTests/ListItemsAreInvisibleToStatsTests`, `GTDNotificationsTests/ListItemsAreInvisibleToNotificationsTests`, `GTDModelTests/RulesListTests` | **done** |

## §6 Areas and projects

| ID | Requirement | Implemented in | Tested by | Status |
| --- | --- | --- | --- | --- |
| P1 | Two levels: areas contain projects, both folders under `Projects/`; area-less projects live in `Projects/no_area/` (a folder, never an area — R-6), and assigning an area later **moves the project's folder** (R-7, D42) | `VaultLayout.noAreaFolderName`/`projectPath`/`isAreaLessProjectPath`, `Reducer.addProject`/`addArea`/`updateProject` (one `VaultFileOp.moveFolder` + rewritten `project:` links + `Reduction.renames`), `GTDVault/VaultClassifier.noAreaNote` + `VaultIndex`, `Rules.projectRows` (area-less first), `FeatureProjects/ProjectDetailModel.setArea` + `AreaPicker`/`AreaPickerContent` (T11) | `GTDModelTests/ReducerProjectTests` (R-7 incl. collision, legacy top-level project, unknown area), `RulesTests`, `GTDVaultTests/NoAreaIndexTests`, `GTDServicesTests/ProjectAreaJourneyTests` (folder move + undo byte for byte, on a temp vault), `FeatureProjectsTests/ProjectDetailModelTests`, `AreaPickerContentTests` | **done** end to end: the model/vault/services layers (T05) and the project detail's area picker (T11), which surfaces `titleCollision`/`notFound` inline and never offers a "No area" list row. |
| P2 | Project note: outcome + why, steps, status, log | `NoteCodec.decodeProject`/`encode`, body sections `# Outcome`/`# Why?`/`# Steps`/`# Log` | `GTDMarkdownTests/RoundTripTests`, `DecodeTests` | **done** |
| P3 | Four statuses; only **active** projects put actions into Next | `ProjectStatus`, `Reducer.updateProject` + `normalize` (leaving `active` demotes its Next actions) | `GTDModelTests/ReducerProjectTests`, `RulesTests` | **done** |
| P4 | Steps are checklist lines; promotion; parallel actions; stalled badge (a `someday` action is not a commitment, so it leaves a project stalled) | `ProjectStep.promotedTo`, `GTDCommand.promoteStep`, `Rules.openActions`/`isStalled`/`stalledProjects` | `GTDModelTests/ReducerProjectTests`, `RulesTests`, `FeatureProjectsTests/ProjectsListModelTests` | **done** |
| P5 | Completing a project action prompts "What's next for …?" | `AppPrompt.whatsNext` from `Reducer.complete`, `FeatureProjects/WhatsNextModel` | `GTDModelTests/ReducerActionTests`, `FeatureProjectsTests/WhatsNextModelTests` | **done** — T11 confirmed `WhatsNextModel.promote`/`createAction` already answer `.missingFields` through `PromotionOutcome` (R-3) rather than swallowing the refusal; no change needed. |
| P6 | Mac project view: header, inline step edit/reorder/promote, reference files, dated log | `FeatureProjects/ProjectViews` + `ProjectDetailModel` + `StepReorder`; `Project.referenceFiles` filled by `VaultIndex` | `FeatureProjectsTests/ProjectDetailModelTests`, `StepReorderTests`, `GTDVaultTests/VaultIndexTests` | **done (blind)** for the view; models and reference-file collection are **done**. |
| P7 | Project deadlines / milestones | — | no `milestone`/`deadline` anywhere | **out of scope** (P7) |
| — | Renaming a project | refused by `Reducer.updateProject` (`.invalid`) | `GTDModelTests/ReducerProjectTests` | **deferred by design** — ARCHITECTURE §6 "Project rename": the folder is the project's identity. Changing a project's *area* is no longer blocked by the file system — `VaultFileOp.moveFolder` (R-5) exists — and lands as a command in T05; the title stays refused. |

## §7 Waiting-for, dates, tickler

| ID | Requirement | Implemented in | Tested by | Status |
| --- | --- | --- | --- | --- |
| W1 | `waiting` requires a **follow-up date**; who is **optional** (D39); +7 days is the suggestion | `WaitingInfo.who: String?`, `GTDError.missingFields([.followUpDate])`, the codec writes no `waitingFor:` line for an empty who, `DesignSystem/WaitingInfoSheet` (the +7 d is a **suggested**, dashed chip — never persisted until tapped) | `GTDModelTests/ReducerActionTests` + `ReducerInboxTests`, `GTDMarkdownTests/CaptureNoteTests` (no line on disk), `FeatureOverviewTests/ActionEditModelTests`, `GTDServicesTests/EndToEndJourneyTests` | **done** |
| W2 | Waiting view sorted by staleness; overdue follow-ups surface in Next as "chase" | `Rules.waitingList`/`chaseItems`/`waitingSince`, `FeatureWaiting/WaitingListModel.metaParts`, `FeatureNext/NextListModel.chaseTitle` + `NextView` chase section | `GTDModelTests/RulesTests`, `FeatureWaitingTests` (`rowMetaNamesWhoWhenPresentAndOmitsItWhenNot`, `metaPartsForActionCombinesWaitingForAndTheComputedAge`), `FeatureNextTests/NextListModelTests` (`chaseTitleNamesWhoWhenPresentAndOmitsTheDashWhenNot`) | **done**; T11 built the who-optional row text and the `Chase: <who> — <what>` / `Chase: <what>` title as pure, tested functions — the waiting row never prints a dangling "— " and the chase row now actually shows the STYLEGUIDE §3.3 title (it previously fell back to the plain action title). |
| D1 | `defer` hides until the date, then a badge; `due` warns as it approaches. A Next item may be deferred (R-2): it holds no cap slot while hidden | `Rules.isVisible`/`deferredList`/`countsTowardCap(_:today:)`/`signals`/`returnedFromDeferBadge`, `StalenessPolicy`, `FeatureNext/NextListModel.showsCapSheet` | `GTDModelTests/RulesTests` (`SignalRuleTests`), `ReducerActionTests`, `FeatureNextTests/NextListModelTests`, `DesignSystemTests/SignalPresentationTests` | **done** for the model; the `Next is full` sheet itself is wired in T11 |
| D2 | Local notifications for defer returns, deadlines and follow-ups | `GTDKit/GTDNotifications/NotificationPlanner` (pure, fully tested) + `SystemNotificationCenter`, `App/NotificationService.swift`, `FeatureSettings` toggles | `GTDNotificationsTests/NotificationPlannerTests`, `NotificationSchedulerTests`, `NotificationRouteTests` | **partial** — no actions on the notification itself → `docs/follow-ups/52-notification-actions-and-widget.md`. Scheduling and routing are **done (blind)**. |
| — | Apple Calendar / Reminders sync | — | no `EventKit` anywhere | **out of scope** (§12) |
| D3 | Mac calendar strip: defer, due, follow-up on one timeline | `Rules.timeline`, `FeatureOverview/OverviewCalendarStrip` (the docked Mac strip; `FeatureWaiting/CalendarStrip` is the older layout) + `WaitingListModel.timeline(days:)` | `GTDModelTests/RulesTests`, `FeatureWaitingTests` | **done (blind)** for the strip; the query is **done**. |

## §8 Engage views

| ID | Requirement | Implemented in | Tested by | Status |
| --- | --- | --- | --- | --- |
| E1 | Next view with context and time chips; plain list; max 15 + chase, R-2's cap sheet when a deferred item returns into a full Next | `Rules.nextList` (+ the total order of ARCHITECTURE §6), `FeatureNext/NextView` + `NextListModel` + `NextFilterStore` + `NextCapSheet` (T11) | `GTDModelTests/RulesTests`, `FeatureNextTests/NextListModelTests` (incl. `theCapSheetIsOfferedOncePerForegroundUntilSomethingIsDemoted`) | **partial** — `⌘F` does not reach this list → `docs/follow-ups/51-search-across-lists.md`. The view is **done, Mac-build-verified** (T11 built and warning-free); the list is never truncated to the cap by decision (ARCHITECTURE §6 "Next list order"). |
| E2 | iPhone: Next hard-filtered to on-the-go contexts, tick off, no full overview | `Rules.onTheGoNextList`, `App/PhoneShell.swift` (three tabs only) | `GTDModelTests/RulesTests`, `FeatureNextTests/NextListModelTests` | **done** for the rule, **done (blind)** for the shell |
| E3 | Mac: sidebar with live counts, list, preview/editor; grouped by area/project | `Rules.sidebarCounts`, `FeatureOverview/OverviewView` (three-column `NavigationSplitView`), `SidebarItem`, `ActionListModel` (grouping), `ActionDetailView` + `ActionEditModel`, `OverviewCommands` (`⌘⇧N`/`⌘⇧S`, T11) | `GTDModelTests/RulesTests`, `FeatureOverviewTests/SidebarRoutingTests`, `ActionListModelTests`, `ActionEditModelTests` | **partial** — three of the five shortcuts of STYLEGUIDE §4.5 are still not in the menu bar (`⌘⏎`, `⌘⇧W`, `Space`) → `docs/follow-ups/50-mac-keyboard-map.md` (T11 added `⌘⇧N`/`⌘⇧S`); `⌘F` → `docs/follow-ups/51-search-across-lists.md`. Everything else is **done, Mac-build-verified**. |
| E4 | Projects list: project, its active actions, remaining steps, stalled badge; Someday list + empty state (E1's tier, shown here since `ActionListView` is shared) | `Rules.projectRows`, `DesignSystem.ProjectRow`, `FeatureProjects/ProjectsListModel`, `FeatureOverview/ActionListView` (`Copy.emptySomedayTitle`, T11) | `GTDModelTests/RulesTests`, `FeatureProjectsTests/ProjectsListModelTests` | **done** |

## §9 Routines

| ID | Requirement | Implemented in | Tested by | Status |
| --- | --- | --- | --- | --- |
| R1 | Routines defined as markdown templates in the vault (Morning, Bedtime) | `GTD/Routines/<Name>.md` (ARCHITECTURE §3), `NoteCodec.decodeRoutine`, `GTDFixtures` sample vault | `GTDMarkdownTests/DecodeTests`, `GTDVaultTests/SampleVaultScanTests` | **done** |
| R2 | Step-by-step cards, big done/skip, sub-steps inline | `FeatureRoutines/RoutineViews` over `ItemCard` + `GlassActionBar`; `RoutineRun` drives it | `FeatureRoutinesTests/RoutineRunTests` | **done (blind)** for the cards; the run is **done**. |
| R3 | Start via scheduled notification **and** home-screen button / Shortcut | `NotificationKind.routineStart` + `RoutineDeepLink` (`gtd://routine/<path>`), the iPhone Routines tab, `GTDIntents.StartRoutineIntent` | `GTDNotificationsTests/NotificationRouteTests`, `GTDIntentsTests/DeepLinkTests`, `PendingRouteTests` | **partial** — no Control Centre widget and no Shortcuts picker for routines → `docs/follow-ups/52-notification-actions-and-widget.md`. Notification, tab and intent are in place. |
| R4 | Journaling steps have no text input (journaling is on the reMarkable) | `RoutineStep.isJournaling` only changes the meta line; **no** routine step anywhere takes text | `FeatureRoutinesTests/RoutineRunTests` | **done** |
| R5 | Log done/skipped per step per day, sync-safe | `GTD/RoutineLog/<day>--<device>.md`, `Reducer.logRoutineStep`, `SnapshotDiff.appendRoutineLog` (a device only ever rewrites its own file) | `GTDModelTests/ReducerSystemTests`, `GTDServicesTests/SyncScenarioTests` (two devices, same day), `GTDMarkdownTests` | **done**, with one documented limitation: a run left open across midnight may re-ask a step logged before midnight (`GTDKit/FeatureRoutines/README.md`). Each entry still carries its own real day, so no log is ever wrong. |
| R6 | Routines never appear in action lists | routines are a separate collection in `VaultSnapshot`; `GTD/` is not `Actions/` (`VaultClassifier`) | `GTDModelTests/ReducerSystemTests`, `GTDVaultTests/VaultPathTests` | **done** — structural: there is no path by which a routine could become an `Action`. |

## §10 Weekly review

| Step | Requirement | Implemented in | Tested by | Status |
| --- | --- | --- | --- | --- |
| 10.1 | Sweep: inbox to zero, review-deferred items with their reason, waiting chase/bump/resolve, stalled projects | `FeatureReview/ReviewSweep` + `ReviewSession` (§10.1.1–10.1.4), embedding `FeatureInbox`'s card and `FeatureProjects`' `WhatsNextSheet` | `FeatureReviewTests/ReviewSweepTests`, `ReviewSessionTests` | **done** |
| 10.2 | Deck: Next → Someday → on-hold & someday projects; ends with Next ≤ 15; Someday ordered stalest first, project-linked before unlinked, with an `untouched > 30 days` count; promote handles the cap (forced choice) and `missingFields` (named inline, `Edit`/`Keep`); keys through `KeyBindings` (rebindable, R-10) | `FeatureReview/ReviewDeck` (`stalestFirst`, `untouchedOver30DaysCount`), `ReviewSession` (`capChoice`/`capCard`/`missingFieldsIssue`, the deck cannot be left over cap), `ReviewDeckViews` | `FeatureReviewTests/ReviewDeckTests`, `ReviewSessionTests` | **done**, verified on a Mac build (T12) |
| 10.3 | Systems check: three prompts + live stats + per-step 7-day routine heatmap | `FeatureReview/ReviewSystemsViews` + `ReviewStats`, `GTDKit/GTDStats/` (`WeeklyStats`, routine audit), `DesignSystem.RoutineHeatmap` | `GTDStatsTests/WeeklyStatsTests`, `RoutineAuditTests`, `FeatureReviewTests/ReviewStatsTests`, `DesignSystemTests/AccessibilityTextTests` | **partial** — "captured vs processed" is an approximation the vault format cannot improve on → `docs/follow-ups/54-filed-at-record.md`. Everything else, including the heatmap and the trend, is exact. |
| 10.4 | Reflection: reMarkable reminder, the eight questions with last week's goal alongside, saved as `KW xx.md` | `FeatureReview/ReviewReflectionViews` + `ReviewSessionState` (the eight questions as cases), `NoteCodec.encode(WeeklyReview)`, `GTD/Reviews/<yyyy>/KW <ww>.md` | `FeatureReviewTests/ReviewNoteTests`, `GTDServicesTests/EndToEndJourneyTests` (the note is decoded back off disk and re-scanned cold) | **done** |
| — | Resumable | `FeatureReview/ReviewStateStore` (Application Support, never the vault), `ReviewResumeBanner`, `ReviewSessionState.migratedPage(fromRaw:)` (a pre-rework stored `page` — e.g. the removed `deckBacklogMaybe` — migrates or restarts the deck stage instead of crashing or discarding the sweep) | `FeatureReviewTests/ReviewStateStoreTests` | **done** |

## §11 Migration (one-time)

All six live in `Tools/migrate/migrate.py`, dry-run by default, backup before `--apply`, nothing
ever deleted. Tests are `Tools/migrate/tests/` (42 tests: `python3 -m pytest -q`).

| ID | Requirement | Status |
| --- | --- | --- |
| M1 | Normalize `Actions/` frontmatter (contexts → enum without `reading`, `timeEstimate: 0` → empty, drop `priority`/`type`/`scheduled`, `to-do` → `someday` fallback); `readlist` notes move to `Lists/Read/` as list items instead | **done** — an unknown context is never guessed; it goes to "needs a decision". `someday`/`backlog`/`maybe` are never written except the one `someday` fallback (R-1). |
| M2 | Import `Actions_legacy/03_Waiting` → `waiting`, strip boilerplate; `04_Maybe` items become inbox captures (body = old title + old body) run through the new inbox flow, not `status: maybe` | **done** — who/follow-up are deliberately left empty for the first review (W1's values are not inventable). |
| M3 | Remove the duplicates in `01_Next_Actions`; keep `02_Done` read-only | **done** — "removed" means "only in the backup". |
| M4 | `Inbox.md` lines → one file each; resolve the dangling links | **done** — a dangling link is reported, never guessed. |
| M5 | Classify `Projects/` into areas vs projects, create project notes | **done** — proposes, never decides: the user writes `projects.decisions.yaml`. |
| M6 | Four empty-body action notes go back to the inbox | **done** |

**In the gate, when `pytest` is installed.** `scripts/check.sh` runs `Tools/migrate/tests`
(42 tests) if it finds a `pytest` on `PATH` or in `~/.local/bin`, and prints `SKIPPED` with the
command to run by hand otherwise. Run them either way before pointing the script at real data —
`docs/MANUAL_TEST.md` §9 step 3.

## §12 Out of scope for v1

The check here is the opposite of the rest of this file: that **nothing implements them**. A
repo-wide grep over `Packages/GTDKit/Sources` and `App/` for `openai`, `anthropic`, `llm`,
`embedding`, `EventKit`, `Reminders`, `CRM`, `energy`, `milestone`, `recurring`, `PHPicker`,
`photoLibrary`, `UIActivity` finds **no matches**.

LLM filing suggestions · LLM/embedding search · people & CRM · energy field · photo/file/share-sheet
capture · Calendar/Reminders sync · project deadlines & milestones · automatic reMarkable parsing ·
recurring actions · in-app routine editor · processing and routine-step timers — all absent, all
deliberate.

Two related decisions worth knowing, because they look like scope creep and are not:

- the **routine editor** is out of scope, but routine *times* are editable in Settings
  (`setRoutineTime`) because R3 needs them;
- **timers** are out of scope, but the inbox-zero reward moment reports the session's minutes
  (STYLEGUIDE §5.1 asks for `14 processed · 6 min`). It measures, it does not limit.

## Follow-ups this file opened

| Brief | Closes | Blocked on |
| --- | --- | --- |
| `docs/follow-ups/50-mac-keyboard-map.md` | E3 (STYLEGUIDE §4.5) | Gate 2 — focus cannot be written blind |
| `docs/follow-ups/51-search-across-lists.md` | E1, E3 (`⌘F`) | Gate 2 |
| `docs/follow-ups/52-notification-actions-and-widget.md` | D2, R3 | Gate 2 |
| `docs/follow-ups/53-stale-write-guard.md` | N3 | nothing |
| `docs/follow-ups/54-filed-at-record.md` | §10.3 | two real weekly reviews first |
| `docs/follow-ups/55-incremental-reindex.md` | performance (non-functional) | nothing |

## What this file cannot tell you

Every "done (blind)" row is a statement about code that compiles nowhere in this project. The
matrix says the requirement is *implemented*; only a Mac says it *works*. The order to find out
in is `TEST-INSTRUCTIONS.md` → "Where to look first", then Gates 1–3, then
`docs/MANUAL_TEST.md` — whose §9 is the first-real-use checklist for the actual vault.
