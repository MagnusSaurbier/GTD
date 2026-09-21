import Foundation
import GTDModel

/// One `- [ ] …` line, with everything needed to put it back the way it was.
///
/// Shared by actions (`# What?`), project steps (`# Steps`, with the `→ [[Action]]` promotion
/// suffix) and routine templates (nesting = sub-steps).
public struct CheckboxItem: Sendable, Equatable {
    /// Leading whitespace exactly as written.
    public var indent: String
    /// `-`, `*` or `+`.
    public var marker: String
    public var done: Bool
    /// The text after `] `, with a `→ [[Action]]` promotion suffix removed.
    public var text: String
    /// The action a project step was promoted to, when the line carries the suffix.
    public var promotedTo: NoteID?
    /// Nesting level: 0 for a top-level item.
    public var depth: Int
    /// Index of the source line inside the block that was parsed.
    public var lineIndex: Int

    public init(
        indent: String = "",
        marker: String = "-",
        done: Bool = false,
        text: String,
        promotedTo: NoteID? = nil,
        depth: Int = 0,
        lineIndex: Int = 0
    ) {
        self.indent = indent
        self.marker = marker
        self.done = done
        self.text = text
        self.promotedTo = promotedTo
        self.depth = depth
        self.lineIndex = lineIndex
    }

    public var checkbox: Checkbox { Checkbox(text: text, done: done) }
}

/// Parsing and rendering markdown task lists.
public enum CheckboxList {

    /// Parses every checkbox line of `lines`, computing nesting depth from the visual indent
    /// (a tab counts as four columns, as Obsidian renders it).
    public static func parse(_ lines: [RawLine]) -> [CheckboxItem] {
        var items: [CheckboxItem] = []
        var widths: [Int] = []          // indent width per depth level
        for (index, line) in lines.enumerated() {
            guard var item = parseLine(line.content) else { continue }
            let width = line.indentWidth
            while let last = widths.last, width < last { widths.removeLast() }
            if let last = widths.last {
                if width > last { widths.append(width) }
            } else {
                widths.append(width)
            }
            item.depth = max(0, widths.count - 1)
            item.lineIndex = index
            items.append(item)
        }
        return items
    }

    /// Parses one line. Returns `nil` when it is not a checkbox.
    ///
    /// The accepted shapes are exactly those of `GTDModel.Checkbox.scan`, which `Action.checkboxes`
    /// and the reducer's `toggleCheckbox` use to *index* checkboxes. The two must agree, or the
    /// reducer toggles a different line than the UI shows (`PrimitiveTests`).
    public static func parseLine(_ content: String) -> CheckboxItem? {
        var rest = Substring(content)
        let indent = String(rest.prefix { $0 == " " || $0 == "\t" })
        rest = rest.dropFirst(indent.count)
        guard let bullet = rest.first, bullet == "-" || bullet == "*" else { return nil }
        rest = rest.dropFirst()
        guard rest.first == " " else { return nil }
        rest = rest.drop { $0 == " " }
        guard rest.first == "[" else { return nil }
        rest = rest.dropFirst()
        guard let mark = rest.first else { return nil }
        rest = rest.dropFirst()
        guard rest.first == "]" else { return nil }
        rest = rest.dropFirst()
        // Obsidian supports `[x]`, `[X]` and `[ ]`; other single characters are custom states
        // that the app must not silently normalise, so they are not checkboxes here.
        guard mark == " " || mark == "x" || mark == "X" else { return nil }

        var text = String(rest).trimmingCharacters(in: .whitespaces)
        var promotedTo: NoteID?
        if let range = CheckboxList.promotionRange(in: text) {
            let suffix = String(text[range.upperBound...])
            promotedTo = Wikilink.parse(suffix)?.noteID
            if promotedTo != nil {
                text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return CheckboxItem(
            indent: indent, marker: String(bullet), done: mark != " ",
            text: text, promotedTo: promotedTo)
    }

    /// The `\u{2192}` (or `->`) that introduces a promotion suffix, if the line has one.
    /// The *last* such arrow wins, so an arrow in the step text itself does not confuse it.
    private static func promotionRange(in text: String) -> Range<String.Index>? {
        for arrow in ["\u{2192}", "->", "\u{27F6}", "\u{2794}"] {
            guard let range = text.range(of: arrow, options: .backwards) else { continue }
            let after = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if after.hasPrefix("[[") { return range }
        }
        return nil
    }

    // MARK: - Rendering

    /// `- [ ] text` / `- [x] text → [[Action]]`, indented four spaces per level.
    public static func render(
        text: String, done: Bool, depth: Int = 0, promotedTo: NoteID? = nil, marker: String = "-"
    ) -> String {
        let indent = String(repeating: "    ", count: max(0, depth))
        let mark = done ? "x" : " "
        let suffix = promotedTo.map { " → \(Wikilink.render($0))" } ?? ""
        return "\(indent)\(marker) [\(mark)] \(text)\(suffix)"
    }

    /// The contiguous run of lines that holds the checkbox list: from the first checkbox line to
    /// the last one. Anything before or after (prose, a stray heading) is left alone by a patch.
    public static func listRange(in lines: [RawLine]) -> Range<Int>? {
        let indices = lines.indices.filter { parseLine(lines[$0].content) != nil }
        guard let first = indices.first, let last = indices.last else { return nil }
        return first..<(last + 1)
    }
}
