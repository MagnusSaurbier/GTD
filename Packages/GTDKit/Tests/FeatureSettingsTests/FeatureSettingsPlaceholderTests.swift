import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import FeatureSettings

/// Placeholder so the target builds and `swift test` has something to run.
/// **T26 replaces this with the real suite.**
struct FeatureSettingsPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

    @Test func deviceSettingsRoundTrip() throws {
        let settings = DeviceSettings(lastKnowledgeFolder: "Studium/Thesis")
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(DeviceSettings.self, from: data) == settings)
    }
}
