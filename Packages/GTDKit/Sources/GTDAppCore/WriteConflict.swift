import Foundation
import GTDModel

/// A write the stale-write guard refused (N3), with everything the person needs to settle it:
/// what both sides started from, what this device wanted to write, what the vault holds now,
/// and a proposed merge (ARCHITECTURE §6, 2026-09-25).
///
/// Paths matter as much as texts: a note's title *is* its file name, so "renamed on the Mac,
/// edited on the phone" is `theirsPath != basePath` plus `mine != base`. `nil` texts mean the
/// note is gone on that side (trashed on this device, or no longer found in the vault).
public struct WriteConflict: Sendable, Equatable, Identifiable {
    /// `UndoLabel` of the refused command — the words the person saw in the toast.
    public var label: String
    /// Where the note was when this device's snapshot was taken.
    public var basePath: String
    /// What the file held then, as this device's snapshot knew it. `nil` when the command
    /// created the note.
    public var base: String?
    /// Where this device would have written the note (differs from `basePath` on a rename).
    public var path: String
    /// The text this device would have written; `nil` when it trashed the note.
    public var mine: String?
    /// Where the vault holds the note now; `nil` when it cannot be found any more.
    public var theirsPath: String?
    /// What the vault holds there now.
    public var theirs: String?

    public init(
        label: String, basePath: String, base: String?, path: String, mine: String?,
        theirsPath: String?, theirs: String?
    ) {
        self.label = label
        self.basePath = basePath
        self.base = base
        self.path = path
        self.mine = mine
        self.theirsPath = theirsPath
        self.theirs = theirs
    }

    public var id: String { basePath }

    /// True when the other side moved the note to a new title.
    public var theirsRenamed: Bool { theirsPath != nil && theirsPath != basePath }
    /// True when this device moved the note to a new title.
    public var mineRenamed: Bool { path != basePath }

    /// The merge the sheet opens with: the newer (vault) side wins wherever both changed the
    /// same thing — the title as much as a line — and everything changed on one side only is
    /// kept from that side.
    public var suggestion: MergeSuggestion {
        let suggestedPath = theirsRenamed ? theirsPath! : path
        switch (mine, theirs) {
        case (nil, nil):
            return MergeSuggestion(path: suggestedPath, text: base ?? "", conflicts: 0)
        case let (mine?, nil):
            return MergeSuggestion(path: suggestedPath, text: mine, conflicts: 0)
        case let (nil, theirs?):
            return MergeSuggestion(path: suggestedPath, text: theirs, conflicts: 0)
        case let (mine?, theirs?):
            let merged = ThreeWayMerge.merge(base: base ?? "", mine: mine, theirs: theirs)
            return MergeSuggestion(path: suggestedPath, text: merged.text, conflicts: merged.conflicts)
        }
    }
}

/// What the conflict sheet proposes: a path (the title, in effect) and the merged text, plus
/// how many passages changed on both sides and were settled in the vault's favour.
public struct MergeSuggestion: Sendable, Equatable {
    public var path: String
    public var text: String
    public var conflicts: Int

    public init(path: String, text: String, conflicts: Int) {
        self.path = path
        self.text = text
        self.conflicts = conflicts
    }
}

/// Why a backend could not resolve a conflict.
public enum ConflictError: Error, Equatable, CustomStringConvertible {
    /// The backend has no files to merge into (`InMemoryBackend`).
    case unsupported

    public var description: String {
        switch self {
        case .unsupported: "This backend cannot write a merged note."
        }
    }
}

/// Line-based three-way merge (diff3 without conflict markers).
///
/// Both sides are diffed against the base by longest common subsequence; the merge walks the
/// three texts in lockstep, copies lines all three agree on, takes a changed hunk from the side
/// that changed it, and where both changed it differently takes **theirs** — the vault's, newer
/// side — while counting the hunk so the UI can say so. Notes are small (frontmatter plus a few
/// paragraphs), so the quadratic LCS is fine; a `CRLF` file merges line by line like any other
/// because the `\r` stays on its line.
public enum ThreeWayMerge {

    public struct Result: Sendable, Equatable {
        public var text: String
        /// Hunks changed on both sides, settled in favour of `theirs`.
        public var conflicts: Int

        public init(text: String, conflicts: Int) {
            self.text = text
            self.conflicts = conflicts
        }
    }

    public static func merge(base: String, mine: String, theirs: String) -> Result {
        if mine == theirs { return Result(text: mine, conflicts: 0) }
        if mine == base { return Result(text: theirs, conflicts: 0) }
        if theirs == base { return Result(text: mine, conflicts: 0) }

        let b = lines(base), m = lines(mine), t = lines(theirs)
        let mineOf = matches(b, m)
        let theirsOf = matches(b, t)

        var out: [Substring] = []
        var conflicts = 0
        var i = 0, j = 0, k = 0
        while i < b.count || j < m.count || k < t.count {
            if i < b.count, mineOf[i] == j, theirsOf[i] == k {
                out.append(b[i])
                i += 1; j += 1; k += 1
                continue
            }
            // The next base line both sides kept is where the three texts are in step again.
            var n = i
            while n < b.count, mineOf[n] == nil || theirsOf[n] == nil { n += 1 }
            let jEnd = n < b.count ? mineOf[n]! : m.count
            let kEnd = n < b.count ? theirsOf[n]! : t.count
            let baseHunk = Array(b[i..<n])
            let mineHunk = Array(m[j..<jEnd])
            let theirsHunk = Array(t[k..<kEnd])
            if mineHunk == baseHunk {
                out += theirsHunk
            } else if theirsHunk == baseHunk || mineHunk == theirsHunk {
                out += mineHunk
            } else {
                out += theirsHunk
                conflicts += 1
            }
            i = n; j = jEnd; k = kEnd
        }
        return Result(text: out.joined(separator: "\n"), conflicts: conflicts)
    }

    private static func lines(_ text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// For every line of `a`, the index of the line of `b` it is paired with in a longest
    /// common subsequence, or `nil` when the line is not part of it. Pairs are increasing in
    /// both indices, which is what the merge walk relies on.
    private static func matches(_ a: [Substring], _ b: [Substring]) -> [Int?] {
        let n = a.count, m = b.count
        var table = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i][j] = a[i] == b[j]
                        ? table[i + 1][j + 1] + 1
                        : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var result = [Int?](repeating: nil, count: n)
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] {
                result[i] = j
                i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return result
    }
}
