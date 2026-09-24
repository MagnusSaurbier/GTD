import Testing
import Foundation
import GTDModel
@testable import GTDAppCore

/// "Open in Obsidian": `path=` must be absolute, `file=` goes with `vault=`.
struct ObsidianLinkTests {
    private let root = "/Users/me/Library/Mobile Documents/iCloud~md~obsidian/Documents/Magnus_GTD"

    private func link(_ path: String, root: String?, _ form: ObsidianLink.Form) -> String? {
        ObsidianLink.url(forVaultPath: path, vaultRoot: root, form: form)?.absoluteString
    }

    // MARK: vault + file

    @Test func vaultAndFileNamesTheVaultFolderAndTheRelativePath() {
        #expect(link("Projects/GTD/GTD App Requirements.md", root: root, .vaultAndFile)
            == "obsidian://open?vault=Magnus_GTD&file=Projects%2FGTD%2FGTD%20App%20Requirements.md")
    }

    @Test func aVaultNameWithSpacesIsEncodedAndATrailingSlashIgnored() {
        #expect(link("Note.md", root: "/Users/me/My Vault/", .vaultAndFile)
            == "obsidian://open?vault=My%20Vault&file=Note.md")
    }

    @Test func charactersThatWouldEndAQueryValueAreEscaped() {
        #expect(link("Actions/R&D #3 = 1+1?.md", root: "/v/Q&A", .vaultAndFile)
            == "obsidian://open?vault=Q%26A&file=Actions%2FR%26D%20%233%20%3D%201%2B1%3F.md")
    }

    @Test func umlautsAreUTF8PercentEncoded() {
        #expect(link("Projects/Wohnen/Küche/Maße.md", root: root, .vaultAndFile)
            == "obsidian://open?vault=Magnus_GTD&file=Projects%2FWohnen%2FK%C3%BCche%2FMa%C3%9Fe.md")
    }

    // MARK: absolute path

    @Test func absolutePathJoinsRootAndRelativePath() {
        #expect(link("Projects/GTD/GTD App Requirements.md", root: "/Users/me/Vault", .absolutePath)
            == "obsidian://open?path=%2FUsers%2Fme%2FVault%2FProjects%2FGTD%2FGTD%20App%20Requirements.md")
        #expect(link("/Note.md", root: "/Users/me/Vault/", .absolutePath)
            == "obsidian://open?path=%2FUsers%2Fme%2FVault%2FNote.md")
    }

    @Test func absolutePathIsNeverVaultRelative() throws {
        let url = try #require(ObsidianLink.url(forVaultPath: "Actions/A & B.md", vaultRoot: root, form: .absolutePath))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.count == 1)
        #expect(items.first?.name == "path")
        #expect(items.first?.value == "\(root)/Actions/A & B.md")
    }

    // MARK: file path (Copy path)

    @Test func filePathJoinsRootAndRelativePathUnescaped() {
        #expect(ObsidianLink.filePath(forVaultPath: "Actions/A & B #3.md", vaultRoot: root)
            == "\(root)/Actions/A & B #3.md")
        #expect(ObsidianLink.filePath(forVaultPath: "/Note.md", vaultRoot: "/Users/me/Vault/")
            == "/Users/me/Vault/Note.md")
        let id = NoteID(path: "Actions/Write DAAD motivation letter.md")
        #expect(ObsidianLink.filePath(for: id, vaultRoot: "/Users/me/Vault")
            == "/Users/me/Vault/Actions/Write DAAD motivation letter.md")
    }

    @Test func thereIsNoFilePathWithoutAVaultRoot() {
        #expect(ObsidianLink.filePath(forVaultPath: "Actions/A.md", vaultRoot: nil) == nil)
        #expect(ObsidianLink.filePath(forVaultPath: "Actions/A.md", vaultRoot: "") == nil)
        #expect(ObsidianLink.filePath(forVaultPath: "Actions/A.md", vaultRoot: "/") == nil)
        #expect(ObsidianLink.filePath(forVaultPath: "", vaultRoot: root) == nil)
    }

    // MARK: no link

    @Test func thereIsNoLinkWithoutAVaultRoot() {
        for form in [ObsidianLink.Form.absolutePath, .vaultAndFile] {
            #expect(link("Actions/A.md", root: nil, form) == nil)
            #expect(link("Actions/A.md", root: "", form) == nil)
            #expect(link("Actions/A.md", root: "/", form) == nil)
            #expect(link("", root: root, form) == nil)
        }
    }

    @Test func aNoteIDUsesItsPathAndThePlatformForm() throws {
        let id = NoteID(path: "Actions/Write DAAD motivation letter.md")
        let url = try #require(ObsidianLink.url(for: id, vaultRoot: "/Users/me/Vault"))
        #if os(macOS)
        #expect(url.absoluteString
            == "obsidian://open?path=%2FUsers%2Fme%2FVault%2FActions%2FWrite%20DAAD%20motivation%20letter.md")
        #else
        #expect(url.absoluteString
            == "obsidian://open?vault=Vault&file=Actions%2FWrite%20DAAD%20motivation%20letter.md")
        #endif
    }
}
