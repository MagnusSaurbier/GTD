# ORCHESTRATOR-NOTES — cross-task findings for T40/T41/T42

<!-- REMOVE THIS FILE in T42 (docs handover) after folding anything durable into module READMEs / ARCHITECTURE §6. -->

# Orchestrator notes for T41 (QA) — accumulated from Wave 1/2 reports
- T20 inbox: InboxSessionView implements drag geometry + inbox-zero moment locally; adopt DesignSystem's CardDragGeometry/CardFilingController/CardSwipeFiling and RewardMoment (T12) instead. Local InboxPreviewData duplicates GTDFixtures (now a declared dep).
- T11: InMemoryBackend has a private copy of the undoable rule; delete it and call Rules.isUndoable.
- T11: extraOps .delete/trash and archive moves keep source file names — T16 must uniquify on collision (check T16 did).
- T11: future defer date on next/in-progress is refused (.invalid) — verify T21/T23 UIs surface AppModel.lastError.
- T14: captured/processed stat is an approximation (no filed-at timestamp) — documented; T27 should present it honestly.
- T13: T40 must re-run plan+sync on every snapshot change; notification actions (Start routine/Done) skipped as optional.
- T15: rollbackFailed must be shown to the user, never retried. No delete API on VaultFileSystem by design.
- T12: .glassEffect gated with #available + material fallback (deviation from ARCHITECTURE §1 "no fallbacks"); decide on Mac.
- T26: DeviceSettings gained vaultDisplayName; folder picker returns URL only (FeatureSettings must not import GTDVault) — T40 wires VaultBookmark.
- Blind-compiled files (highest risk): DesignSystem Components/Interaction/Colors/Typography; every Feature*Views.swift; GTDVault/Platform/*; GTDNotifications/SystemNotificationCenter.swift; App/GTDApp.swift.
- T25 → T40: share one OverviewNavigation between OverviewView and OverviewCommands; observe isCaptureRequested (⌘N) and route to capture; set \.vaultRootPath env; ⌘F query only reaches Overview lists (NextView/WaitingView/ProjectsListView ignore \.overviewQuery) — T41 could wire them.
- T24 → T40: host RoutinesHomeView directly; fresh run after midnight may re-ask a step done yesterday (vault one-log-per-day limitation, documented).
- T25: Why?/What? fields use plain TextField(axis:.vertical) since DesignSystem has no MarkdownTextEditor.
- T30 → T40: call `PendingRoute().consume()` on launch/foreground and route like onOpenURL/NotificationRoute; add a `gtd://inbox` route (not a NotificationRoute case today). RoutineDeepLink assumes VaultLayout.default. CaptureError.bookmarkStale unreachable because VaultBookmark.startAccess() folds stale into noVaultSelected (GTDVault fix, T41). No AppEntity for routines, no ControlWidget (needs widget extension).
- T21: NextListModel.setDefer demotes to Backlog first then sets the date; DesignSystem Copy/Symbols gained entries (checkboxOn/Off is a STYLEGUIDE §7 gap).
- T27: deferred-items step rebuilds the inbox decision via DeferredSweep (InboxSession queue not injectable); StalledSweep.addNextAction marks handled without a command — re-check against T22's WhatsNextSheet; systemFixNotes round-trip via encode(WeeklyReview) must be verified once T16 lands.
- T16: FeatureOverviewTests.ActionEditModelTests was FLAKY (~3/8 runs) — **fixed in T40** (contract change T40-2: AppModel serialises commands and gained send(deriving:); the autosave was racing another in-flight command, not refresh()). Nothing left for T41 here. Archiving leaves ProjectStep.promotedTo pointing at the old Actions/ path — reducer should retarget (T41). VaultBackend undo is 20 levels, InMemoryBackend one.
