#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// First run: explain what to pick, pick it, show a validation preview, ask for notifications,
/// then hint at the capture Shortcut. Returns a plain `URL` — this target must not import
/// `GTDVault`; the shell (T15/T40) turns it into a `VaultBookmark`. **Owned by T26.**
///
/// The validation preview and the rest of onboarding read `@Environment(AppModel.self)` (the
/// same pattern `SettingsView` uses) rather than a second closure: once the shell hands the
/// picked `URL` to `VaultBookmark`/`GTDServices` and mounts a real `AppModel`, this view's next
/// steps see the loaded snapshot for free.
public struct OnboardingView: View {
    private let onVaultPicked: (URL) -> Void
    @Environment(AppModel.self) private var model
    @State private var isPickerPresented = false
    @State private var step: Step = .welcome

    private enum Step { case welcome, validate, notifications, shortcut }

    public init(onVaultPicked: @escaping (URL) -> Void) {
        self.onVaultPicked = onVaultPicked
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            switch step {
            case .welcome: welcomeStep
            case .validate: validateStep
            case .notifications: notificationsStep
            case .shortcut: shortcutStep
            }
        }
        .padding(Spacing.screenMargin)
        .frame(maxWidth: Spacing.cardMaxWidth, alignment: .leading)
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                onVaultPicked(url)
                step = .validate
            }
        }
    }

    // MARK: Step 1 — explain and pick

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Pick your vault").font(Typo.screenTitle).foregroundStyle(Color.ink)
            Text("Choose the Obsidian folder that contains Actions/. The app reads and writes markdown files there — nothing else is touched.")
                .font(Typo.body)
                .foregroundStyle(Color.textSecondary)
            Button("Choose folder…") { isPickerPresented = true }
                .buttonStyle(.borderedProminent)
                .tint(Color.gtdAccent)
        }
    }

    // MARK: Step 2 — validation preview

    private var validateStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Looks like this").font(Typo.screenTitle).foregroundStyle(Color.ink)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(model.snapshot.actions.count) actions found")
                Text("\(model.snapshot.projects.count) projects found")
                Text(model.snapshot.inbox.isEmpty
                    ? "Inbox is empty"
                    : "\(model.snapshot.inbox.count) item\(model.snapshot.inbox.count == 1 ? "" : "s") in Inbox")
            }
            .font(Typo.body)
            .foregroundStyle(Color.textSecondary)
            if !model.snapshot.issues.isEmpty {
                Text("\(model.snapshot.issues.count) file\(model.snapshot.issues.count == 1 ? "" : "s") need attention — see Vault issues in Settings.")
                    .font(Typo.meta)
                    .foregroundStyle(Color.signalAttention)
            }
            Button("Continue") { step = .notifications }
                .buttonStyle(.borderedProminent)
                .tint(Color.gtdAccent)
        }
    }

    // MARK: Step 3 — notification permission

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Stay on top of things").font(Typo.screenTitle).foregroundStyle(Color.ink)
            Text("Turn on notifications for due dates, follow-ups and routines. You can change this anytime in Settings.")
                .font(Typo.body)
                .foregroundStyle(Color.textSecondary)
            Button("Turn on notifications") { requestNotifications() }
                .buttonStyle(.borderedProminent)
                .tint(Color.gtdAccent)
            Button("Not now") { step = .shortcut }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func requestNotifications() {
        #if canImport(UserNotifications)
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            step = .shortcut
        }
        #else
        step = .shortcut
        #endif
    }

    // MARK: Step 4 — capture Shortcut hint

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("One more thing").font(Typo.screenTitle).foregroundStyle(Color.ink)
            Text("Install the capture Shortcut to add to your Inbox from anywhere — the share sheet, Siri, or the lock screen. See Shortcuts/README.md for the recipe.")
                .font(Typo.body)
                .foregroundStyle(Color.textSecondary)
            Text("You're set. Open Next or process your Inbox to get going.")
                .font(Typo.meta)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

/// Synced settings go through `updateConfig`/`setRoutineTime`; device-local ones through the
/// binding. **Owned by T26.**
public struct SettingsView: View {
    @Binding private var deviceSettings: DeviceSettings
    private let onChangeVault: () -> Void
    @Environment(AppModel.self) private var model

    @State private var newContextName = ""
    @State private var renamingContext: String?
    @State private var renameText = ""
    @State private var pendingRemoval: String?

    public init(deviceSettings: Binding<DeviceSettings>, onChangeVault: @escaping () -> Void) {
        self._deviceSettings = deviceSettings
        self.onChangeVault = onChangeVault
    }

