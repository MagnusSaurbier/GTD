import Foundation

/// Where `StartRoutineIntent` and `ProcessInboxIntent` leave a note of where the app should
/// navigate once it is foregrounded.
///
/// `openAppWhenRun = true` only launches/foregrounds the app — App Intents has no built-in way to
/// hand it a navigation payload, and this app has no separate App Intents extension (`project.yml`
/// declares one multiplatform target), so the intent runs in-process but may well finish before
/// any SwiftUI scene has subscribed to anything. Writing the route to durable, device-local
/// storage and having the app **consume** it once on launch and on every foreground (the same
/// place it already reads a `gtd://` URL from `onOpenURL`, per T40's brief) avoids that race.
/// Device-local state belongs outside the vault (ARCHITECTURE §3); this uses `UserDefaults` on
/// real devices, exactly like `FeatureSettings.SettingsStore`.
public protocol PendingRouteStore: Sendable {
    func string(forKey key: String) -> String?
    func setString(_ value: String?, forKey key: String)
}

/// In-memory `PendingRouteStore` — used by tests and previews. Thread-safe.
public final class InMemoryPendingRouteStore: PendingRouteStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String]

    public init(_ initial: [String: String] = [:]) {
        storage = initial
    }

    public func string(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func setString(_ value: String?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }
}

/// `UserDefaults`-backed `PendingRouteStore` — the default for real devices. `UserDefaults` is
/// part of Foundation, so this compiles (and could run) on Linux too.
public final class UserDefaultsPendingRouteStore: PendingRouteStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    public func setString(_ value: String?, forKey key: String) { defaults.set(value, forKey: key) }
}

/// Reads and writes the single pending deep link through an injected store.
public struct PendingRoute: Sendable {
    private let store: any PendingRouteStore
    private let key: String

    public init(store: any PendingRouteStore = UserDefaultsPendingRouteStore(), key: String = "gtd.pendingRoute") {
        self.store = store
        self.key = key
    }

    public func set(_ url: String) {
        store.setString(url, forKey: key)
    }

    /// Reads and clears in the same step — a route is delivered at most once, so a second
    /// foreground does not re-navigate somewhere the user already left.
    public func consume() -> String? {
        guard let value = store.string(forKey: key) else { return nil }
        store.setString(nil, forKey: key)
        return value
    }
}
