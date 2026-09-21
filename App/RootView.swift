import SwiftUI
import GTDModel
import GTDAppCore
import GTDIntents
import DesignSystem
import FeatureOverview
import FeatureProjects
import FeatureRoutines
import FeatureSettings

/// The one view the window shows: onboarding until there is a vault, the platform shell after
/// that (N5 — iPhone tabs, Mac split view), plus everything that belongs to the app rather than
/// to a screen: the "What's next?" prompt (P5), error alerts, quick capture (I7), a deep-linked
/// routine run, and the lifecycle wiring (deep links, foreground refresh, notification plans).
struct RootView: View {
    let composition: AppComposition
    @Bindable var router: AppRouter
    let notifications: NotificationService

    var body: some View {
        phaseContent
            .modifier(GlobalFlows(composition: composition, router: router))
            .modifier(Lifecycle(
                composition: composition, router: router, notifications: notifications))
            // Outermost on purpose: a value set here is visible to every modifier *inside* it,
            // which is where the flows above read `AppModel` from — and to their sheets, which
            // inherit the presenting view's environment.
            .environment(composition.model)
            .environment(\.vaultRootPath, composition.vaultRootPath)
            .environment(\.keyBindings, composition.deviceSettings.keyBindings)
    }

    @ViewBuilder private var phaseContent: some View {
        switch composition.phase {
        case .loading:
            ProgressView(AppCopy.openingVault)
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.surface)
        case .onboarding:
            OnboardingView(
                onVaultPicked: { url in Task { await composition.pickVault(url) } },
                onFinished: {
                    composition.finishOnboarding()
                    Task { await notifications.requestAuthorizationIfNeeded() }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.surfaceGrouped)
        case .ready:
            shell
        }
    }

    @ViewBuilder private var shell: some View {
        #if os(macOS)
        MacShell(composition: composition, router: router)
        #else
        PhoneShell(composition: composition, router: router)
        #endif
    }
}

// MARK: - Global flows

/// Presentations that belong to the app, not to a screen. One place, so nothing is presented
/// twice and the rules of STYLEGUIDE §4.3 (sheets for sub-flows, alerts only for real failures)
/// hold everywhere.
private struct GlobalFlows: ViewModifier {
    let composition: AppComposition
    @Bindable var router: AppRouter

    /// Read from the composition rather than the environment: this modifier sits *outside* the
    /// `.environment(...)` it would have to read from.
    private var model: AppModel { composition.model }

    func body(content: Content) -> some View {
        content
            // P5 — "What's next?" after the last open action of a project was completed.
            .sheet(item: whatsNext) { target in
                WhatsNextSheet(project: target.note)
            }
            // I7 — capture, then process that one card.
            .sheet(isPresented: $router.isCapturePresented) {
                QuickCaptureSheet { text in
                    router.isCapturePresented = false
                    // One presentation at a time: let the capture sheet finish dismissing before
                    // processing takes the screen, and give the vault scan a moment to pick the
                    // new file up so the session opens *on that card* (I7, LIFO).
                    Task {
                        guard await composition.capture(text: text) != nil else { return }
                        try? await Task.sleep(for: .milliseconds(350))
                        router.isProcessingInbox = true
                    }
                }
            }
            // R3 — a routine opened from a notification or an App Intent.
            .flowCover(item: $router.routineRun) { target in
                RoutineRunnerView(routine: target.note, onFinished: { router.routineRun = nil })
            }
            .alert(
                AppCopy.somethingWentWrong,
                isPresented: errorPresented,
                presenting: currentError
            ) { _ in
                Button(AppCopy.ok) { dismissError() }
            } message: { error in
                Text(error.message)
            }
    }

    // MARK: Bindings

    private var whatsNext: Binding<NoteTarget?> {
        Binding(
            get: {
                if case let .whatsNext(project) = model.prompt { return NoteTarget(project) }
                return nil
            },
            set: { if $0 == nil { model.prompt = nil } })
    }

    /// Shell failures and `AppModel.lastError` (a refused undo, a failed rollback — T16) share
    /// one alert: a failure the person cannot see is a lying UI (§1).
    private var currentError: AppError? {
        composition.error ?? model.writeFailure.map(AppError.init) ?? model.lastError.map(AppError.init)
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { currentError != nil }, set: { if !$0 { dismissError() } })
    }

    private func dismissError() {
        composition.error = nil
        model.clearError()
    }
}

// MARK: - Lifecycle

