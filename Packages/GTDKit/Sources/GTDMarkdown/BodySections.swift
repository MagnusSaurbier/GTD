import Foundation

/// A note body split at its top-level `# Heading` lines.
///
/// Text before the first heading and every heading the model does not know about are kept
/// verbatim, so a note the user has extended in Obsidian survives an app write untouched.
/// Headings inside fenced code blocks are not headings.
public struct BodySections {

    public struct Section {
        /// The heading text without the leading `# `.
        public var title: String
        /// The heading line exactly as written.
        public var headingLine: RawLine
        /// Everything until the next top-level heading, including trailing blank lines.
        public var contentLines: [RawLine]

        /// The content as plain text, without the trailing blank lines that separate sections.
        public var text: String { RawText.text(RawText.trimTrailingBlanks(contentLines).kept) }
    }

    /// Lines before the first `# Heading`.
    public var prefix: [RawLine]
    public var sections: [Section]
    /// Terminator for lines this type creates.
    public var terminator: String

    // MARK: - Parsing

    public init(lines: [RawLine], terminator: String = "\n") {
        self.terminator = terminator
        var prefix: [RawLine] = []
        var sections: [Section] = []
        var fence: String?

        for line in lines {
            if let open = fence {
                if BodySections.fenceMarker(line.content) == open { fence = nil }
                if sections.isEmpty { prefix.append(line) } else { sections[sections.count - 1].contentLines.append(line) }
                continue
            }
            if let marker = BodySections.fenceMarker(line.content) {
                fence = marker
                if sections.isEmpty { prefix.append(line) } else { sections[sections.count - 1].contentLines.append(line) }
                continue
            }
            if let title = BodySections.headingTitle(line.content) {
                sections.append(Section(title: title, headingLine: line, contentLines: []))
            } else if sections.isEmpty {
                prefix.append(line)
            } else {
                sections[sections.count - 1].contentLines.append(line)
            }
        }
        self.prefix = prefix
        self.sections = sections
    }

    /// A level-1 ATX heading (`# Outcome`). Deeper headings belong to their section's content.
    static func headingTitle(_ content: String) -> String? {
        guard content.hasPrefix("# ") else { return nil }
        var title = String(content.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        // Closed ATX headings: `# Why? #`
        while title.hasSuffix("#") { title = String(title.dropLast()).trimmingCharacters(in: .whitespaces) }
        return title
    }

    /// ``` or ~~~ opening/closing a fenced code block (up to three spaces of indent).
    static func fenceMarker(_ content: String) -> String? {
        let trimmed = content.drop { $0 == " " }
        guard content.count - trimmed.count <= 3 else { return nil }
        if trimmed.hasPrefix("```") { return "```" }
        if trimmed.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    // MARK: - Lookup

    /// Case- and punctuation-insensitive: `Why?`, `why`, `WHY ?` are the same heading.
    public static func normalize(_ title: String) -> String {
        var out = ""
        for character in title.lowercased() where character.isLetter || character.isNumber {
            out.append(character)
        }
        return out
    }

    public func index(of title: String) -> Int? {
        let wanted = BodySections.normalize(title)
        return sections.firstIndex { BodySections.normalize($0.title) == wanted }
    }

    /// The section's text, or `nil` when the note has no such heading.
    public func text(of title: String) -> String? {
        index(of: title).map { sections[$0].text }
    }

    // MARK: - Patching

    /// Replaces a section's content, keeping the heading line and the blank lines that separate
    /// it from the next section. Inserts the section (in `canonicalOrder`) when it is missing.
    public mutating func setText(_ title: String, _ newText: String, canonicalOrder: [String] = []) {
        if let index = index(of: title) {
            let (_, blanks) = RawText.trimTrailingBlanks(sections[index].contentLines)
            let lineTerminator = sections[index].headingLine.terminator.isEmpty
                ? terminator : sections[index].headingLine.terminator
            var replacement = RawText.block(newText, terminator: lineTerminator)
            replacement.append(contentsOf: blanks)
            guard replacement != sections[index].contentLines else { return }
            sections[index].contentLines = replacement
        } else {
            guard !newText.isEmpty else { return }
            insert(title: title, content: RawText.block(newText, terminator: terminator),
                   canonicalOrder: canonicalOrder)
        }
    }

    /// Replaces the *lines* of a section (used for checkbox lists and log entries, where the
    /// rendering is line-based). Trailing blank lines of the old content are kept.
    public mutating func setLines(_ title: String, _ newLines: [String], canonicalOrder: [String] = []) {
        if let index = index(of: title) {
            let (_, blanks) = RawText.trimTrailingBlanks(sections[index].contentLines)
            let lineTerminator = sections[index].headingLine.terminator.isEmpty
                ? terminator : sections[index].headingLine.terminator
            var replacement = newLines.map { RawLine(content: $0, terminator: lineTerminator) }
            replacement.append(contentsOf: blanks)
            guard replacement != sections[index].contentLines else { return }
            sections[index].contentLines = replacement
        } else {
            guard !newLines.isEmpty else { return }
            insert(title: title,
                   content: newLines.map { RawLine(content: $0, terminator: terminator) },
                   canonicalOrder: canonicalOrder)
        }
    }

    /// Inserts a new section, keeping one blank line between it and its neighbours and never
    /// adding a trailing blank line at the end of the file.
    private mutating func insert(title: String, content: [RawLine], canonicalOrder: [String]) {
        let at = insertionIndex(for: title, canonicalOrder: canonicalOrder)
        var content = content
        if at < sections.count {
            content.append(RawLine(content: "", terminator: terminator))
        } else if at > 0, !(sections[at - 1].contentLines.last?.isBlank ?? false) {
            sections[at - 1].contentLines.append(RawLine(content: "", terminator: terminator))
        }
        sections.insert(
            Section(title: title,
                    headingLine: RawLine(content: "# \(title)", terminator: terminator),
                    contentLines: content),
            at: at)
    }

    private func insertionIndex(for title: String, canonicalOrder: [String]) -> Int {
        let order = canonicalOrder.map(BodySections.normalize)
        guard let rank = order.firstIndex(of: BodySections.normalize(title)) else { return sections.count }
        for (index, section) in sections.enumerated() {
            guard let otherRank = order.firstIndex(of: BodySections.normalize(section.title)) else { continue }
            if otherRank > rank { return index }
        }
        return sections.count
    }

    // MARK: - Rendering

    public var lines: [RawLine] {
        var out = prefix
        for section in sections {
            out.append(section.headingLine)
            out.append(contentsOf: section.contentLines)
        }
        return out
    }

    public var text: String { RawText.join(lines) }
}
