import Foundation
import GTDModel
import Testing
@testable import GTDVault

@Suite("Paths, classification and the frontmatter peek")
struct VaultPathTests {

    // MARK: VaultPath

    @Test func normalizesSeparatorsAndStrips() {
        #expect(VaultPath.normalize("/Actions//Foo.md/") == "Actions/Foo.md")
        #expect(VaultPath.normalize("Actions\\Foo.md") == "Actions/Foo.md")
        #expect(VaultPath.normalize("") == "")
    }

    @Test func rejectsPathsThatEscapeTheVault() {
        #expect(VaultPath.isSafe("Actions/Foo.md"))
        #expect(!VaultPath.isSafe("../secrets.md"))
        #expect(!VaultPath.isSafe("Actions/../../etc/passwd"))
        #expect(!VaultPath.isSafe(""))
    }

    @Test func splitsNamesStemsAndExtensions() {
        #expect(VaultPath.folder(of: "Projects/Applications/DAAD/DAAD.md") == "Projects/Applications/DAAD")
        #expect(VaultPath.name(of: "Projects/DAAD/DAAD.md") == "DAAD.md")
        #expect(VaultPath.stem(of: "Projects/DAAD/DAAD.md") == "DAAD")
        #expect(VaultPath.extension(of: "Projects/DAAD/notes.pdf") == "pdf")
        #expect(VaultPath.stem(of: ".hidden") == ".hidden")
        #expect(VaultPath.folder(of: "Config.md") == "")
    }

    @Test func recognisesEvictediCloudPlaceholders() {
        #expect(VaultPath.evictedOriginal(of: "Actions/.Foo.md.icloud") == "Actions/Foo.md")
        #expect(VaultPath.evictedOriginal(of: "Actions/Foo.md") == nil)
        #expect(VaultPath.evictedOriginal(of: "Actions/.icloud") == nil)
    }

    // MARK: Classification

    private let classifier = VaultClassifier()

    @Test func classifiesEveryFolderOfTheVaultLayout() {
        #expect(classifier.kind(of: "Inbox/2026-09-19 081204.md") == .inbox)
        #expect(classifier.kind(of: "Actions/Fix the bike light.md") == .action)
        #expect(classifier.kind(of: "Archive/2026/08/Old.md") == .archive)
        #expect(classifier.kind(of: "GTD/Trash/Thrown away.md") == .trash)
        #expect(classifier.kind(of: "GTD/Config.md") == .config)
        #expect(classifier.kind(of: "GTD/Routines/Morning.md") == .routine)
        #expect(classifier.kind(of: "GTD/RoutineLog/2026-09-18--iPhone.md") == .routineLog)
        #expect(classifier.kind(of: "GTD/Reviews/2026/KW 37.md") == .review)
        #expect(classifier.kind(of: "Knowledge/Studium/Thesis/Sources.md") == .knowledge)
        #expect(classifier.kind(of: "Somewhere else/Note.md") == .other)
    }

    @Test func projectNoteIsTheOneNamedLikeItsFolder() {
        #expect(classifier.kind(of: "Projects/Applications/DAAD/DAAD.md") == .projectNote)
        #expect(classifier.kind(of: "Projects/Applications/Applications.md") == .projectNote)
        // Anything else in the folder is reference material (P6).
        #expect(classifier.kind(of: "Projects/Applications/DAAD/Transcript.pdf") == .reference)
        #expect(classifier.kind(of: "Projects/Applications/DAAD/Scratch notes.md") == .reference)
    }

    @Test func nonMarkdownInsideActionsIsLeftAlone() {
        #expect(classifier.kind(of: "Actions/attachment.png") == .other)
        #expect(classifier.kind(of: "Inbox/voice memo.m4a") == .other)
    }

    @Test func knowledgeFoldersAreReportedWithoutTheirPrefix() {
        #expect(classifier.knowledgeFolder(of: "Knowledge/Studium/Thesis") == "Studium/Thesis")
        #expect(classifier.knowledgeFolder(of: "Knowledge") == nil)
        #expect(classifier.knowledgeFolder(of: "Actions") == nil)
    }

    @Test func honoursACustomLayout() {
        let custom = VaultClassifier(layout: VaultLayout(inbox: "00 Inbox", actions: "10 Actions"))
        #expect(custom.kind(of: "00 Inbox/note.md") == .inbox)
        #expect(custom.kind(of: "10 Actions/note.md") == .action)
        #expect(custom.kind(of: "Inbox/note.md") == .other)
    }

    // MARK: Conflict copies (N3 §7.5)

    @Test func reportsConflictCopiesOnlyWhenTheOriginalIsThere() {
        let copies = VaultClassifier.conflictCopies(among: [
            "Actions/Fix the bike light.md",
            "Actions/Fix the bike light 2.md",
            "Actions/Lonely 3.md",             // no original — not a conflict copy
            "Actions/Buy milk 1.md",           // " 1" is not an iCloud conflict suffix
            "Actions/Buy milk.md",
            "Actions/Notes 2025.md",           // four digits: a year, not a suffix
            "Actions/Notes.md",
        ])
        #expect(copies == ["Actions/Fix the bike light 2.md"])
    }

    @Test func conflictCopiesAreNeverTouchedOnlyReported() {
        // The classifier has no mutating API at all — the only thing it can do is name them.
        let copies = VaultClassifier.conflictCopies(among: ["A.md", "A 2.md"])
        #expect(copies == ["A 2.md"])
    }

    // MARK: Frontmatter peek

    @Test func readsTopLevelScalars() {
        let text = """
        ---
        kind: project
        status: "on-hold"
        area: "[[Projects/Applications/Applications]]"
        nested:
          key: value
        ---
        # Outcome
        kind: not-this-one
        """
        #expect(Frontmatter.scalar("kind", in: text) == "project")
        #expect(Frontmatter.scalar("status", in: text) == "on-hold")
        #expect(Frontmatter.scalar("area", in: text) == "[[Projects/Applications/Applications]]")
        #expect(Frontmatter.scalar("key", in: text) == nil)       // indented: not top level
        #expect(Frontmatter.scalar("missing", in: text) == nil)
    }

    @Test func handlesNotesWithoutFrontmatter() {
        #expect(Frontmatter.block(in: "# Just a heading\n") == nil)
        #expect(Frontmatter.scalar("kind", in: "# Just a heading\n") == nil)
        #expect(Frontmatter.block(in: "---\nkind: area\n") == nil)   // unterminated
    }

    @Test func emptyFrontmatterValueCountsAsAbsent() {
        // "no lying defaults": an empty key is not a value.
        #expect(Frontmatter.scalar("status", in: "---\nstatus:\n---\nbody") == nil)
    }
}
