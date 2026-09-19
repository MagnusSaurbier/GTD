#if os(macOS)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureOverview
import FeatureReview
import FeatureSettings

/// The Mac window (E3, STYLEGUIDE §4.1): `OverviewView`'s three columns, with the weekly-review
/// resume banner above them so an interrupted review is never lost behind a menu item (§10).
///
/// The window's selection lives in `AppRouter.overview`, the same `OverviewNavigation` the menu
/// bar's `OverviewCommands` drives — that is what makes `⌘1…7`, `⌘N` and `⌘I` land in this
/// window instead of a second copy of the state (T25's note to T40).
struct MacShell: View {
    let composition: AppComposition
    @Bindable var router: AppRouter

    var body: some View {
        VStack(spacing: 0) {
            // Renders nothing unless a review is in progress.
            ReviewResumeBanner(onResume: { router.overview.select(.review) })
            OverviewView(navigation: router.overview)
        }
        .frame(minWidth: 900, minHeight: 560)
        // A deep link or an App Intent asked for inbox processing; on the Mac the window owns
        // that sheet (`OverviewView`), so the request is handed over rather than presented twice.
        .onChange(of: router.isProcessingInbox) { _, requested in
            guard requested else { return }
            router.isProcessingInbox = false
            router.overview.isProcessingInbox = true
        }
    }
}

/// The `Settings` scene's content (`⌘,`). The same screen the iPhone shows in a sheet.
struct MacSettingsScene: View {
    let composition: AppComposition

    var body: some View {
        SettingsView(
            deviceSettings: Binding(
                get: { composition.deviceSettings },
                set: { composition.deviceSettings = $0 }),
            onChangeVault: { Task { await composition.changeVault() } })
            .frame(width: 520, height: 560)
    }
}
#endif
