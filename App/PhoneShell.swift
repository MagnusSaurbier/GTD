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

/// The iPhone (N5, E2, STYLEGUIDE §4.2): three tabs — **Next** (on-the-go), **Inbox** (count +
/// `Process inbox`), **Routines**. No full task overview, no settings tab: settings live behind
/// the gear on Next, and inbox processing and routines run full-screen.
struct PhoneShell: View {
    let composition: AppComposition
    @Bindable var router: AppRouter
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView(selection: $router.tab) {
            nextTab
                .tabItem { Label(Copy.next, systemImage: Symbols.next) }
                .tag(AppTab.next)

            inboxTab
                .tabItem { Label(Copy.inbox, systemImage: Symbols.inbox) }
                .badge(Rules.inboxQueue(model.snapshot).count)
                .tag(AppTab.inbox)

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
                    ActionDetailView(action: id)
                        .navigationTitle(model.snapshot.action(id)?.title ?? "")
                        .navigationBarTitleDisplayMode(.inline)
                }
        }
    }

    // MARK: - Inbox (I1)

    private var inboxTab: some View {
        NavigationStack {
            InboxTabContent(onProcess: { router.isProcessingInbox = true })
                .navigationTitle(Copy.inbox)
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
