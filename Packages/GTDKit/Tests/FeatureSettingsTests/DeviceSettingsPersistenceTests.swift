import Testing
import Foundation
import GTDModel
import GTDAppCore
@testable import FeatureSettings

/// Round-trips `DeviceSettings` through the injected `SettingsStore` (T26 brief: "inject a
/// key-value store protocol; test against an in-memory one").
struct DeviceSettingsPersistenceTests {
    @Test func roundTripsThroughTheStore() {
        let store = InMemorySettingsStore()
        let settingsStore = DeviceSettingsStore(store: store)

        var settings = DeviceSettings.default
        settings.lastKnowledgeFolder = "Studium/Thesis"
        settings.notificationKinds = ["dueApproaching": true, "summary": false]
        settings.morningTime = DayTime(hour: 6, minute: 45)
        settings.nextContextFilter = ["phone", "errands"]
        settings.nextTimeFilter = 30
        settings.vaultDisplayName = "GTD"

        settingsStore.save(settings)
        #expect(settingsStore.load() == settings)
    }

    @Test func missingRecordFallsBackToDefault() {
        let store = InMemorySettingsStore()
        let settingsStore = DeviceSettingsStore(store: store)
        #expect(settingsStore.load() == .default)
    }

    @Test func corruptRecordFallsBackToDefaultRatherThanGuessing() {
        let store = InMemorySettingsStore(["gtd.deviceSettings": Data("not json".utf8)])
        let settingsStore = DeviceSettingsStore(store: store)
        #expect(settingsStore.load() == .default)
    }

    @Test func savingReplacesThePreviousRecord() {
        let store = InMemorySettingsStore()
        let settingsStore = DeviceSettingsStore(store: store)
        settingsStore.save(DeviceSettings(lastKnowledgeFolder: "A"))
        settingsStore.save(DeviceSettings(lastKnowledgeFolder: "B"))
        #expect(settingsStore.load().lastKnowledgeFolder == "B")
    }

    @Test func twoStoresUnderDifferentKeysDoNotCollide() {
        let store = InMemorySettingsStore()
        let a = DeviceSettingsStore(store: store, key: "a")
        let b = DeviceSettingsStore(store: store, key: "b")
        a.save(DeviceSettings(lastKnowledgeFolder: "A"))
        #expect(b.load() == .default)
        #expect(a.load().lastKnowledgeFolder == "A")
    }

    @Test func deviceSettingsCodableRoundTrip() throws {
        let settings = DeviceSettings(lastKnowledgeFolder: "Studium/Thesis")
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(DeviceSettings.self, from: data) == settings)
    }

    /// R-10 (N7): key rebinds are device-local, so they persist through `DeviceSettings` exactly
    /// like every other field — no separate store.
    @Test func keyBindingsDefaultAndPersistThroughTheStore() throws {
        #expect(DeviceSettings.default.keyBindings == .defaults)

        var settings = DeviceSettings.default
        try settings.keyBindings.rebind(.stepAction, to: .letter("Q"))

        let store = InMemorySettingsStore()
        let settingsStore = DeviceSettingsStore(store: store)
        settingsStore.save(settings)
        #expect(settingsStore.load().keyBindings.key(for: .stepAction) == .letter("Q"))
    }

    /// The Keyboard pane's "Reset to defaults" (STYLEGUIDE §4.5) restores every screen at once,
    /// and the reset itself persists exactly like a rebind does.
    @Test func keyBindingsResetPersistsThroughTheStore() throws {
        var settings = DeviceSettings.default
        try settings.keyBindings.rebind(.stepAction, to: .letter("Q"))
        try settings.keyBindings.rebind(.deckKeep, to: .letter("Z"))
        #expect(!settings.keyBindings.rebound.isEmpty)

        settings.keyBindings.reset()
        #expect(settings.keyBindings == .defaults)

        let store = InMemorySettingsStore()
        let settingsStore = DeviceSettingsStore(store: store)
        settingsStore.save(settings)
        #expect(settingsStore.load().keyBindings == .defaults)
    }
}
