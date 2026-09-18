#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures

/// First run: explain what to pick, pick it, validate it. Returns a plain `URL` — this target
/// must not import `GTDVault`. **Owned by T26** — this is the compiling shell.
public struct OnboardingView: View {
    private let onVaultPicked: (URL) -> Void
    @State private var isPickerPresented = false

    public init(onVaultPicked: @escaping (URL) -> Void) {
        self.onVaultPicked = onVaultPicked
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Pick your vault").font(Typo.screenTitle)
            Text("Choose the folder that contains Actions/.")
                .font(Typo.body)
                .foregroundStyle(Color.textSecondary)
            Button("Choose folder…") { isPickerPresented = true }
        }
        .padding(Spacing.screenMargin)
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { onVaultPicked(url) }
        }
    }
}

/// Synced settings go through `updateConfig`; device-local ones through the binding.
/// **Owned by T26.**
public struct SettingsView: View {
    @Binding private var deviceSettings: DeviceSettings
    private let onChangeVault: () -> Void
    @Environment(AppModel.self) private var model

    public init(deviceSettings: Binding<DeviceSettings>, onChangeVault: @escaping () -> Void) {
        self._deviceSettings = deviceSettings
        self.onChangeVault = onChangeVault
    }

    public var body: some View {
        Form {
            Section(Copy.next) {
                Text("Cap: \(model.snapshot.config.nextCap)").font(Typo.body)
            }
            Section("Vault") {
                Button("Change vault…", action: onChangeVault)
            }
        }
    }
}

/// Files the app refuses to guess about (N3 §7). **Owned by T26.**
public struct VaultIssuesView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        List(Array(model.snapshot.issues.enumerated()), id: \.offset) { _, issue in
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(issue.path).font(Typo.body)
                Text(issue.message).font(Typo.meta).foregroundStyle(Color.textSecondary)
            }
        }
    }
}

#Preview {
    @Previewable @State var settings = DeviceSettings.default
    return SettingsView(deviceSettings: $settings, onChangeVault: {})
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
}
#endif
