#if os(iOS)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureInbox
import FeatureNext
import FeatureOverview
import FeatureRoutines
import FeatureSettings
import FeatureLists

/// The iPhone (N5, E2, STYLEGUIDE §4.2): five tabs, in order — **Inbox** (count +
/// `Process inbox`), **Next** (on-the-go; the tab the app opens on, E1 — `AppRouter.tab` starts
/// at `.next`), **In progress** (the board, #87), **Lists** (L5: lists with counts → items → item editor), **Routines**. No full
/// task overview, no settings tab: the settings gear and quick capture sit on every tab's root
/// screen (`tabToolbar`), and inbox processing and routines run full-screen.
struct PhoneShell: View {
    let composition: AppComposition
    @Bindable var router: AppRouter
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView(selection: $router.tab) {
            inboxTab
                .tabItem { Label(Copy.inbox, systemImage: Symbols.inbox) }
                .badge(Rules.inboxQueue(model.snapshot).count)
                .tag(AppTab.inbox)

            nextTab
                .tabItem { Label(Copy.next, systemImage: Symbols.next) }
                .tag(AppTab.next)

            inProgressTab
                .tabItem { Label(Copy.inProgress, systemImage: Symbols.inProgress) }
                .tag(AppTab.inProgress)

            listsTab
                .tabItem { Label(Copy.lists, systemImage: Symbols.listBullet) }
                .tag(AppTab.lists)

            routinesTab
                .tabItem { Label(AppCopy.routines, systemImage: Symbols.routineGeneric) }
                .tag(AppTab.routines)
        }
        // I1 — processing is a forced, full-screen session; the only way out is quitting it.
        // The `NavigationStack` is what renders `InboxProcessingView`'s own toolbar (the card
        // counter, `⌘Z` undo and `Done`); without it the session has no way out (T41).
        .fullScreenCover(isPresented: $router.isProcessingInbox) {
            NavigationStack {
                InboxProcessingView(onFinished: { router.isProcessingInbox = false })
            }
        }
        // N3 — processing begins on what the files say *now* (see `MacShell`).
        .onChange(of: router.isProcessingInbox) { _, began in
            guard began else { return }
            Task { await composition.refreshFromDisk() }
        }
        .sheet(isPresented: $router.isSettingsPresented) {
            PhoneSettingsSheet(composition: composition, router: router)
                .environment(model)
        }
        // N6 — the Next tab brings its own toast (T21) and processing has its own undo, so the
        // shell only covers the tabs that have none.
        .overlay(alignment: .bottom) {
            if router.tab != .next && !router.isFlowPresented {
                UndoOverlay()
            }
        }
        // The build's version, bottom right above the tab bar (`docs/TICKETS.md`: every issue
        // claims one). Same placement as the undo toast, so it clears the tab bar the same way.
        .overlay(alignment: .bottomTrailing) {
            if !router.isFlowPresented {
                VersionStamp()
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.l)
            }
        }
    }

    // MARK: - Next (E2)

    private var nextTab: some View {
        // No sidebar to drop a row on here; the rows' `Move to…` menu is the drag's twin, and
        // the dialogue a move needs (the action card, the project or list picker) is
        // presented over this tab (`FeatureInbox.moveNoteHost`).
        NavigationStack(path: $router.nextPath) {
            NextView(
                mode: .onTheGo,
                onOpen: { router.nextPath.append($0) })
                .tabToolbar(router)
                .navigationDestination(for: NoteID.self) { id in
                    // The editable, wrapping title in the detail *is* the title (P5); a second,
                    // truncated copy in the bar only repeats it. A rename moves the note (A1)
                    // and so changes this id: `AppRouter.apply(snapshot:renames:)` rewrites the
                    // path entry when the snapshot arrives, which is what keeps the detail open
                    // instead of landing on "Action is gone".
                    ActionDetailView(action: id)
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        // P7 — the detail's own bottom bar (Done / Trash) takes the tab bar's
                        // place, so nothing floats over the last row of the form.
                        .toolbar(.hidden, for: .tabBar)
                }
        }
        .moveNoteHost()
    }

    // MARK: - In progress (#87)

    /// The board as one list with a section per column; cards move between columns through
    /// their menu (`Move to column`), and the dialogue a move needs is presented over this tab.
    private var inProgressTab: some View {
        NavigationStack(path: $router.inProgressPath) {
            InProgressBoardView(onOpen: { router.inProgressPath.append($0) })
                .tabToolbar(router)
                .navigationDestination(for: NoteID.self) { id in
                    // Same as the Next tab's pushed detail.
                    ActionDetailView(action: id)
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(.hidden, for: .tabBar)
                }
        }
        .moveNoteHost()
    }

    // MARK: - Lists (L5)

    private var listsTab: some View {
        NavigationStack(path: $router.listsPath) {
            ListsHomeView()
                .tabToolbar(router)
                .navigationDestination(for: ListsRoute.self) { route in
                    switch route {
                    case let .list(name):
                        ListItemsView(list: name)
                    case let .item(id):
                        ListItemEditorView(item: id)
                            // P7 — same as the Next tab's pushed detail: the item editor's own
                            // toolbar takes the tab bar's place.
                            .toolbar(.hidden, for: .tabBar)
                    }
                }
        }
    }

    // MARK: - Inbox (I1)

    private var inboxTab: some View {
        NavigationStack {
            InboxTabContent(onProcess: { router.isProcessingInbox = true })
                .pinnedScreenTitle(Copy.inbox)
                .tabToolbar(router)
        }
    }

    // MARK: - Routines (R2)

    private var routinesTab: some View {
        NavigationStack {
            RoutinesHomeView()
                .tabToolbar(router)
        }
    }
}

