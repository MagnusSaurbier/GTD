/// The Obsidian list shortcuts of every note-body field (STYLEGUIDE §4.5): the pure text
/// rewrite. `NoteEditor` feeds it the field's text and selection and applies the result;
/// everything that decides *what* changes lives here, so it is tested.
///
/// A command works on **whole lines** — every line the selection touches (a selection ending at
/// the very start of a line leaves that line out, as in Obsidian). The indentation is kept; only
/// the list marker after it changes. Positions are UTF-16 offsets, the unit of `NSRange`.
public enum ListEditCommand: String, CaseIterable, Sendable {
    /// Obsidian `editor:toggle-bullet-list` (the user's ⇧⌘L): all lines already list items →
    /// plain text; otherwise the plain and numbered lines become `- ` bullets.
    case toggleBulletList
    /// Obsidian `editor:cycle-list-checklist` (the user's ⌥⌘L): plain → `- ` → `- [ ] ` → plain,
    /// decided by the first non-blank line and applied to all of them.
    case cycleListChecklist
    /// Obsidian's "Toggle checkbox status" (⌥L here): per line, `- [ ]` ↔ `- [x]`; a line that
    /// is no checkbox yet becomes `- [ ] `.
    case toggleCheckbox
    /// `Tab` in a body field (2026-09-25): one more tab of indentation on every line the
    /// selection touches — the field never hands focus on; that is `⌘↩`'s job (`nextInputLine`).
    case indent
    /// `⇧Tab`: one tab (or up to four spaces) of indentation less on every touched line.
    case outdent
}

/// A key combination as the Mac key monitor matches it: one letter plus an exact modifier set.
public struct ListEditShortcut: Equatable, Sendable {
    public var key: Character
    public var command: Bool
    public var option: Bool
    public var shift: Bool
    public var control: Bool

    public init(key: Character, command: Bool = false, option: Bool = false,
                shift: Bool = false, control: Bool = false) {
        self.key = key
        self.command = command
        self.option = option
        self.shift = shift
        self.control = control
    }

    /// The fixed key table, taken from the user's Obsidian `hotkeys.json` (⇧⌘L, ⌥⌘L) and their
    /// ⌥L for the checkbox toggle. Not rebindable in Settings › Keyboard.
    public static let table: [(ListEditShortcut, ListEditCommand)] = [
        (ListEditShortcut(key: "l", command: true, shift: true), .toggleBulletList),
        (ListEditShortcut(key: "l", command: true, option: true), .cycleListChecklist),
        (ListEditShortcut(key: "l", option: true), .toggleCheckbox),
    ]

    public static func command(for shortcut: ListEditShortcut) -> ListEditCommand? {
        table.first { $0.0 == shortcut }?.1
    }
}

/// One edit to apply: replace `range` with `replacement`, then select `selection`.
public struct ListEdit: Equatable, Sendable {
    public var range: Range<Int>
    public var replacement: String
    public var selection: Range<Int>
}

public enum ListEditing {

    /// The edit `command` makes to `text` with `selection` (UTF-16 offsets), or `nil` when
    /// nothing would change.
    public static func edit(
        _ command: ListEditCommand, text: String, selection: Range<Int>
    ) -> ListEdit? {
        let lines = split(text)
        let first = lineIndex(containing: selection.lowerBound, in: lines)
        var last = lineIndex(containing: selection.upperBound, in: lines)
        if last > first, selection.upperBound == lines[last].start { last -= 1 }

        let parsed = lines[first...last].map { Line(parsing: $0.text) }
        let rewritten = rewrite(parsed, command: command)
        guard rewritten != parsed else { return nil }

        // Map both ends of the selection through the per-line prefix changes. A caret at or in
        // the marker lands after the new one (so typing continues the item); the start of a real
        // selection that sits before the marker stays there, keeping whole lines selected.
        func map(_ offset: Int, keepsLineStart: Bool) -> Int {
            var shift = 0
            for index in first...last {
                let old = parsed[index - first], new = rewritten[index - first]
                let lineStart = lines[index].start
                if offset <= lines[index].end, offset >= lineStart {
                    let column = offset - lineStart
                    let head = old.indent.utf16.count, newHead = new.indent.utf16.count
                    let oldPrefix = head + old.marker.utf16.count
                    let newPrefix = newHead + new.marker.utf16.count
                    let mapped: Int
                    if column < head || (column == head && keepsLineStart) { mapped = min(column, newHead) }
                    else if column < oldPrefix || column == head { mapped = newPrefix }
                    else { mapped = column + newPrefix - oldPrefix }
                    return lineStart + shift + mapped
                }
                shift += new.text.utf16.count - old.text.utf16.count
            }
            return offset + shift
        }

        let range = lines[first].start..<lines[last].end
        let replacement = rewritten.map(\.text).joined(separator: "\n")
        let lower = map(selection.lowerBound, keepsLineStart: !selection.isEmpty)
        let upper = selection.isEmpty ? lower : max(lower, map(selection.upperBound, keepsLineStart: false))
        return ListEdit(range: range, replacement: replacement, selection: lower..<upper)
    }

