import Foundation
import GTDModel
import Testing
@testable import GTDVault

@Suite("Transactions: inverse ops, rollback, and never hard-deleting")
struct VaultTransactionTests {

    private func transaction(_ files: [String: String]) -> (VaultTransaction, InMemoryFileSystem) {
        let fs = InMemoryFileSystem(files: files)
        return (VaultTransaction(fileSystem: fs, layout: .default), fs)
    }

    // MARK: put

    @Test func putOverAnExistingFileInvertsToThePreviousContent() throws {
        let (tx, fs) = transaction(["Actions/A.md": "before"])
        let inverse = try tx.commit([.put(path: "Actions/A.md", text: "after")])
        #expect(try fs.readText("Actions/A.md") == "after")
        #expect(inverse == [.put(path: "Actions/A.md", text: "before")])

        _ = try tx.commit(inverse)
        #expect(try fs.readText("Actions/A.md") == "before")
    }

    @Test func putOfANewFileInvertsToADelete() throws {
        let (tx, fs) = transaction([:])
        let inverse = try tx.commit([.put(path: "Actions/New.md", text: "hello")])
        #expect(inverse == [.delete(path: "Actions/New.md")])

        _ = try tx.commit(inverse)
        #expect(fs.exists("Actions/New.md") == false)
        // Undoing a creation still does not destroy anything.
        #expect(try fs.readText("GTD/Trash/New.md") == "hello")
    }

    // MARK: move

    @Test func moveInvertsToTheReverseMove() throws {
        let (tx, fs) = transaction(["Actions/A.md": "x"])
        let inverse = try tx.commit([.move(from: "Actions/A.md", to: "Archive/2026/09/A.md")])
        #expect(inverse == [.move(from: "Archive/2026/09/A.md", to: "Actions/A.md")])
        _ = try tx.commit(inverse)
        #expect(try fs.readText("Actions/A.md") == "x")
    }

