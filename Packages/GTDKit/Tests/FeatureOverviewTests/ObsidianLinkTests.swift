import Testing
import Foundation
import GTDModel
@testable import FeatureOverview

/// "Open in Obsidian" (E3).
struct ObsidianLinkTests {
    private let id = NoteID(path: "Actions/Write DAAD motivation letter.md")

    @Test func linkUsesTheVaultRelativePathWhenTheRootIsUnknown() throws {
        let url = try #require(ObsidianLink.url(for: id))
        #expect(url.scheme == "obsidian")
        #expect(url.host == "open")
        #expect(url.absoluteString.contains("path="))
        #expect(url.absoluteString.contains("Actions"))
        // Spaces must be percent-encoded, not left raw.
        #expect(!url.absoluteString.contains(" "))
    }

    @Test func linkIsAbsoluteWhenTheVaultRootIsKnown() {
        #expect(ObsidianLink.path(for: id, vaultRoot: "/Users/me/Vault")
            == "/Users/me/Vault/Actions/Write DAAD motivation letter.md")
        #expect(ObsidianLink.path(for: id, vaultRoot: "/Users/me/Vault/")
            == "/Users/me/Vault/Actions/Write DAAD motivation letter.md")
        #expect(ObsidianLink.path(for: id, vaultRoot: "") == id.path)
        #expect(ObsidianLink.path(for: id, vaultRoot: nil) == id.path)
    }
}
