import SwiftUI
import GTDAppCore
import GTDModel
import FeatureOverview

/// The app shell. **Owned by T40.**
///
/// It composes and nothing else: `AppComposition` builds the backend (vault or fixtures),
/// `AppRouter` holds where the app is looking, `NotificationService` keeps the local
/// notifications in step, and `RootView` renders the platform shell (N5). Everything with GTD
/// meaning lives in `GTDModel`; everything that touches files lives in `GTDVault`.
@main
struct GTDApp: App {
    @State private var composition: AppComposition
    @State private var router: AppRouter
    @State private var notifications: NotificationService

    init() {
        let composition = AppComposition()
        let notifications = NotificationService()
        _composition = State(initialValue: composition)
        _router = State(initialValue: AppRouter())
        _notifications = State(initialValue: notifications)
        BackgroundRefresh.register(composition: composition, notifications: notifications)
    }

    var body: some Scene {
        // One `#if` around whole scenes, not several around modifier-chain fragments: a postfix
        // `#if` chain followed by another `#if` that opens a *statement* is the kind of thing a
        // blind-written file gets wrong, and nothing here needs it (T41).
        #if os(macOS)
        WindowGroup {
            RootView(composition: composition, router: router, notifications: notifications)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            // STYLEGUIDE §4.5 — the window's keyboard map, mirrored in the menu bar.
            OverviewCommands(navigation: router.overview, model: composition.model)
        }

        Settings {
            MacSettingsScene(composition: composition)
                .environment(composition.model)
        }
        // Follows `MacSettingsScene`'s min/max frame, so the scrolling form can be resized.
        .windowResizability(.contentSize)
        #else
        WindowGroup {
            RootView(composition: composition, router: router, notifications: notifications)
        }
        // D2 — while the app is away, re-read the vault and re-plan the notifications.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
        #endif
    }
}
