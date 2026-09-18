import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDVault

/// Placeholder so the target builds and `swift test` has something to run.
/// **T15 replaces this with the real suite.**
struct GTDVaultPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

    @Test func storeIsNotImplementedYet() async {
        let store = FileVaultStore(root: URL(fileURLWithPath: NSTemporaryDirectory()))
        await #expect(throws: VaultError.self) { _ = try await store.read(path: "Actions/A.md") }
    }
}