    /// Return inside a list item, as in Obsidian: the new line gets the same marker (`- `,
    /// `- [ ] ` unticked, the next number); Return on an item with no text removes its marker
    /// instead. `nil` outside a list — the editor then inserts a plain newline.
    public static func newline(text: String, selection: Range<Int>) -> ListEdit? {
        let lines = split(text)
        let index = lineIndex(containing: selection.lowerBound, in: lines)
        let span = lines[index]
        guard selection.upperBound <= span.end else { return nil }
        let line = Line(parsing: span.text)
        guard line.kind != .plain else { return nil }
        let markerEnd = span.start + line.indent.utf16.count + line.marker.utf16.count
        guard selection.lowerBound >= markerEnd else { return nil }

        if line.content.allSatisfy({ $0 == " " || $0 == "\t" }) {
            return ListEdit(range: span.start..<span.end, replacement: "", selection: span.start..<span.start)
        }
        let next: String
        switch line.kind {
        case .plain: return nil
        case .bullet: next = line.marker
        case .task: next = String(line.marker.prefix(1)) + " [ ] "
        case .numbered:
            let digits = line.marker.prefix { $0.isNumber }
            let number = (Int(digits) ?? 0) + 1
            next = "\(number)" + line.marker.dropFirst(digits.count)
        }
        let insert = "\n" + line.indent + next
        let caret = selection.lowerBound + insert.utf16.count
        return ListEdit(range: selection, replacement: insert, selection: caret..<caret)
    }

    // MARK: - Rewriting

    private static func rewrite(_ lines: [Line], command: ListEditCommand) -> [Line] {
        // A blank line is left alone unless it is the only line (then the marker goes in).
        let applies: (Line) -> Bool = { lines.count == 1 || !$0.isBlank }
        switch command {
        case .toggleBulletList:
            let targets = lines.filter(applies)
            let allListed = !targets.isEmpty && targets.allSatisfy { $0.kind.isListItem }
            return lines.map { line in
                guard applies(line) else { return line }
                if allListed { return line.with(.plain) }
                return line.kind.isListItem ? line : line.with(.bullet)
            }
        case .cycleListChecklist:
            guard let lead = lines.first(where: applies) else { return lines }
            let target: Line.Kind
            switch lead.kind {
            case .plain, .numbered: target = .bullet
            case .bullet: target = .task(checked: false)
            case .task: target = .plain
            }
            return lines.map { applies($0) ? $0.with(target) : $0 }
        case .toggleCheckbox:
            return lines.map { line in
                guard applies(line) else { return line }
                if case .task(let checked) = line.kind { return line.with(.task(checked: !checked)) }
                return line.with(.task(checked: false))
            }
        case .indent:
            // Every touched line, blank ones included: Tab on an empty line indents it too.
            return lines.map { $0.indented(by: "\t") }
        case .outdent:
            return lines.map { $0.outdented() }
        }
    }

    // MARK: - Navigation

    /// `⌘↩` — where the next **input line** is: past the block of non-empty lines that follows
    /// the caret's line, the first empty line (blank, or only a list marker such as `- [ ] `).
    /// Returns the caret offset at the end of that line, or `nil` when there is none — the
    /// editor then hands focus to the next field. Empty lines directly below the caret are
    /// skipped first, so from one input line the jump lands on the *next* heading's input line.
    public static func nextInputLine(text: String, caret: Int) -> Int? {
        let lines = split(text)
        var index = lineIndex(containing: caret, in: lines) + 1
        func isInput(_ span: Span) -> Bool {
            Line(parsing: span.text).content.allSatisfy { $0 == " " || $0 == "\t" }
        }
        while index < lines.count, isInput(lines[index]) { index += 1 }
        while index < lines.count, !isInput(lines[index]) { index += 1 }
        guard index < lines.count else { return nil }
        return lines[index].end
    }