    @Test func moveOntoAnExistingFileIsRefused() throws {
        let (tx, fs) = transaction(["Actions/A.md": "x", "Actions/B.md": "y"])
        #expect(throws: VaultError.destinationExists(path: "Actions/B.md")) {
            try tx.commit([.move(from: "Actions/A.md", to: "Actions/B.md")])
        }
        #expect(try fs.readText("Actions/B.md") == "y")   // untouched
    }

    @Test func moveOfAMissingFileFails() throws {
        let (tx, _) = transaction([:])
        #expect(throws: VaultError.self) {
            try tx.commit([.move(from: "Actions/Gone.md", to: "Actions/Here.md")])
        }
    }

    @Test func aMoveOntoItselfIsANoOp() throws {
        let (tx, fs) = transaction(["Actions/A.md": "x"])
        #expect(try tx.commit([.move(from: "Actions/A.md", to: "Actions/A.md")]).isEmpty)
        #expect(try fs.readText("Actions/A.md") == "x")
    }

    // MARK: moveFolder (R-5)

    @Test func moveFolderMovesTheTreeAndInvertsToTheMoveBack() throws {
        let (tx, fs) = transaction([
            "Lists/Read/Dune.md": "one",
            "Lists/Read/Done/Ubik.md": "two",
        ])
        let inverse = try tx.commit([.moveFolder(from: "Lists/Read", to: "Lists/Reading")])
        #expect(inverse == [.moveFolder(from: "Lists/Reading", to: "Lists/Read")])
        #expect(try fs.readText("Lists/Reading/Done/Ubik.md") == "two")

        _ = try tx.commit(inverse)
        #expect(fs.snapshotOfFiles == ["Lists/Read/Dune.md": "one", "Lists/Read/Done/Ubik.md": "two"])
    }

    @Test func moveFolderOntoAnExistingFolderIsRefused() throws {
        let (tx, fs) = transaction(["Lists/Read/A.md": "x", "Lists/Watch/B.md": "y"])
        #expect(throws: VaultError.destinationExists(path: "Lists/Watch")) {
            try tx.commit([.moveFolder(from: "Lists/Read", to: "Lists/Watch")])
        }
        #expect(fs.snapshotOfFiles == ["Lists/Read/A.md": "x", "Lists/Watch/B.md": "y"])
    }

    @Test func moveFolderOntoAnExistingFileIsRefused() throws {
        let (tx, _) = transaction(["Lists/Read/A.md": "x", "Lists/Watch": "a file, not a folder"])
        #expect(throws: VaultError.destinationExists(path: "Lists/Watch")) {
            try tx.commit([.moveFolder(from: "Lists/Read", to: "Lists/Watch")])
        }
    }

    @Test func moveFolderOfAMissingFolderFails() throws {
        let (tx, _) = transaction(["Actions/A.md": "x"])
        #expect(throws: VaultError.self) {
            try tx.commit([.moveFolder(from: "Lists/Gone", to: "Lists/Here")])
        }
        // A file is not a folder.
        #expect(throws: VaultError.self) {
            try tx.commit([.moveFolder(from: "Actions/A.md", to: "Actions/B")])
        }
    }

    @Test func aFolderCannotBeMovedInsideItself() throws {
        let (tx, fs) = transaction(["Lists/Read/A.md": "x"])
        #expect(throws: VaultError.self) {
            try tx.commit([.moveFolder(from: "Lists/Read", to: "Lists/Read/Deeper")])
        }
        #expect(try fs.readText("Lists/Read/A.md") == "x")
    }

    @Test func aFolderMoveOntoItselfIsANoOp() throws {
        let (tx, fs) = transaction(["Lists/Read/A.md": "x"])
        #expect(try tx.commit([.moveFolder(from: "Lists/Read", to: "Lists/Read")]).isEmpty)
        #expect(try fs.readText("Lists/Read/A.md") == "x")
    }

    /// The acceptance case of T02: `[moveFolder, put]` where the `put` fails leaves the tree
    /// exactly where it was.
    @Test func aFailingPutAfterAFolderMoveRollsTheFolderBack() throws {
        let files = ["Lists/Read/Dune.md": "one", "Lists/Read/Done/Ubik.md": "two"]
        let (tx, fs) = transaction(files)
        fs.failWrites(matching: ["Lists/Reading/New.md"])

        #expect(throws: VaultError.self) {
            try tx.commit([
                .moveFolder(from: "Lists/Read", to: "Lists/Reading"),
                .put(path: "Lists/Reading/New.md", text: "never lands"),
            ])
        }
        #expect(fs.snapshotOfFiles == files)
        #expect(!fs.folderExists("Lists/Reading"))
    }

    /// The same acceptance case on a **real** directory: `InMemoryFileSystem` could be wrong
    /// about what a file system does with a tree, so the rollback is proved on disk too. The put
    /// fails because its parent path is a file, which no injection is needed for.
    @Test func aFailingPutAfterAFolderMoveRollsBackOnARealFileSystem() throws {
        let vault = try TempVault()
        let fs = PlainFileSystem(root: vault.url)
        let tx = VaultTransaction(fileSystem: fs, layout: .default)
        try fs.writeText("one", to: "Lists/Read/Dune.md")
        try fs.writeText("two", to: "Lists/Read/Done/Ubik.md")
        let before = try fs.listFiles().map(\.path)

        #expect(throws: VaultError.self) {
            try tx.commit([
                .moveFolder(from: "Lists/Read", to: "Lists/Reading"),
                // `Dune.md` is a file, so creating it as a folder — and the write below it —
                // cannot work.
                .put(path: "Lists/Reading/Dune.md/never.md", text: "boom"),
            ])
        }

        #expect(try fs.listFiles().map(\.path) == before)
        #expect(vault.read("Lists/Read/Dune.md") == "one")
        #expect(vault.read("Lists/Read/Done/Ubik.md") == "two")
        #expect(!vault.exists("Lists/Reading"))
    }

    @Test func aFailingRollbackOfAFolderMoveIsReportedNotSwallowed() throws {
        let (tx, fs) = transaction(["Lists/Read/A.md": "x"])
        // The folder move succeeds, the put fails, and moving the folder back fails too.
        fs.failWrites(matching: ["Lists/Reading/New.md"])
        fs.failMoves(to: ["Lists/Read"])

        var caught: VaultError?
        do {
            _ = try tx.commit([
                .moveFolder(from: "Lists/Read", to: "Lists/Reading"),
                .put(path: "Lists/Reading/New.md", text: "boom"),
            ])
        } catch let error as VaultError {
            caught = error
        }
        guard case .rollbackFailed = caught else {
            Issue.record("expected rollbackFailed, got \(String(describing: caught))")
            return
        }
        // The vault really is in the mixed state the error announces — which is why it is loud.
        #expect(try fs.readText("Lists/Reading/A.md") == "x")
    }

    // MARK: delete → trash

    @Test func deleteMovesIntoTrashAndInvertsToAMoveBack() throws {
        let (tx, fs) = transaction(["Inbox/2026-09-19 081204.md": "capture"])
        let inverse = try tx.commit([.delete(path: "Inbox/2026-09-19 081204.md")])

        #expect(fs.exists("Inbox/2026-09-19 081204.md") == false)
        #expect(try fs.readText("GTD/Trash/2026-09-19 081204.md") == "capture")
        #expect(inverse == [.move(from: "GTD/Trash/2026-09-19 081204.md",
                                  to: "Inbox/2026-09-19 081204.md")])

        _ = try tx.commit(inverse)
        #expect(try fs.readText("Inbox/2026-09-19 081204.md") == "capture")
    }

    @Test func aSecondDeleteOfTheSameNameGetsAFreeTrashName() throws {
        let (tx, fs) = transaction([
            "Actions/A.md": "first",
            "GTD/Trash/A.md": "an older casualty",
        ])
        let inverse = try tx.commit([.delete(path: "Actions/A.md")])
        #expect(try fs.readText("GTD/Trash/A.md") == "an older casualty")   // not overwritten
        #expect(try fs.readText("GTD/Trash/A 2.md") == "first")
        #expect(inverse == [.move(from: "GTD/Trash/A 2.md", to: "Actions/A.md")])
    }

    @Test func deletingSomethingThatIsAlreadyGoneIsANoOp() throws {
        let (tx, _) = transaction([:])
        #expect(try tx.commit([.delete(path: "Actions/Gone.md")]).isEmpty)
    }

    // MARK: Ordering and rollback

    @Test func inverseOpsComeBackInUndoOrder() throws {
        let (tx, fs) = transaction(["Actions/A.md": "x"])
        let inverse = try tx.commit([
            .put(path: "Actions/B.md", text: "new"),
            .move(from: "Actions/A.md", to: "Actions/C.md"),
        ])
        // Reverse order: undo the move first, then the creation.
        #expect(inverse == [
            .move(from: "Actions/C.md", to: "Actions/A.md"),
            .delete(path: "Actions/B.md"),
        ])
        _ = try tx.commit(inverse)
        #expect(try fs.readText("Actions/A.md") == "x")
        #expect(fs.exists("Actions/B.md") == false)
        #expect(fs.exists("Actions/C.md") == false)
    }

    @Test func aFailureInTheMiddleRollsBackEverythingBefore() throws {
        let (tx, fs) = transaction(["Actions/A.md": "original", "Actions/B.md": "keep"])
        fs.failWrites(matching: ["Actions/C.md"])

        #expect(throws: VaultError.self) {
            try tx.commit([
                .put(path: "Actions/A.md", text: "changed"),
                .move(from: "Actions/B.md", to: "Actions/B moved.md"),
                .put(path: "Actions/C.md", text: "never lands"),
            ])
        }

        #expect(try fs.readText("Actions/A.md") == "original")
        #expect(try fs.readText("Actions/B.md") == "keep")
        #expect(fs.exists("Actions/B moved.md") == false)
        #expect(fs.exists("Actions/C.md") == false)
    }

    @Test func rollbackOfACreationTrashesItRatherThanLosingIt() throws {
        let (tx, fs) = transaction([:])
        fs.failWrites(matching: ["Actions/Second.md"])
        #expect(throws: VaultError.self) {
            try tx.commit([
                .put(path: "Actions/First.md", text: "half-applied"),
                .put(path: "Actions/Second.md", text: "boom"),
            ])
        }
        #expect(fs.exists("Actions/First.md") == false)
        #expect(try fs.readText("GTD/Trash/First.md") == "half-applied")
    }

    @Test func aFailingRollbackIsReportedNotSwallowed() throws {
        let (tx, fs) = transaction(["Actions/A.md": "x"])
        // The move succeeds, the following put fails, and moving A back fails too.
        fs.failWrites(matching: ["Actions/C.md"])
        fs.failMoves(to: ["Actions/A.md"])

        var caught: VaultError?
        do {
            _ = try tx.commit([
                .move(from: "Actions/A.md", to: "Actions/B.md"),
                .put(path: "Actions/C.md", text: "boom"),
            ])
        } catch let error as VaultError {
            caught = error
        }
        guard case .rollbackFailed = caught else {
            Issue.record("expected rollbackFailed, got \(String(describing: caught))")
            return
        }
    }

    @Test func anEmptyCommitDoesNothing() throws {
        let (tx, _) = transaction([:])
        #expect(try tx.commit([]).isEmpty)
    }
}
