import Foundation
import GTDModel
import Testing
@testable import GTDVault

/// #53 — an open action whose `project:` names no project note is reported, so the user learns
/// why the link shows nothing and where to fix it. The action itself stays indexed.
struct DanglingProjectLinkTests {

    private func snapshot(_ files: [String: String]) throws -> VaultSnapshot {
        var index = VaultIndex(parser: StubNoteParser())
        try index.refresh(using: InMemoryFileSystem(files: files))
        return index.snapshot(today: MiniVault.today)
    }

    @Test func anOpenActionWithADanglingProjectLinkIsReported() throws {
        let snapshot = try snapshot([
            "Projects/Karriere/Manage&More/Manage&More.md": "---\nkind: project\nstatus: active\n---\n",
            "Actions/Hackathon.md":
                "---\nstatus: next\nproject: Projects/Karriere/Manage&More 1/Manage&More.md\n---\n",
            "Actions/Linked.md": "---\nstatus: next\nproject: Projects/Karriere/Manage&More/Manage&More.md\n---\n",
            "Actions/Old.md": "---\nstatus: done\nproject: Projects/Gone/Gone.md\n---\n",
        ])

        #expect(snapshot.actions.count == 3)
        let issue = try #require(snapshot.issues.first { $0.path == "Actions/Hackathon.md" })
        #expect(issue.message.contains("Projects/Karriere/Manage&More 1/Manage&More.md"))
        // A linked action and a closed one are not reported.
        #expect(snapshot.issues.count == 1)
    }
}
