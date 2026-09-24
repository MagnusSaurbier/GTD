import Foundation

/// Where Next-view filters are remembered per device (E1: "filters persist per device").
///
/// `FeatureSettings.DeviceSettings` already reserves `nextContextFilter`/`nextTimeFilter` for
/// this, "persisted by the app shell" (T00's note there) — but `FeatureNext` may not import
/// `FeatureSettings` (ARCHITECTURE §2: features never import each other except where listed).
/// This protocol is the seam: `NextListModel` persists through it today via
/// `UserDefaultsNextFilterStore`, and T26/T40 can later hand it an adapter backed by
/// `DeviceSettings` without any call-site change.
public protocol NextFilterStore: Sendable {
    func contexts(for mode: NextViewMode) -> [String]
    func timeAvailable(for mode: NextViewMode) -> Int?
    func save(contexts: [String], timeAvailable: Int?, for mode: NextViewMode)
    /// E2 — whether the iPhone list shows every context instead of only the on-the-go ones.
    func showsAllContexts(for mode: NextViewMode) -> Bool
    func save(showsAllContexts: Bool, for mode: NextViewMode)
}

/// The default, device-local store. Minutes and contexts are namespaced per `NextViewMode`
/// so the Mac's full-list filter and the iPhone's on-the-go filter never overwrite each other
/// on a shared account (iCloud does not sync `UserDefaults.standard` across devices for this app).
public struct UserDefaultsNextFilterStore: NextFilterStore, @unchecked Sendable {
    // `UserDefaults` is documented thread-safe but predates `Sendable`; `@unchecked` is sound.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func contexts(for mode: NextViewMode) -> [String] {
        defaults.stringArray(forKey: contextsKey(mode)) ?? []
    }

    public func timeAvailable(for mode: NextViewMode) -> Int? {
        let key = timeKey(mode)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    public func save(contexts: [String], timeAvailable: Int?, for mode: NextViewMode) {
        defaults.set(contexts, forKey: contextsKey(mode))
        if let timeAvailable {
            defaults.set(timeAvailable, forKey: timeKey(mode))
        } else {
            defaults.removeObject(forKey: timeKey(mode))
        }
    }

    public func showsAllContexts(for mode: NextViewMode) -> Bool {
        defaults.bool(forKey: showsAllKey(mode))
    }

    public func save(showsAllContexts: Bool, for mode: NextViewMode) {
        defaults.set(showsAllContexts, forKey: showsAllKey(mode))
    }

    private func contextsKey(_ mode: NextViewMode) -> String { "FeatureNext.contexts.\(mode)" }
    private func showsAllKey(_ mode: NextViewMode) -> String { "FeatureNext.showsAllContexts.\(mode)" }
    private func timeKey(_ mode: NextViewMode) -> String { "FeatureNext.timeAvailable.\(mode)" }
}

/// Never touches disk — used by previews and tests so nothing leaks between runs.
/// `Box` is only ever touched from the `@MainActor` `NextListModel`, so the lack of internal
/// locking is sound despite the `@unchecked Sendable`.
public struct InMemoryNextFilterStore: NextFilterStore {
    private final class Box: @unchecked Sendable {
        var contexts: [NextViewMode: [String]] = [:]
        var time: [NextViewMode: Int?] = [:]
        var showsAll: [NextViewMode: Bool] = [:]
    }
    private let box = Box()

    public init() {}

    public func contexts(for mode: NextViewMode) -> [String] { box.contexts[mode] ?? [] }
    public func timeAvailable(for mode: NextViewMode) -> Int? { box.time[mode] ?? nil }

    public func save(contexts: [String], timeAvailable: Int?, for mode: NextViewMode) {
        box.contexts[mode] = contexts
        box.time[mode] = timeAvailable
    }

    public func showsAllContexts(for mode: NextViewMode) -> Bool { box.showsAll[mode] ?? false }
    public func save(showsAllContexts: Bool, for mode: NextViewMode) { box.showsAll[mode] = showsAllContexts }
}