private extension View {
    /// Every tab's root screen carries the same two buttons: the gear that opens settings
    /// (STYLEGUIDE §4.2: no settings tab) top leading, and quick capture (P17) top trailing.
    /// Pushed screens bring their own toolbars and don't get them.
    func tabToolbar(_ router: AppRouter) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.isSettingsPresented = true
                } label: {
                    Label(AppCopy.settings, systemImage: Symbols.settings)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.isCapturePresented = true
                } label: {
                    Label(Copy.quickCapture, systemImage: Symbols.capture)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

/// The inbox tab: the primary `Process inbox` button and the raw captures, read-only —
/// processing order is forced (I1), so tapping an item is not an entry point.
private struct InboxTabContent: View {
    let onProcess: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let today = model.today()
        let items = Rules.inboxQueue(model.snapshot)
        Group {
            if items.isEmpty {
                ContentUnavailableView(Copy.emptyInboxTitle, systemImage: Symbols.inbox)
            } else {
                VStack(spacing: Spacing.l) {
                    InboxStartButton(action: onProcess)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(Color.gtdAccent)
                        .padding(.horizontal, Spacing.screenMargin)
                        .padding(.top, Spacing.m)

                    List {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: Spacing.m) {
                                Text(item.title)
                                    .font(Typo.body)
                                    .foregroundStyle(Color.ink)
                                    .lineLimit(3)
                                Spacer(minLength: Spacing.s)
                                ForEach(
                                    Array(SignalPresentation.badges(
                                        for: Rules.signals(for: item, today: today),
                                        today: today).enumerated()),
                                    id: \.offset
                                ) { badge in
                                    Badge(badge.element)
                                }
                            }
                            .padding(.vertical, Spacing.rowVertical)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }
}

/// Settings behind the gear (STYLEGUIDE §4.2: no settings tab). The vault-issue list hangs off
/// it, because the iPhone has no sidebar to put it in.
private struct PhoneSettingsSheet: View {
    let composition: AppComposition
    @Bindable var router: AppRouter
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView(
                deviceSettings: Binding(
                    get: { composition.deviceSettings },
                    set: { composition.deviceSettings = $0 }),
                onChangeVault: {
                    dismiss()
                    Task { await composition.changeVault() }
                })
                .navigationTitle(AppCopy.settings)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(AppCopy.close) { dismiss() }
                    }
                    if !model.snapshot.issues.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                router.isIssuesPresented = true
                            } label: {
                                Label(AppCopy.vaultIssues, systemImage: AppSymbols.issues)
                            }
                        }
                    }
                }
                .sheet(isPresented: $router.isIssuesPresented) {
                    NavigationStack {
                        VaultIssuesView()
                            .navigationTitle(AppCopy.vaultIssues)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button(AppCopy.close) { router.isIssuesPresented = false }
                                }
                            }
                    }
                    .environment(model)
                }
        }
    }
}

/// N6 — the shell's undo toast, same component and timing as the Mac window's (STYLEGUIDE §3.8).
///
/// `.onChange(of: model.undoLabel)` rather than `.task(id:)` (T15 defect 2): this view mounts and
/// unmounts as `router.tab`/`isFlowPresented` toggle the `if` that wraps it in `PhoneShell`, and a
/// freshly mounted `.task(id:)` only reacts to the *next* change of its id — a mount that lands
/// with `model.undoLabel` already equal to the very label the next command is about to set again
/// (e.g. two list items finished in a row, both "Done") never restarts it, so the Lists tab (which
/// has no toast of its own) silently showed nothing. `onChange` fires on every distinct update
/// regardless of when this view mounted, matching `FeatureNext.NextView`'s own toast.
private struct UndoOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: String?
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let shown {
                UndoToast(label: shown, onUndo: {
                    dismissTask?.cancel()
                    self.shown = nil
                    Task { await model.undo() }
                })
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.l)
                .transition(.opacity)
            }
        }
        .animation(Motion.standard(reduceMotion: reduceMotion), value: shown)
        .onChange(of: model.undoLabel) { _, newValue in
            guard let newValue else { return }
            showToast(newValue)
        }
    }

    private func showToast(_ label: String) {
        dismissTask?.cancel()
        shown = label
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(MotionTiming.toastDuration))
            guard !Task.isCancelled else { return }
            shown = nil
        }
    }
}
#endif
