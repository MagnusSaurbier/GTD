import Foundation

/// A minimal byte store `DeviceSettings` is persisted through. Injected so persistence stays
/// unit-testable without touching real `UserDefaults` or the file system (T26 brief).
public protocol SettingsStore: Sendable {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
}

/// In-memory `SettingsStore` — used by tests and SwiftUI previews. Thread-safe.
public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data]

    public init(_ initial: [String: Data] = [:]) {
        storage = initial
    }

    public func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func setData(_ data: Data?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let data {
            storage[key] = data
        } else {
            storage.removeValue(forKey: key)
        }
    }
}

/// `UserDefaults`-backed `SettingsStore` — the default for real devices. `UserDefaults` is part
/// of Foundation (not SwiftUI/UIKit), so this compiles and could even run on Linux; the app shell
/// (T40) is free to substitute an Application-Support-file-backed store instead (ARCHITECTURE §3:
/// device-local state lives in Application Support, not the vault).
public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func setData(_ data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

/// Loads and saves `DeviceSettings` through an injected `SettingsStore`. Never touches the vault
/// (ARCHITECTURE §3) and never guesses a value: a missing or corrupt record falls back to
/// `DeviceSettings.default`, never a partially-decoded guess.
public struct DeviceSettingsStore: Sendable {
    private let store: any SettingsStore
    private let key: String

    public init(store: any SettingsStore, key: String = "gtd.deviceSettings") {
        self.store = store
        self.key = key
    }

    public func load() -> DeviceSettings {
        guard let data = store.data(forKey: key),
              let settings = try? JSONDecoder().decode(DeviceSettings.self, from: data)
        else { return .default }
        return settings
    }

    public func save(_ settings: DeviceSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        store.setData(data, forKey: key)
    }
}
