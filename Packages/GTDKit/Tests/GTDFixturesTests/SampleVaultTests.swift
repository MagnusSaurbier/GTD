import Testing
import Foundation
import GTDModel
@testable import GTDFixtures

struct SampleVaultTests {

    @Test func snapshotInvariants() {
        let s = Fixtures.sampleSnapshot
        #expect(Rules.countsTowardCap(s) == s.config.nextCap - 1)
        #expect(s.inbox.count == 6)
        #expect(s.actions.count >= 25)
        #expect(s.areas.count == 2)
        #expect(s.projects.count == 5)
        #expect(s.routines.count == 2)
        #expect(Set(s.routineLog.map(\.day)).count == 10)
        #expect(s.lastReview != nil)
        #expect(s.issues.isEmpty)
        // Every action id is unique and lives under Actions/.
        #expect(Set(s.actions.map(\.id)).count == s.actions.count)
        #expect(s.actions.allSatisfy { $0.id.isInside(s.config.layout.actions) })
        // No lying defaults.
        #expect(s.actions.allSatisfy { ($0.timeEstimate ?? 1) > 0 })
        // Every project link points at a project that exists.
        #expect(s.actions.allSatisfy { $0.project == nil || s.project($0.project!) != nil })
    }

    @Test func everyEntityIsRendered() {
        let files = SampleVault.files
        let s = Fixtures.sampleSnapshot
        for action in s.actions { #expect(files[action.id.path] != nil) }
        for project in s.projects { #expect(files[project.id.path] != nil) }
        for area in s.areas { #expect(files[area.id.path] != nil) }
        for routine in s.routines { #expect(files[routine.id.path] != nil) }
        for item in s.inbox { #expect(files[item.id.path] != nil) }
        #expect(files[s.config.layout.configFile] != nil)
        #expect(files["GTD/Reviews/2026/KW 37.md"] != nil)
        #expect(files.values.allSatisfy { $0.hasSuffix("\n") })
    }

    @Test func renderedFilesLookLikeTheVaultLayout() throws {
        let files = SampleVault.files
        let action = try #require(files["Actions/Reply to the DAAD info mail.md"])
        #expect(action.hasPrefix("---\nstatus: next\n"))
        #expect(action.contains("project: \"[[Projects/Applications/DAAD/DAAD]]\""))
        #expect(action.contains("due: 2026-09-17"))
        #expect(action.contains("# Why?"))
        #expect(action.contains("# What?"))
        #expect(!action.contains("timeEstimate: 0"))

        let project = try #require(files["Projects/Applications/DAAD/DAAD.md"])
        #expect(project.hasPrefix("---\nkind: project\nstatus: active\n"))
        #expect(project.contains("- [x] Collect transcripts → [[Actions/Collect DAAD transcripts]]"))
        #expect(project.contains("# Outcome"))
        #expect(project.contains("# Steps"))
        #expect(project.contains("# Log"))

        let morning = try #require(files["GTD/Routines/Morning.md"])
        #expect(morning.hasPrefix("---\ntime: \"07:00\"\n---\n"))
        #expect(morning.contains("- [ ] Frühstück\n    - [ ] Brainsmoothie\n"))
    }

    @Test func copyToTemporaryDirectoryWritesEveryFile() throws {
        let root = try SampleVault.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let written = try SampleVault.read(tree: root)
        #expect(written.count == SampleVault.files.count)
        for (path, text) in SampleVault.files {
            #expect(written[path] == text, "\(path) differs")
        }
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Knowledge/Studium/Thesis").path,
            isDirectory: &isDirectory))
    }

    /// The committed copy under `Sources/GTDFixtures/Resources/SampleVault` must match what
    /// `render` produces. Regenerate with the export test below when the fixtures change.
    @Test func committedCopyMatchesTheRenderedSnapshot() throws {
        let bundleURL = try #require(SampleVault.bundleURL, "resource bundle missing")
        let committed = try SampleVault.read(tree: bundleURL)
        #expect(committed == SampleVault.files,
                "Sources/GTDFixtures/Resources/SampleVault is stale — see its README")
    }

    /// Regenerates the committed sample vault. Opt in:
    /// `GTD_EXPORT_SAMPLE_VAULT=1 swift test --filter exportSampleVault`
    @Test func exportSampleVault() throws {
        guard let target = ProcessInfo.processInfo.environment["GTD_EXPORT_SAMPLE_VAULT"],
              target != "0"
        else { return }
        let root = URL(fileURLWithPath: target, isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try SampleVault.write(SampleVault.files, to: root)
    }
}
