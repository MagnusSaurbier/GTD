import Foundation
import GTDModel
import Yams

/// A markdown file split into YAML frontmatter and body, **without losing a byte**.
///
/// The document keeps the file as `RawLine`s and edits it by *patching lines*. Values are read
/// through Yams (which handles quoting, flow/block styles, anchors and escapes correctly), but
/// nothing is ever re-serialised: a key the caller does not touch keeps its exact original text,
/// and so do unknown keys, comments, blank lines, key order and the line endings.
///
/// ```
/// var doc = try FrontmatterDocument(text: fileText, path: id.path)
/// doc.setValue("status", "next")          // rewrites one line
/// let text = doc.text                     // == fileText when nothing changed
/// ```
public struct FrontmatterDocument {

    /// A UTF-8 BOM, when the file had one.
    public private(set) var bom: String
    /// The `---` line that opens the frontmatter, if any.
    private var openDelimiter: RawLine?
    /// The lines *between* the delimiters.
    private var frontmatterLines: [RawLine]
    /// The `---` (or `...`) line that closes the frontmatter, if any.
    private var closeDelimiter: RawLine?
    /// Everything after the closing delimiter — or the whole file when there is no frontmatter.
    public internal(set) var bodyLines: [RawLine]
    /// Terminator used for lines this document creates.
    public private(set) var terminator: String

    /// The parsed frontmatter mapping, or `nil` when the file has no frontmatter.
    /// Kept only for *reading*; patching never goes through it.
    private var root: Node?

    /// Vault-relative path, used for error messages only.
    public let path: String

    // MARK: - Parsing

