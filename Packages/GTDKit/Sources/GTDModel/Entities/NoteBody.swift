import Foundation

/// The `# Heading` sections of a note body, as far as the model needs them.
///
/// `Action.body` is the whole text below the frontmatter (2026-09-24): the detail editor shows
/// and edits it as one markdown document, exactly as Obsidian would. `Action.why`, `.what` and
/// `.preamble` are *views* over that text, so every rule that reads or writes them (R-3's
/// required fields, A2's checkboxes, an inbox filing's lead paragraph) goes through here.
///
/// Deliberately the same grammar as `GTDMarkdown.BodySections`, on `"\n"`-joined text instead
/// of terminated lines: a level-1 ATX heading (`# Title`, optionally closed `# Title #`) starts a
/// section, deeper headings belong to their section, and nothing inside a fenced code block is
/// a heading. Titles compare case- and punctuation-insensitively (`Why?` = `why`). The codec
/// stays the only place that turns file bytes into text and back.
public enum NoteBody {

    /// The two sections every action note carries (A1), in their canonical order.
    public static let actionSections = ["Why?", "What?"]

    struct Section {
        var title: String
        var headingLine: String
        var lines: [String]
    }

    struct Split {
        var prefix: [String]
        var sections: [Section]

        var joined: String {
            var lines = prefix
            for section in sections {
                lines.append(section.headingLine)
                lines.append(contentsOf: section.lines)
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - Reading

    /// The text under `title` without the blank lines that separate it from the next section,
    /// or `nil` when the body has no such heading.
    public static func text(of title: String, in body: String) -> String? {
        let parts = split(body)
        guard let index = index(of: title, in: parts) else { return nil }
        return trimmed(parts.sections[index].lines)
    }

    public static func hasSection(_ title: String, in body: String) -> Bool {
        index(of: title, in: split(body)) != nil
    }

    /// True when the body has at least one of `titles`.
    public static func hasAnySection(of titles: [String], in body: String) -> Bool {
        let parts = split(body)
        return titles.contains { index(of: $0, in: parts) != nil }
    }

    /// The text above the first heading, without trailing blank lines. The whole body when
    /// there is no heading at all.
    public static func prefix(of body: String) -> String {
        trimmed(split(body).prefix)
    }

    /// The whole body without trailing blank lines — what a headingless note says.
    public static func wholeText(_ body: String) -> String {
        trimmed(body.components(separatedBy: "\n"))
    }

    // MARK: - Writing

    /// Replaces the text under `title`, keeping the heading line as written and the blank lines
    /// that separate the section from the next one. A missing section is inserted at its place
    /// in `canonicalOrder` (after every known heading that ranks before it, else at the end) —
    /// unless the new text is empty, in which case nothing is added.
    public static func setText(
        _ title: String, _ newText: String, in body: String, canonicalOrder: [String] = []
    ) -> String {
        var parts = split(body)
        if let index = index(of: title, in: parts) {
            let blanks = trailingBlankCount(parts.sections[index].lines)
            var replacement = block(newText)
            replacement.append(contentsOf: Array(repeating: "", count: blanks))
            parts.sections[index].lines = replacement
        } else {
            guard !newText.isEmpty else { return body }
            insert(title: title, lines: block(newText), into: &parts, canonicalOrder: canonicalOrder)
        }
        return parts.joined
    }

    /// Replaces the text above the first heading. One blank line separates it from the heading
    /// that follows; an empty text removes the lead paragraph altogether.
    public static func setPrefix(_ newText: String, in body: String) -> String {
        var parts = split(body)
        var lead = block(newText)
        if !lead.isEmpty, !parts.sections.isEmpty { lead.append("") }
        parts.prefix = lead
        return parts.joined
    }

    /// The body with every heading of `titles` present, inserted empty in that order where it
    /// is missing. A body that has none of them and is not empty is read as one long `What?`
    /// (as the codec has always read it), so its text moves under the `What?` heading rather
    /// than becoming a lead paragraph the model would then ignore.
    public static func ensuringSections(_ titles: [String], in body: String) -> String {
        var parts = split(body)
        let missing = titles.filter { index(of: $0, in: parts) == nil }
        guard !missing.isEmpty else { return body }
        if missing.count == titles.count, parts.sections.isEmpty, !parts.prefix.isEmpty,
           let last = titles.last {
            let text = trimmed(parts.prefix)
            var out = ""
            for title in titles.dropLast() { out += "# \(title)\n\n" }
            out += "# \(last)"
            if !text.isEmpty { out += "\n" + text }
            return out
        }
        for title in missing {
            insert(title: title, lines: [], into: &parts, canonicalOrder: titles)
        }
        return parts.joined
    }

    /// A fresh body from its pieces: the lead paragraph (if any), a blank line, then each section
    /// as `# Title` followed by its text. Empty sections keep their heading, so the empty
    /// action body is exactly the template's `# Why?\n\n# What?`.
    public static func compose(prefix: String = "", sections: [(title: String, text: String)]) -> String {
        var pieces: [String] = []
        for section in sections {
            let text = trimmed(block(section.text))
            pieces.append(text.isEmpty ? "# \(section.title)" : "# \(section.title)\n\(text)")
        }
        let lead = trimmed(block(prefix))
        let joined = pieces.joined(separator: "\n\n")
        if lead.isEmpty { return joined }
        return joined.isEmpty ? lead : lead + "\n\n" + joined
    }

    // MARK: - Grammar

    static func split(_ body: String) -> Split {
        guard !body.isEmpty else { return Split(prefix: [], sections: []) }
        var prefix: [String] = []
        var sections: [Section] = []
        var fence: String?

        for line in body.components(separatedBy: "\n") {
            if let open = fence {
                if fenceMarker(line) == open { fence = nil }
                append(line, to: &prefix, or: &sections)
                continue
            }
            if let marker = fenceMarker(line) {
                fence = marker
                append(line, to: &prefix, or: &sections)
                continue
            }
            if let title = headingTitle(line) {
                sections.append(Section(title: title, headingLine: line, lines: []))
            } else {
                append(line, to: &prefix, or: &sections)
            }
        }
        return Split(prefix: prefix, sections: sections)
    }

    private static func append(_ line: String, to prefix: inout [String], or sections: inout [Section]) {
        if sections.isEmpty { prefix.append(line) } else { sections[sections.count - 1].lines.append(line) }
    }

    /// A level-1 ATX heading (`# Outcome`). Deeper headings belong to their section's content.
    static func headingTitle(_ line: String) -> String? {
        guard line.hasPrefix("# ") else { return nil }
        var title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        while title.hasSuffix("#") { title = String(title.dropLast()).trimmingCharacters(in: .whitespaces) }
        return title
    }

    /// ``` or ~~~ opening/closing a fenced code block (up to three spaces of indent).
    static func fenceMarker(_ line: String) -> String? {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count <= 3 else { return nil }
        if trimmed.hasPrefix("```") { return "```" }
        if trimmed.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    /// Case- and punctuation-insensitive: `Why?`, `why`, `WHY ?` are the same heading.
    public static func normalize(_ title: String) -> String {
        var out = ""
        for character in title.lowercased() where character.isLetter || character.isNumber {
            out.append(character)
        }
        return out
    }

    private static func index(of title: String, in parts: Split) -> Int? {
        let wanted = normalize(title)
        return parts.sections.firstIndex { normalize($0.title) == wanted }
    }

    private static func insert(title: String, lines: [String], into parts: inout Split, canonicalOrder: [String]) {
        let at = insertionIndex(for: title, in: parts, canonicalOrder: canonicalOrder)
        var content = lines
        if at < parts.sections.count {
            content.append("")
        } else if at > 0 {
            if !(parts.sections[at - 1].lines.last?.isBlankLine ?? false) { parts.sections[at - 1].lines.append("") }
        } else if !parts.prefix.isEmpty, !(parts.prefix.last?.isBlankLine ?? false) {
            parts.prefix.append("")
        }
        parts.sections.insert(Section(title: title, headingLine: "# \(title)", lines: content), at: at)
    }

    private static func insertionIndex(for title: String, in parts: Split, canonicalOrder: [String]) -> Int {
        let order = canonicalOrder.map(normalize)
        guard let rank = order.firstIndex(of: normalize(title)) else { return parts.sections.count }
        for (index, section) in parts.sections.enumerated() {
            guard let otherRank = order.firstIndex(of: normalize(section.title)) else { continue }
            if otherRank > rank { return index }
        }
        return parts.sections.count
    }

    // MARK: - Lines

    /// `text` as lines, without a trailing newline's empty line.
    private static func block(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        while lines.last == "" { lines.removeLast() }
        return lines
    }

    private static func trailingBlankCount(_ lines: [String]) -> Int {
        var count = 0
        for line in lines.reversed() {
            guard line.isBlankLine else { break }
            count += 1
        }
        return count
    }

    /// Joined lines without trailing blank lines.
    private static func trimmed(_ lines: [String]) -> String {
        var kept = lines
        while let last = kept.last, last.isBlankLine { kept.removeLast() }
        return kept.joined(separator: "\n")
    }
}

private extension String {
    var isBlankLine: Bool { allSatisfy { $0 == " " || $0 == "\t" } }
}
