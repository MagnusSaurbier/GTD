import SwiftUI
import GTDAppCore
import GTDFixtures
import GTDModel
import DesignSystem
import FeatureOverview

/// The app shell. **Owned by T40** — T00 wired up the smallest thing that runs: the fixtures
/// snapshot behind `InMemoryBackend`, so the whole UI stack can be opened before `GTDVault`
/// and `GTDServices` exist.
@main
struct GTDApp: App {
    @State private var model: AppModel

    init() {
        // T40: replace with `VaultBackend` + the security-scoped bookmark, keeping
        // `InMemoryBackend` behind the `-useFixtures` launch argument for UI tests.
        let snapshot = Fixtures.sampleSnapshot
        _model = State(initialValue: AppModel(
            backend: InMemoryBackend(snapshot: snapshot),
            snapshot: snapshot))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 640)
        #endif
    }
}

/// Placeholder root view. T40 replaces it with the real platform split (N5):
/// `OverviewView` on Mac, a three-tab `TabView` on iPhone.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        OverviewView()
    }
}

#Preview {
    RootView()
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
}
