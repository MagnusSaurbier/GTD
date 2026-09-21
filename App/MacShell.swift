#if os(macOS)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureOverview
import FeatureReview
import FeatureSettings

/// The Mac window (E3, STYLEGUIDE §4.1): `OverviewView`'s columns (three; two for the guided
/// flows), with the weekly-review
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
            // Renders nothing unless a review is in progress — and nothing while the review
            // section is the one on screen: "Resume" would lead where you already are
            // (walkthrough 2026-09-19).
            if router.overview.selection != .review {
                ReviewResumeBanner(onResume: { router.overview.select(.review) })
            }
            OverviewView(navigation: router.overview)
        }
        // Never narrower than the three columns at their minimum widths: below that, titles
        // hyphenate and badges collapse.
        .frame(
            minWidth: OverviewLayout.windowMinWidth, minHeight: OverviewLayout.windowMinHeight)
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
