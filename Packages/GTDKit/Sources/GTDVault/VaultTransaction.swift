import Foundation
import GTDModel

/// Applies `[VaultFileOp]` to a vault and produces the inverse ops for the undo journal.
///
/// Two rules the whole app depends on:
///
/// 1. **Nothing is ever hard-deleted.** `.delete` is a move into `GTD/Trash/`, so its inverse is
///    a move back. `VaultFileSystem` has no delete at all (ARCHITECTURE §3).
/// 2. **All or nothing, as far as the file system allows.** Ops are applied in order; when one
///    fails, the ones already applied are undone in reverse order before the error is rethrown.
///    A failure *during* rollback is reported as `VaultError.rollbackFailed` with both reasons —
///    the vault is then in a mixed state and the user must be told, never silently.
///
/// The returned inverse ops are **already in undo order**: feeding them straight back into
/// `commit` restores the previous state.
struct VaultTransaction {
    let fileSystem: any VaultFileSystem
    let layout: VaultLayout

    func commit(_ ops: [VaultFileOp]) throws -> [VaultFileOp] {
        var applied: [VaultFileOp] = []   // inverses, in application order
        for op in ops {
            do {
                applied.append(contentsOf: try apply(op))
            } catch {
                try rollback(applied, after: error)
                throw error
            }
        }
        return applied.reversed()
    }

    // MARK: One op

    /// Applies one op and returns its inverse (empty when the op was a no-op).
    private func apply(_ op: VaultFileOp) throws -> [VaultFileOp] {
        switch op {
        case let .put(path, text):
            let previous = try? fileSystem.readText(path)
            try fileSystem.writeText(text, to: path)
            // Restoring a file that did not exist means trashing the one we just created.
            return [previous.map { VaultFileOp.put(path: path, text: $0) }
                ?? VaultFileOp.delete(path: path)]

        case let .move(from, to):
            let source = VaultPath.normalize(from)
            let destination = VaultPath.normalize(to)
            guard source != destination else { return [] }
            guard fileSystem.exists(source) else {
                throw VaultError.ioFailed(path: source, reason: "no such file to move")
            }
            guard !fileSystem.exists(destination) else {
                // Never overwrite: the caller (T16) decides on a new name, we do not guess.
                throw VaultError.destinationExists(path: destination)
            }
            try fileSystem.move(source, to: destination)
            return [.move(from: destination, to: source)]

        case let .moveFolder(from, to):
            let source = VaultPath.normalize(from)
            let destination = VaultPath.normalize(to)
            guard source != destination else { return [] }
            // Moving a folder below itself would make the source disappear into the destination.
            guard !VaultPath.isInside(destination, source) else {
                throw VaultError.ioFailed(
                    path: destination, reason: "a folder cannot be moved inside itself")
            }
            guard fileSystem.folderExists(source) else {
                throw VaultError.ioFailed(path: source, reason: "no such folder to move")
            }
            guard !fileSystem.exists(destination), !fileSystem.folderExists(destination) else {
                // Never overwrite, and never merge two trees: the caller picks another name.
                throw VaultError.destinationExists(path: destination)
            }
            try fileSystem.moveFolder(source, to: destination)
            return [.moveFolder(from: destination, to: source)]

        case let .delete(path):
            let source = VaultPath.normalize(path)
            // Idempotent: a file an external edit already removed is not an error.
            guard fileSystem.exists(source) else { return [] }
            let destination = freeTrashPath(for: source)
            try fileSystem.move(source, to: destination)
            return [.move(from: destination, to: source)]
        }
    }

    /// Replays inverse ops without recording anything — used for rollback only.
    private func applyRaw(_ op: VaultFileOp) throws {
        switch op {
        case let .put(path, text):
            try fileSystem.writeText(text, to: path)
        case let .move(from, to):
            let source = VaultPath.normalize(from)
            let destination = VaultPath.normalize(to)
            guard source != destination, fileSystem.exists(source) else { return }
            if fileSystem.exists(destination) {
                throw VaultError.destinationExists(path: destination)
            }
            try fileSystem.move(source, to: destination)
        case let .moveFolder(from, to):
            let source = VaultPath.normalize(from)
            let destination = VaultPath.normalize(to)
            guard source != destination, fileSystem.folderExists(source) else { return }
            if fileSystem.exists(destination) || fileSystem.folderExists(destination) {
                throw VaultError.destinationExists(path: destination)
            }
            try fileSystem.moveFolder(source, to: destination)
        case let .delete(path):
            let source = VaultPath.normalize(path)
            guard fileSystem.exists(source) else { return }
            try fileSystem.move(source, to: freeTrashPath(for: source))
        }
    }

    private func rollback(_ inverses: [VaultFileOp], after original: any Error) throws {
        var failures: [String] = []
        for inverse in inverses.reversed() {
            do { try applyRaw(inverse) } catch { failures.append("\(error)") }
        }
        guard !failures.isEmpty else { return }
        throw VaultError.rollbackFailed(
            reason: "\(original)", rollbackReason: failures.joined(separator: "; "))
    }

    // MARK: Trash

    /// A free name under `GTD/Trash/`. Collisions there are harmless — the trash is not part of
    /// the snapshot — so unlike a real move this one picks the next free suffix instead of
    /// failing, and the inverse op carries the name that was actually used.
    func freeTrashPath(for path: String) -> String {
        let base = VaultPath.normalize(layout.trashPath(for: NoteID(path: path)).path)
        guard fileSystem.exists(base) else { return base }
        let folder = VaultPath.folder(of: base)
        let stem = VaultPath.stem(of: base)
        let ext = VaultPath.extension(of: base)
        for suffix in 2...999 {
            let candidate = VaultPath.join(
                folder, ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)")
            if !fileSystem.exists(candidate) { return candidate }
        }
        return VaultPath.join(folder, "\(stem) \(UUID().uuidString).\(ext)")
    }
}