/// Launch, foreground, deep links, notification plans (D2, R3, N3).
private struct Lifecycle: ViewModifier {
    let composition: AppComposition
    let router: AppRouter
    let notifications: NotificationService
    @Environment(\.scenePhase) private var scenePhase

    private var model: AppModel { composition.model }

    func body(content: Content) -> some View {
        content
            .task {
                notifications.installDelegate { link in
                    router.apply(url: link, snapshot: composition.model.snapshot)
                }
                await composition.bootstrap()
                if composition.phase == .ready {
                    await notifications.requestAuthorizationIfNeeded()
                    await notifications.replanNow(
                        snapshot: composition.model.snapshot,
                        settings: composition.deviceSettings)
                }
                router.consumePendingRoute(
                    composition.pendingRoute, snapshot: composition.model.snapshot)
            }
            // A `gtd://` link from a notification tap, a Shortcut or another app.
            .onOpenURL { url in
                router.apply(url: url.absoluteString, snapshot: model.snapshot)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    Task {
                        await composition.refreshFromDisk()
                        await composition.runDailyHousekeeping()
                        router.consumePendingRoute(
                            composition.pendingRoute, snapshot: composition.model.snapshot)
                        await notifications.replanNow(
                            snapshot: composition.model.snapshot,
                            settings: composition.deviceSettings)
                    }
                case .background:
                    BackgroundRefresh.schedule()
                    Task { await composition.flushWritesBeforeSuspension() }
                default:
                    break
                }
            }
            // Every snapshot change re-plans (debounced): a device only knows what has synced
            // into its own snapshot, so planning once at launch is not enough (T13).
            .onChange(of: model.snapshot) { _, snapshot in
                // The only consumer of the renames: `consumeRenames()` hands over everything
                // published since the last change, so the router follows a renamed note before
                // it prunes the ones that are genuinely gone (A1 — a rename is a file move).
                router.apply(snapshot: snapshot, renames: model.consumeRenames())
                notifications.scheduleReplan(
                    snapshot: snapshot, settings: composition.deviceSettings)
            }
            // The morning time and the per-kind toggles live in the device settings.
            .onChange(of: composition.deviceSettings) { _, settings in
                Task {
                    await notifications.replanNow(
                        snapshot: composition.model.snapshot, settings: settings)
                }
            }
            // ⌘N in the menu bar asks the shell to capture — capture writes through `GTDVault`,
            // which feature targets must not import (T25).
            .onChange(of: router.overview.isCaptureRequested) { _, requested in
                guard requested else { return }
                router.overview.isCaptureRequested = false
                router.isCapturePresented = true
            }
    }
}

// MARK: - Quick capture (I7)

/// One field, one button. Capture is deliberately the dumbest screen in the app: it writes the
/// raw text and gets out of the way — processing happens straight after (I7, LIFO).
struct QuickCaptureSheet: View {
    let onCapture: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(Copy.quickCapture)
                .font(Typo.sectionHeader)
                .foregroundStyle(Color.ink)
            TextField(AppCopy.capturePlaceholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.cardText)
                .lineLimit(3...)
                .focused($focused)
            HStack {
                Button(AppCopy.cancel) { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button(AppCopy.capture) { onCapture(text) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gtdAccent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.screenMargin)
        .frame(minWidth: 320)
        #if os(iOS)
        // P17 — a short sheet with the field at the top, not a full-height one with the field
        // floating in the middle. Cancel and Capture stay above the keyboard, so the sheet
        // needs no keyboard `Done` of its own.
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear { focused = true }
    }
}

// MARK: - Helpers

extension View {
    /// A flow that takes the whole screen on iPhone and a sheet on Mac (STYLEGUIDE §4.2/§4.3).
    @ViewBuilder
    func flowCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(item: item, content: content)
        #else
        self.sheet(item: item, content: content)
        #endif
    }

    /// `isPresented` twin of the above.
    @ViewBuilder
    func flowCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
}

// MARK: - Previews

/// Previews always run on fixtures — never on the bookmark, and therefore never on the real
/// vault (CLAUDE.md rule 1).
@MainActor
private func previewRoot() -> some View {
    RootView(
        composition: AppComposition(useFixtures: true),
        router: AppRouter(),
        notifications: NotificationService())
}

#Preview("Shell") {
    previewRoot()
}

#Preview("Shell · dark") {
    previewRoot()
        .preferredColorScheme(.dark)
}

#Preview("Quick capture") {
    QuickCaptureSheet { _ in }
}
