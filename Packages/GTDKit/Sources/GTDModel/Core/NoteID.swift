import Foundation

/// Identity of a note: its path relative to the vault root, always "/"-separated and
/// always including the `.md` extension for real files.
public struct NoteID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let path: String

    public init(path: String) {
        self.path = NoteID.normalize(path)
    }

    /// Filename without the `.md` extension — the human-readable title of most notes.
    public var title: String {
        let last = path.split(separator: "/").last.map(String.init) ?? path
        return last.hasSuffix(".md") ? String(last.dropLast(3)) : last
    }

    /// Everything before the filename; `""` for a note at the vault root.
    public var folder: String {
        var parts = path.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return "" }
        parts.removeLast()
        return parts.joined(separator: "/")
    }

    public var components: [String] { path.split(separator: "/").map(String.init) }

    /// True when this note lives inside `folder` (at any depth).
    public func isInside(_ folder: String) -> Bool {
        let f = NoteID.normalize(folder)
        guard !f.isEmpty else { return true }
        return path == f || path.hasPrefix(f + "/")
    }

    public var description: String { path }

    public static func < (lhs: NoteID, rhs: NoteID) -> Bool { lhs.path < rhs.path }

    /// Collapses `\`, duplicate and leading/trailing separators. Does not resolve `..`.
    private static func normalize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }
}
