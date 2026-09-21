import Foundation

#if os(iOS)
import BackgroundTasks
#endif

/// Background app refresh (D2): while the app is away, another device may have filed, deferred
/// or completed things. A refresh re-reads the vault and re-plans the notifications, so a
/// reminder that is no longer true is withdrawn even if the app is never opened.
///
/// It also doubles as the shell's service registry: the `backgroundTask` scene modifier takes a
/// `@Sendable` closure, which cannot capture the main-actor-isolated `AppComposition`. Holding
/// the two objects here — on the main actor — keeps that closure capture-free.
@MainActor
enum BackgroundRefresh {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in `project.yml`.
    static let identifier = "com.magnussaurbier.gtd.refresh"

    /// How long after backgrounding the system may run the refresh. The system decides in the
    /// end; this is only the earliest it is allowed to.
    static let interval: TimeInterval = 60 * 60

    static var composition: AppComposition?
    static var notifications: NotificationService?

    static func register(composition: AppComposition, notifications: NotificationService) {
        self.composition = composition
        self.notifications = notifications
    }

    /// Asks for the next refresh. Called every time the app goes to the background.
    static func schedule() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        // A refused submit (background refresh switched off, simulator) is not an error the
        // person needs to see — the app works, it just will not refresh unattended.
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    /// The refresh itself. Re-reading the vault publishes a new snapshot, and the plan is
    /// rebuilt from it — `NotificationPlanner` drops anything whose fire date has passed.
    static func run() async {
        await composition?.refreshFromDisk()
        guard let composition, let notifications else { return }
        await notifications.replanNow(
            snapshot: composition.model.snapshot, settings: composition.deviceSettings)
        schedule()
    }
}