    public var body: some View {
        let session = SettingsSession(model: model)
        Form {
            contextsSection(session)
            onTheGoSection(session)
            nextCapSection(session)
            routinesSection(session)
            notificationsSection
            vaultSection
            aboutSection
        }
        .confirmationDialog(
            "Remove context?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { context in
            Button("Remove", role: .destructive) {
                Task { try? await session.removeContext(context) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { context in
            let count = session.affectedActionCount(for: context)
            Text("\(count) action\(count == 1 ? "" : "s") still use \"\(context)\". They keep the text; it just won't show as a chip.")
        }
        .alert(
            "Rename context",
            isPresented: Binding(
                get: { renamingContext != nil },
                set: { if !$0 { renamingContext = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let old = renamingContext {
                    Task { try? await session.renameContext(old, to: renameText) }
                }
                renamingContext = nil
            }
            Button("Cancel", role: .cancel) { renamingContext = nil }
        }
    }

    // MARK: Contexts (A4)

    @ViewBuilder
    private func contextsSection(_ session: SettingsSession) -> some View {
        Section {
            ForEach(Array(session.config.contexts.enumerated()), id: \.offset) { index, context in
                contextRow(session, index: index, context: context, count: session.config.contexts.count)
            }
            HStack {
                TextField("Add a context", text: $newContextName)
                Button("Add") {
                    let name = newContextName
                    newContextName = ""
                    Task { try? await session.addContext(name) }
                }
                .disabled(newContextName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Contexts")
        } footer: {
            Text("Removing a context in use asks first; it never rewrites existing actions.")
        }
    }

    private func contextRow(_ session: SettingsSession, index: Int, context: String, count: Int) -> some View {
        HStack(spacing: Spacing.s) {
            Text(context).font(Typo.body).foregroundStyle(Color.ink)
            Spacer()
            Button("Up") { moveContext(session, at: index, up: true) }
                .disabled(index == 0)
            Button("Down") { moveContext(session, at: index, up: false) }
                .disabled(index == count - 1)
            Button("Rename") {
                renameText = context
                renamingContext = context
            }
            Button {
                let affected = session.affectedActionCount(for: context)
                if affected > 0 {
                    pendingRemoval = context
                } else {
                    Task { try? await session.removeContext(context) }
                }
            } label: {
                Image(systemName: Symbols.trash)
            }
            .accessibilityLabel("Remove \(context)")
        }
        .buttonStyle(.plain)
        .font(Typo.meta)
        .foregroundStyle(Color.gtdAccent)
    }

    private func moveContext(_ session: SettingsSession, at index: Int, up: Bool) {
        let destination = up ? index - 1 : index + 2
        Task { try? await session.reorderContexts(from: IndexSet(integer: index), to: destination) }
    }

    // MARK: On-the-go subset (A4, N5)

    @ViewBuilder
    private func onTheGoSection(_ session: SettingsSession) -> some View {
        Section {
            ContextChipGroup(
                contexts: session.config.contexts,
                selection: Binding(
                    get: { session.config.onTheGoContexts },
                    set: { newValue in
                        let changed = Set(newValue).symmetricDifference(session.config.onTheGoContexts)
                        for context in changed {
                            Task { try? await session.toggleOnTheGo(context) }
                        }
                    }))
        } header: {
            Text("On the go")
        } footer: {
            Text("These contexts make up the iPhone's on-the-go Next list.")
        }
    }

    // MARK: Next cap (A3)

    @ViewBuilder
    private func nextCapSection(_ session: SettingsSession) -> some View {
        Section {
            Stepper(
                "Next cap: \(session.config.nextCap)",
                value: Binding(
                    get: { session.config.nextCap },
                    set: { newValue in Task { try? await session.setNextCap(newValue) } }),
                in: NextCapPolicy.minimum...999)
            if NextCapPolicy.showsRaisedWarning(session.config.nextCap) {
                Text("A higher cap makes Next less focused.")
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
            }
        } header: {
            Text(Copy.next)
        }
    }

    // MARK: Routine times (R3)

    @ViewBuilder
    private func routinesSection(_ session: SettingsSession) -> some View {
        Section {
            ForEach(session.routines) { routine in
                RoutineTimeRow(routine: routine, session: session)
            }
        } header: {
            Text(Copy.routine)
        }
    }

    // MARK: Device-local (D2, notifications + morning time)

    private var notificationsSection: some View {
        Section {
            ForEach(NotificationKindOption.allCases) { option in
                Toggle(
                    option.label,
                    isOn: Binding(
                        get: { deviceSettings.notificationKinds[option.rawValue] ?? true },
                        set: { deviceSettings.notificationKinds[option.rawValue] = $0 }))
            }
            DatePicker(
                "Morning time",
                selection: Binding(
                    get: { deviceSettings.morningTime.asDate },
                    set: { deviceSettings.morningTime = DayTime($0) }),
                displayedComponents: .hourAndMinute)
        } header: {
            Text("Notifications")
        }
    }

    private var vaultSection: some View {
        Section {
            if let name = deviceSettings.vaultDisplayName {
                LabeledContent("Vault", value: name)
            }
            Button("Change vault…", action: onChangeVault)
        } header: {
            Text("Vault")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Self.appVersion)
            Text("A personal GTD app over a plain-markdown Obsidian vault.")
                .font(Typo.meta)
                .foregroundStyle(Color.textSecondary)
        } header: {
            Text("About")
        }
    }

    private static var appVersion: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// One routine's schedule (R1, R3): an on/off toggle plus a time picker while on. Turning it on
/// commits an explicit, user-chosen starting time immediately — the same "tap to confirm" rule
/// `DateValueChip` uses elsewhere, not a silently-written default.
private struct RoutineTimeRow: View {
    let routine: Routine
    let session: SettingsSession

    @State private var isScheduled: Bool
    @State private var time: Date

    init(routine: Routine, session: SettingsSession) {
        self.routine = routine
        self.session = session
        _isScheduled = State(initialValue: routine.time != nil)
        _time = State(initialValue: (routine.time ?? DayTime(hour: 7, minute: 0)).asDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Toggle(routine.title, isOn: $isScheduled)
                .onChange(of: isScheduled) { _, on in
                    Task { try? await session.setRoutineTime(routine.id, to: on ? DayTime(time) : nil) }
                }
            if isScheduled {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .onChange(of: time) { _, newValue in
                        Task { try? await session.setRoutineTime(routine.id, to: DayTime(newValue)) }
                    }
            }
        }
    }
}

/// Files the app refuses to guess about (N3 §7). **Owned by T26.**
public struct VaultIssuesView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        List {
            if model.snapshot.issues.isEmpty {
                ContentUnavailableView("No issues", systemImage: Symbols.done)
            } else {
                ForEach(Array(model.snapshot.issues.enumerated()), id: \.offset) { _, issue in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(issue.path).font(Typo.body).foregroundStyle(Color.ink)
                        Text(issue.message).font(Typo.meta).foregroundStyle(Color.textSecondary)
                        HStack(spacing: Spacing.l) {
                            Button("Reveal") { reveal(issue.path) }
                            Button("Open in Obsidian") { openInObsidian(issue.path) }
                        }
                        .buttonStyle(.plain)
                        .font(Typo.meta)
                        .foregroundStyle(Color.gtdAccent)
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }
        }
        .navigationTitle("Vault issues")
    }

    /// Best effort: this target only has the vault-relative path (no root URL —
    /// `FeatureSettings` intentionally does not import `GTDVault`, ARCHITECTURE §2). A future
    /// contract addition could hand this view the resolved vault root if that turns out not to
    /// be enough for these two actions. Unverified — see the module README.
    private func reveal(_ path: String) {
        #if canImport(AppKit)
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        #endif
        // No Files-app equivalent on iOS without a resolvable URL.
    }

    private func openInObsidian(_ path: String) {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "obsidian://open?path=\(encoded)")
        else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

#Preview("Onboarding") {
    OnboardingView(onVaultPicked: { _ in })
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
}

#Preview("Onboarding — dark") {
    OnboardingView(onVaultPicked: { _ in })
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
        .preferredColorScheme(.dark)
}

#Preview("Onboarding — AX1") {
    OnboardingView(onVaultPicked: { _ in })
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
        .dynamicTypeSize(.accessibility1)
}

#Preview("Settings") {
    @Previewable @State var settings = DeviceSettings.default
    return NavigationStack {
        SettingsView(deviceSettings: $settings, onChangeVault: {})
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}

#Preview("Settings — dark") {
    @Previewable @State var settings = DeviceSettings.default
    return NavigationStack {
        SettingsView(deviceSettings: $settings, onChangeVault: {})
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
    .preferredColorScheme(.dark)
}

#Preview("Settings — AX1") {
    @Previewable @State var settings = DeviceSettings.default
    return NavigationStack {
        SettingsView(deviceSettings: $settings, onChangeVault: {})
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
    .dynamicTypeSize(.accessibility1)
}

#Preview("Vault issues") {
    NavigationStack {
        VaultIssuesView()
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}

#Preview("Vault issues — dark") {
    NavigationStack {
        VaultIssuesView()
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
    .preferredColorScheme(.dark)
}

#Preview("Vault issues — empty") {
    NavigationStack {
        VaultIssuesView()
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: .empty),
        snapshot: .empty,
        today: { Fixtures.today }))
}
#endif