    public init(text: String, path: String) throws {
        self.path = path
        let (bom, rest) = RawText.stripBOM(text)
        self.bom = bom
        var lines = RawText.split(rest)
        self.terminator = RawText.dominantTerminator(lines)

        if let first = lines.first, FrontmatterDocument.isOpeningDelimiter(first.content),
           let close = lines.dropFirst().firstIndex(where: { FrontmatterDocument.isClosingDelimiter($0.content) }) {
            openDelimiter = lines[0]
            frontmatterLines = Array(lines[1..<close])
            closeDelimiter = lines[close]
            bodyLines = Array(lines[(close + 1)...])
        } else {
            openDelimiter = nil
            frontmatterLines = []
            closeDelimiter = nil
            bodyLines = lines
        }
        lines = []

        if openDelimiter != nil {
            let yaml = RawText.join(frontmatterLines)
            if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                root = nil
            } else {
                do {
                    root = try Yams.compose(yaml: yaml)
                } catch {
                    throw NoteCodecError.unreadable(
                        path: path, reason: "Frontmatter is not valid YAML: \(error)")
                }
            }
        }
    }

    /// `---` at the very start of the file. Trailing spaces are tolerated; nothing else is.
    static func isOpeningDelimiter(_ content: String) -> Bool {
        content.trimmingCharacters(in: .whitespaces) == "---"
    }

    static func isClosingDelimiter(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        return trimmed == "---" || trimmed == "..."
    }

    // MARK: - Whole-file text

    public var text: String {
        var out = bom
        if let openDelimiter { out += openDelimiter.content + openDelimiter.terminator }
        out += RawText.join(frontmatterLines)
        if let closeDelimiter { out += closeDelimiter.content + closeDelimiter.terminator }
        out += RawText.join(bodyLines)
        return out
    }

    public var hasFrontmatter: Bool { openDelimiter != nil }

    /// The body as plain text (no frontmatter, terminators as in the file).
    public var body: String { RawText.join(bodyLines) }

    // MARK: - Reading values

    private func node(_ key: String) -> Node? {
        guard let root, case .mapping = root else { return nil }
        return root[key]
    }

    /// True when the key is physically present, whatever its value (including an empty one).
    public func hasKey(_ key: String) -> Bool { entry(for: key) != nil }

    /// The raw scalar text of `key` — unquoted and unescaped by Yams, but *not* re-typed:
    /// `created: 2026-09-18T21:04:11+02:00` yields the original string, not a `Date`.
    /// An explicitly empty value (`key:` or `key: ""`) yields `nil`.
    public func scalar(_ key: String) -> String? {
        guard let value = node(key)?.scalar?.string else { return nil }
        return value.isEmpty ? nil : value
    }

    /// A list value, accepting both `[a, b]` and a block sequence. A scalar counts as a
    /// one-element list (TaskNotes wrote `contexts: phone` occasionally).
    public func list(_ key: String) -> [String]? {
        guard let node = node(key) else { return nil }
        if let sequence = node.sequence {
            return sequence.compactMap { $0.scalar?.string }
        }
        if let single = node.scalar?.string, !single.isEmpty { return [single] }
        return nil
    }

    public func int(_ key: String) -> Int? { scalar(key).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }

    public func day(_ key: String) -> Day? { scalar(key).flatMap { Day(iso: $0) } }

    public func timestamp(_ key: String, defaultTimeZone: TimeZone) -> Date? {
        scalar(key).flatMap { YAMLScalar.parseTimestamp($0, defaultTimeZone: defaultTimeZone) }
    }

    /// A sequence of mappings, e.g. the routine log's `entries:`.
    public func mappings(_ key: String) -> [Node]? {
        node(key)?.sequence.map(Array.init)
    }

    /// A nested mapping, e.g. the config's `layout:`.
    public func mappingNode(_ key: String) -> Node? {
        guard let node = node(key), case .mapping = node else { return nil }
        return node
    }

    // MARK: - Top-level key regions

    /// One top-level key and the lines it owns.
    struct Entry {
        /// The key as written, without quotes.
        var key: String
        /// Everything before the `:` on the key line, verbatim (keeps quoting and spacing).
        var keyText: String
        /// Index of the key line in `frontmatterLines`.
        var start: Int
        /// One past the last line that belongs to the value (trailing blanks/comments excluded).
        var end: Int
    }

    var entries: [Entry] {
        var found: [Entry] = []
        for (index, line) in frontmatterLines.enumerated() {
            guard let (key, keyText) = FrontmatterDocument.parseKeyLine(line.content) else { continue }
            if var last = found.popLast() {
                last.end = index
                found.append(last)
            }
            found.append(Entry(key: key, keyText: keyText, start: index, end: frontmatterLines.count))
        }
        // A key's region must not swallow the blank lines and comments that visually separate it
        // from the next key — otherwise setting one field deletes the user's spacing.
        return found.map { entry in
            var trimmed = entry
            while trimmed.end > trimmed.start + 1 {
                let line = frontmatterLines[trimmed.end - 1]
                let content = line.content.trimmingCharacters(in: .whitespaces)
                if content.isEmpty || content.hasPrefix("#") { trimmed.end -= 1 } else { break }
            }
            return trimmed
        }
    }

    func entry(for key: String) -> Entry? { entries.first { $0.key == key } }

    /// Recognises a top-level `key:` line: no indentation, not a comment, not a sequence item.
    /// Returns the unquoted key and the verbatim text before the colon.
    static func parseKeyLine(_ content: String) -> (key: String, keyText: String)? {
        guard let first = content.first, first != " ", first != "\t", first != "#" else { return nil }
        if first == "-" { return nil }           // `- item`, `---`
        let scalars = Array(content)

        if first == "\"" || first == "'" {
            let quote = first
            var index = 1
            while index < scalars.count {
                if scalars[index] == "\\", quote == "\"" { index += 2; continue }
                if scalars[index] == quote { break }
                index += 1
            }
            guard index < scalars.count, index + 1 < scalars.count, scalars[index + 1] == ":" else { return nil }
            let keyText = String(scalars[0...index])
            let inner = String(scalars[1..<index])
            let after = index + 2
            guard after == scalars.count || scalars[after] == " " || scalars[after] == "\t" else { return nil }
            return (inner, keyText)
        }

        var index = 0
        while index < scalars.count {
            if scalars[index] == ":" {
                let after = index + 1
                if after == scalars.count || scalars[after] == " " || scalars[after] == "\t" {
                    let keyText = String(scalars[0..<index])
                    let key = keyText.trimmingCharacters(in: .whitespaces)
                    return key.isEmpty ? nil : (key, keyText)
                }
            }
            if scalars[index] == "#" { return nil }
            index += 1
        }
        return nil
    }

    // MARK: - Patching

    /// Replaces (or inserts) `key: rendered`. Nothing happens when the line is already identical.
    ///
    /// `canonicalOrder` decides where a *new* key goes: directly before the first key that ranks
    /// after it. Keys the order does not mention never move and never constrain the insertion.
    public mutating func setValue(_ key: String, _ rendered: String, canonicalOrder: [String] = []) {
        setLines(key, [rendered.isEmpty ? "\(key):" : "\(key): \(rendered)"], canonicalOrder: canonicalOrder)
    }

    /// Replaces (or inserts) a multi-line value. `lines[0]` must start with the key.
    public mutating func setLines(_ key: String, _ lines: [String], canonicalOrder: [String] = []) {
        guard !lines.isEmpty else { return removeValue(key) }
        if let existing = entry(for: key) {
            // Keep the file's own spelling of the key (quoted keys, `key :`, …).
            var replacement = lines
            if let colon = lines[0].firstIndex(of: ":") {
                replacement[0] = existing.keyText + String(lines[0][colon...])
            }
            let old = frontmatterLines[existing.start..<existing.end]
            if old.count == replacement.count,
               zip(old, replacement).allSatisfy({ $0.content == $1 }) { return }
            let keepTerminator = frontmatterLines[existing.start].terminator.isEmpty
                ? terminator : frontmatterLines[existing.start].terminator
            frontmatterLines.replaceSubrange(
                existing.start..<existing.end,
                with: replacement.map { RawLine(content: $0, terminator: keepTerminator) })
        } else {
            ensureFrontmatter()
            let insertAt = insertionIndex(for: key, canonicalOrder: canonicalOrder)
            frontmatterLines.insert(
                contentsOf: lines.map { RawLine(content: $0, terminator: terminator) }, at: insertAt)
        }
    }

    /// Removes the key and the lines belonging to its value. Unknown keys are untouched.
    public mutating func removeValue(_ key: String) {
        guard let existing = entry(for: key) else { return }
        frontmatterLines.removeSubrange(existing.start..<existing.end)
    }

    private func insertionIndex(for key: String, canonicalOrder: [String]) -> Int {
        guard let rank = canonicalOrder.firstIndex(of: key) else { return frontmatterLines.count }
        for entry in entries {
            guard let otherRank = canonicalOrder.firstIndex(of: entry.key) else { continue }
            if otherRank > rank { return entry.start }
        }
        return frontmatterLines.count
    }

    private mutating func ensureFrontmatter() {
        guard openDelimiter == nil else { return }
        openDelimiter = RawLine(content: "---", terminator: terminator)
        closeDelimiter = RawLine(content: "---", terminator: terminator)
        frontmatterLines = []
    }

    // MARK: - Body

    public mutating func setBody(_ lines: [RawLine]) { bodyLines = lines }
}
