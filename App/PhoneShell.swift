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

/// The iPhone (N5, E2, STYLEGUIDE §4.2): three tabs — **Inbox** (count + `Process inbox`),
/// **Next** (on-the-go; the tab the app opens on, E1 — `AppRouter.tab` starts at `.next`),
/// **Routines**. No full task overview, no settings tab: settings live behind the gear on Next,
/// and inbox processing and routines run full-screen.
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
    }

    // MARK: - Next (E2)

    private var nextTab: some View {
        NavigationStack(path: $router.nextPath) {
            NextView(
                mode: .onTheGo,
                onOpen: { router.nextPath.append($0) },
                onQuickCapture: { router.isCapturePresented = true })
                .navigationTitle(Copy.next)
                // P20 — a large title collapses on scroll; `.inline` or a pinned header cannot.
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            router.isSettingsPresented = true
                        } label: {
                            Label(AppCopy.settings, systemImage: Symbols.settings)
                        }
                    }
                }
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
    }

    // MARK: - Inbox (I1)

    private var inboxTab: some View {
        NavigationStack {
            InboxTabContent(onProcess: { router.isProcessingInbox = true })
                .navigationTitle(Copy.inbox)
                // P17 — captures land here, so this is where the capture button belongs too.
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            router.isCapturePresented = true
                        } label: {
                            Label(Copy.quickCapture, systemImage: Symbols.capture)
                        }
                    }
                }
        }
    }

    // MARK: - Routines (R2)

    private var routinesTab: some View {
        NavigationStack {
            RoutinesHomeView()
                .navigationTitle(AppCopy.routines)
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
                                Text(item.text)
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
private struct UndoOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: String?

    var body: some View {
        Group {
            if let shown {
                UndoToast(label: shown, onUndo: { Task { await model.undo() } })
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.l)
                    .transition(.opacity)
            }
        }
        .animation(Motion.standard(reduceMotion: reduceMotion), value: shown)
        .task(id: model.undoLabel) {
            shown = model.undoLabel
            guard shown != nil else { return }
            try? await Task.sleep(for: .seconds(MotionTiming.toastDuration))
            shown = nil
        }
    }
}
#endif