    // MARK: - Lines

    private struct Span {
        var text: String
        var start: Int
        var end: Int
    }

    private static func split(_ text: String) -> [Span] {
        var spans: [Span] = []
        var start = 0
        // Split on UTF-16 newlines: `"\r\n"` is one `Character`, so a `Character` split would
        // miss CRLF line ends (the `\r` then stays at the end of the line's content).
        for piece in text.utf16.split(separator: 10, omittingEmptySubsequences: false) {
            let length = piece.count
            spans.append(Span(text: String(decoding: piece, as: UTF16.self), start: start, end: start + length))
            start += length + 1
        }
        return spans
    }

    private static func lineIndex(containing offset: Int, in lines: [Span]) -> Int {
        lines.lastIndex { $0.start <= offset } ?? 0
    }
}

/// One line split into indentation, list marker (with its trailing space) and content.
private struct Line: Equatable {
    enum Kind: Equatable {
        case plain
        case bullet
        case task(checked: Bool)
        case numbered

        var isListItem: Bool {
            switch self {
            case .bullet, .task: true
            case .plain, .numbered: false
            }
        }
    }

    var indent: String
    var marker: String
    var content: String
    var kind: Kind

    var text: String { indent + marker + content }
    var isBlank: Bool { text.allSatisfy { $0 == " " || $0 == "\t" } }

    init(indent: String, marker: String, content: String, kind: Kind) {
        self.indent = indent
        self.marker = marker
        self.content = content
        self.kind = kind
    }

    init(parsing text: String) {
        let indent = String(text.prefix { $0 == " " || $0 == "\t" })
        var rest = Substring(text.dropFirst(indent.count))
        self.indent = indent
        self.kind = .plain
        self.marker = ""

        if let bullet = rest.first, "-*+".contains(bullet), rest.dropFirst().first == " " {
            var marker = String(rest.prefix(2))
            rest = rest.dropFirst(2)
            kind = .bullet
            // `[ ]`, `[x]`, `[/]`, … — any one character in the brackets; only a space is open.
            let box = Array(rest.prefix(4))
            if box.count >= 3, box[0] == "[", box[2] == "]", box.count == 3 || box[3] == " " {
                kind = .task(checked: box[1] != " ")
                marker += String(box)
                rest = rest.dropFirst(box.count)
            }
            self.marker = marker
        } else {
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            let after = rest.dropFirst(digits.count)
            if !digits.isEmpty, let dot = after.first, dot == "." || dot == ")",
               after.dropFirst().first == " " {
                marker = String(rest.prefix(digits.count + 2))
                rest = rest.dropFirst(digits.count + 2)
                kind = .numbered
            }
        }
        self.content = String(rest)
    }

    func indented(by unit: String) -> Line {
        Line(indent: unit + indent, marker: marker, content: content, kind: kind)
    }

    /// One tab, or up to four spaces, less. A line with no indentation is returned unchanged.
    func outdented() -> Line {
        var rest = Substring(indent)
        if rest.first == "\t" {
            rest = rest.dropFirst()
        } else {
            var removed = 0
            while removed < 4, rest.first == " " { rest = rest.dropFirst(); removed += 1 }
        }
        return Line(indent: String(rest), marker: marker, content: content, kind: kind)
    }

    func with(_ kind: Kind) -> Line {
        let marker: String
        switch kind {
        case .plain: marker = ""
        case .bullet: marker = "- "
        case .task(let checked):
            // Keep the author's bullet character when a bullet gains a box.
            let bullet = self.kind == .plain || self.kind == .numbered
                ? "-" : String(self.marker.prefix(1))
            marker = bullet + (checked ? " [x] " : " [ ] ")
        case .numbered: marker = self.marker
        }
        return Line(indent: indent, marker: marker, content: content, kind: kind)
    }
}
