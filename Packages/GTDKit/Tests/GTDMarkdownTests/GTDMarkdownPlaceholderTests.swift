import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDMarkdown

/// Placeholder so the target builds and `swift test` has something to run.
/// **T10 replaces this with the real suite.**
struct GTDMarkdownPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

    @Test func codecIsNotImplementedYet() {
        #expect(throws: NoteCodecError.self) {
            _ = try NoteCodec.decodeAction(id: NoteID(path: "Actions/A.md"), text: "")
        }
    }
}
