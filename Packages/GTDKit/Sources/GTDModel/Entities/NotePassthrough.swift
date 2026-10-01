import Foundation

/// Opaque carrier for everything a note file contains that the model does not describe:
/// unknown frontmatter keys and their order, unknown body sections, the original line ending,
/// pre-heading text. It exists so the round-trip rule (N2) can hold.
///
/// **Only `GTDMarkdown` writes or interprets these slots.** Every other module treats a
/// `NotePassthrough` as a black box it carries from decode to encode. The storage is an ordered
/// string→string map so the codec can choose its own slot names without another contract change.
public struct NotePassthrough: Sendable, Equatable {
    private var order: [String]
    private var values: [String: String]

    public init() {
        order = []
        values = [:]
    }

    public static let empty = NotePassthrough()

    public var isEmpty: Bool { order.isEmpty }

    /// Slot names in insertion order.
    public var keys: [String] { order }

    public subscript(key: String) -> String? {
        get { values[key] }
        set {
            if let newValue {
                if values[key] == nil { order.append(key) }
                values[key] = newValue
            } else if values.removeValue(forKey: key) != nil {
                order.removeAll { $0 == key }
            }
        }
    }
}

/// One `- [ ]` / `- [x]` line in a note body.
public struct Checkbox: Sendable, Equatable, Hashable, Codable {
    public var text: String
    public var done: Bool

    public init(text: String, done: Bool = false) {
        self.text = text
        self.done = done
    }
}

extension Checkbox {
    /// Simple line scan used by `Action.checkboxes`.
    ///
    /// Deliberately shallow: leading whitespace, `-` or `*`, `[ ]`/`[x]`/`[X]`. The full parser
    /// (nesting, `→ [[Action]]` suffixes, tabs) is `GTDMarkdown.CheckboxList` — `GTDModel` has no
    /// codec, so this is the most an entity may do with its own body text.
    public static func scan(_ markdown: String) -> [Checkbox] {
        scanNested(markdown).map(\.checkbox)
    }

    /// `scan` plus each checkbox's nesting depth (0 = top level), computed from the visual
    /// indent the way `GTDMarkdown.CheckboxList.parse` does (a tab counts as four columns).
    /// Same order and count as `scan`, so an index here is a `toggleCheckbox` index.
    public static func scanNested(_ markdown: String) -> [(checkbox: Checkbox, depth: Int)] {
        var result: [(checkbox: Checkbox, depth: Int)] = []
        var widths: [Int] = []          // indent width per depth level
        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let checkbox = parseLine(rawLine) else { continue }
            var width = 0
            for character in rawLine {
                if character == " " { width += 1 }
                else if character == "\t" { width += 4 - (width % 4) }
                else { break }
            }
            while let last = widths.last, width < last { widths.removeLast() }
            if let last = widths.last {
                if width > last { widths.append(width) }
            } else {
                widths.append(width)
            }
            result.append((checkbox, max(0, widths.count - 1)))
        }
        return result
    }

    private static func parseLine(_ rawLine: Substring) -> Checkbox? {
        var line = rawLine
        while let f = line.first, f == " " || f == "\t" { line = line.dropFirst() }
        guard let bullet = line.first, bullet == "-" || bullet == "*" else { return nil }
        line = line.dropFirst()
        guard line.first == " " else { return nil }
        line = line.drop(while: { $0 == " " })
        guard line.first == "[" else { return nil }
        let markIndex = line.index(after: line.startIndex)
        guard markIndex < line.endIndex else { return nil }
        let mark = line[markIndex]
        let closeIndex = line.index(after: markIndex)
        guard closeIndex < line.endIndex, line[closeIndex] == "]" else { return nil }
        guard mark == " " || mark == "x" || mark == "X" else { return nil }
        let rest = line[line.index(after: closeIndex)...]
            .trimmingCharacters(in: .whitespaces)
        return Checkbox(text: rest, done: mark != " ")
    }
}
