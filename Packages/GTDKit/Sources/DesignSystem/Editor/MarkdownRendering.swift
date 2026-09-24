/// Obsidian-style live preview for note bodies (STYLEGUIDE §4.4): which characters of the
/// markdown source get which look. `NoteEditor` maps the runs onto its text storage; the
/// read-only `MarkdownText` uses `display(_:)`. Everything that decides the look lives here.
///
/// The source text is never changed by rendering. Markup that Obsidian hides (`**`, `#`, `[[`,
/// `](url)`, …) is marked `hidden` on every line **except the lines the selection touches**,
/// where it shows, muted, so it can be edited. List bullets and checkboxes are always drawn as
/// a dot and a box, as in Obsidian (a task's own `- ` is always hidden). Positions are UTF-16 offsets, the unit of `NSRange`.
public struct MarkdownAttributes: Equatable, Hashable, Sendable {
    public var bold = false
    public var italic = false
    public var code = false
    public var strike = false
    public var highlight = false
    public var link = false
    /// Secondary colour: visible markup on the caret line, a done task, a quote, a code fence.
    public var muted = false
    /// Not drawn and takes no space (markup off the caret line).
    public var hidden = false
    /// The `-`/`*`/`+` of a list item, drawn as a dot in the glyph's place.
    public var bullet = false
    /// The `[ ]` of a checkbox, drawn as a box; `true` when it is ticked.
    public var checkbox: Bool?
    /// 1…6 for a heading's text and markup, 0 otherwise.
    public var heading = 0
    public var codeBlock = false

    public init() {}

    var isPlain: Bool { self == MarkdownAttributes() }
}

public struct MarkdownRun: Equatable, Sendable {
    public var range: Range<Int>
    public var attributes: MarkdownAttributes

    public init(range: Range<Int>, attributes: MarkdownAttributes) {
        self.range = range
        self.attributes = attributes
    }
}

public enum MarkdownRendering {

    /// The styled runs of `text`; plain stretches are left out. `selection` is the editor's
    /// selection while it has focus, `nil` otherwise (then every line is rendered).
    public static func runs(_ text: String, selection: Range<Int>?) -> [MarkdownRun] {
        let units = Array(text.utf16)
        let lines = lineRanges(units)
        var marks = [Mark](repeating: Mark(), count: units.count)
        parse(units, lines: lines, into: &marks)

        let active = selection.map { activeLines($0, in: lines) } ?? []
        var runs: [MarkdownRun] = []
        for (index, line) in lines.enumerated() {
            let reveal = active.contains(index)
            for offset in line {
                var attributes = marks[offset].attributes
                if marks[offset].syntax {
                    if reveal { attributes.muted = true } else { attributes.hidden = true }
                }
                append(&runs, offset, attributes)
            }
        }
        return runs.filter { !$0.attributes.isPlain }
    }

    /// The text as a reader sees it off the caret line — hidden markup removed, a bullet as
    /// `•`, a checkbox as `☐`/`☑` — with its runs. For read-only places (`MarkdownText`).
    public static func display(_ text: String) -> (text: String, runs: [MarkdownRun]) {
        let units = Array(text.utf16)
        let styled = runs(text, selection: nil)
        var attributesAt = [MarkdownAttributes](repeating: MarkdownAttributes(), count: units.count)
        for run in styled { for offset in run.range { attributesAt[offset] = run.attributes } }

        var output: [UInt16] = []
        var runs: [MarkdownRun] = []
        var offset = 0
        while offset < units.count {
            var attributes = attributesAt[offset]
            if attributes.hidden { offset += 1; continue }
            var replacement: [UInt16] = [units[offset]]
            var consumed = 1
            if attributes.bullet {
                replacement = Array("•".utf16)
            } else if let checked = attributes.checkbox {
                replacement = Array((checked ? "☑" : "☐").utf16)
                consumed = 3
            }
            attributes.bullet = false
            attributes.checkbox = nil
            for unit in replacement {
                append(&runs, output.count, attributes)
                output.append(unit)
            }
            offset += consumed
        }
        return (String(decoding: output, as: UTF16.self), runs.filter { !$0.attributes.isPlain })
    }

    /// The range of the checkbox (`[ ]`/`[x]`) at `offset`, if there is one — what a click on a
    /// drawn box hits. The caller toggles it with `ListEditing` on that line.
    public static func checkbox(at offset: Int, in text: String) -> Range<Int>? {
        runs(text, selection: nil).first {
            $0.attributes.checkbox != nil && $0.range.contains(offset)
        }?.range
    }

    // MARK: - Runs

    private static func append(_ runs: inout [MarkdownRun], _ offset: Int, _ attributes: MarkdownAttributes) {
        if let last = runs.last, last.attributes == attributes, last.range.upperBound == offset {
            runs[runs.count - 1].range = last.range.lowerBound..<(offset + 1)
        } else {
            runs.append(MarkdownRun(range: offset..<(offset + 1), attributes: attributes))
        }
    }

    // MARK: - Lines

    /// Line ranges without their `\n`.
    static func lineRanges(_ units: [UInt16]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        for (offset, unit) in units.enumerated() where unit == U.newline {
            ranges.append(start..<offset)
            start = offset + 1
        }
        ranges.append(start..<units.count)
        return ranges
    }

    private static func activeLines(_ selection: Range<Int>, in lines: [Range<Int>]) -> Set<Int> {
        Set(lines.indices.filter { index in
            let line = lines[index]
            return selection.upperBound >= line.lowerBound && selection.lowerBound <= line.upperBound
        })
    }

    // MARK: - Parsing

    private struct Mark {
        var attributes = MarkdownAttributes()
        /// Markup: hidden off the caret line, muted on it.
        var syntax = false
    }

    private static func parse(_ units: [UInt16], lines: [Range<Int>], into marks: inout [Mark]) {
        var inFence = false
        for line in lines {
            var start = line.lowerBound
            while start < line.upperBound, units[start] == U.space || units[start] == U.tab { start += 1 }

            if isFence(units, start, line.upperBound) {
                for offset in line { marks[offset].attributes.codeBlock = true; marks[offset].attributes.muted = true }
                inFence.toggle()
                continue
            }
            if inFence {
                for offset in line { marks[offset].attributes.codeBlock = true }
                continue
            }

            var content = start
            // Heading: 1…6 `#`, then a space.
            var hashes = 0
            while content + hashes < line.upperBound, units[content + hashes] == U.hash { hashes += 1 }
            if (1...6).contains(hashes), content + hashes < line.upperBound, units[content + hashes] == U.space {
                for offset in content..<(content + hashes + 1) { marks[offset].syntax = true }
                for offset in content..<line.upperBound { marks[offset].attributes.heading = hashes }
                content += hashes + 1
            } else if content < line.upperBound, units[content] == U.greater {
                // Quote.
                let end = content + 1 < line.upperBound && units[content + 1] == U.space ? content + 2 : content + 1
                for offset in content..<end { marks[offset].syntax = true }
                for offset in content..<line.upperBound { marks[offset].attributes.muted = true }
                content = end
            } else if content + 1 < line.upperBound,
                      [U.dash, U.star, U.plus].contains(units[content]), units[content + 1] == U.space {
                // Bullet, maybe with a checkbox.
                marks[content].attributes.bullet = true
                content += 2
                if content + 2 < line.upperBound, units[content] == U.open, units[content + 2] == U.close,
                   content + 3 == line.upperBound || units[content + 3] == U.space {
                    let checked = units[content + 1] != U.space
                    // A task shows only its box, as in Obsidian: the bullet and its space go.
                    marks[content - 2].attributes.bullet = false
                    marks[content - 2].attributes.hidden = true
                    marks[content - 1].attributes.hidden = true
                    for offset in content..<(content + 3) { marks[offset].attributes.checkbox = checked }
                    content += min(4, line.upperBound - content)
                    if checked {
                        for offset in content..<line.upperBound {
                            marks[offset].attributes.strike = true
                            marks[offset].attributes.muted = true
                        }
                    }
                }
            }
            inline(units, content..<line.upperBound, into: &marks)
        }
    }

    private static func isFence(_ units: [UInt16], _ start: Int, _ end: Int) -> Bool {
        guard end - start >= 3 else { return false }
        let first = units[start]
        return (first == U.backtick || first == U.tilde)
            && units[start + 1] == first && units[start + 2] == first
    }

    private typealias Emphasis = (delimiter: [UInt16], apply: @Sendable (inout MarkdownAttributes) -> Void)

    private static let emphases: [Emphasis] = [
        (Array("**".utf16), { $0.bold = true }),
        (Array("__".utf16), { $0.bold = true }),
        (Array("~~".utf16), { $0.strike = true }),
        (Array("==".utf16), { $0.highlight = true }),
        (Array("*".utf16), { $0.italic = true }),
        (Array("_".utf16), { $0.italic = true }),
    ]

    private static func inline(_ units: [UInt16], _ range: Range<Int>, into marks: inout [Mark]) {
        var i = range.lowerBound
        let end = range.upperBound
        func markSyntax(_ r: Range<Int>) { for offset in r { marks[offset].syntax = true } }

        scan: while i < end {
            let c = units[i]

            if c == U.backslash, i + 1 < end, isPunctuation(units[i + 1]) {
                markSyntax(i..<(i + 1))
                i += 2
                continue
            }

            if c == U.backtick {
                var run = 0
                while i + run < end, units[i + run] == U.backtick { run += 1 }
                var j = i + run
                while j < end {
                    var closing = 0
                    while j + closing < end, units[j + closing] == U.backtick { closing += 1 }
                    if closing == run {
                        markSyntax(i..<(i + run))
                        markSyntax(j..<(j + run))
                        for offset in (i + run)..<j { marks[offset].attributes.code = true }
                        i = j + run
                        continue scan
                    }
                    j += max(closing, 1)
                }
                i += run
                continue
            }

            if c == U.open, i + 1 < end, units[i + 1] == U.open,
               let close = find([U.close, U.close], in: units, from: i + 2, to: end) {
                // [[target]] or [[target|shown]]
                let inner = (i + 2)..<close
                let pipe = inner.first { units[$0] == U.pipe }
                markSyntax(i..<(pipe.map { $0 + 1 } ?? i + 2))
                for offset in (pipe.map { $0 + 1 } ?? i + 2)..<close { marks[offset].attributes.link = true }
                markSyntax(close..<(close + 2))
                i = close + 2
                continue
            }

            if c == U.open, let close = find([U.close, U.paren], in: units, from: i + 1, to: end),
               let paren = find([U.parenClose], in: units, from: close + 2, to: end) {
                // [text](url)
                markSyntax(i..<(i + 1))
                for offset in (i + 1)..<close { marks[offset].attributes.link = true }
                markSyntax(close..<(paren + 1))
                inline(units, (i + 1)..<close, into: &marks)
                i = paren + 1
                continue
            }

            if (i == range.lowerBound || isSpace(units[i - 1])), startsWithURL(units, i, end) {
                var j = i
                while j < end, !isSpace(units[j]) { j += 1 }
                for offset in i..<j { marks[offset].attributes.link = true }
                i = j
                continue
            }

            for emphasis in emphases {
                let d = emphasis.delimiter
                guard matches(d, in: units, at: i, end: end) else { continue }
                let open = i + d.count
                guard open < end, !isSpace(units[open]) else { continue }
                if d.count == 1, d[0] == U.underscore, i > range.lowerBound, isWordCharacter(units[i - 1]) { continue }
                var j = open + 1
                while j + d.count <= end {
                    if matches(d, in: units, at: j, end: end), !isSpace(units[j - 1]),
                       d.count > 1 || !adjacentSame(units, j, end),
                       d[0] != U.underscore || j + d.count >= end || !isWordCharacter(units[j + d.count]) {
                        markSyntax(i..<open)
                        markSyntax(j..<(j + d.count))
                        for offset in open..<j { emphasis.apply(&marks[offset].attributes) }
                        inline(units, open..<j, into: &marks)
                        i = j + d.count
                        continue scan
                    }
                    j += 1
                }
            }
            i += 1
        }
    }

    // MARK: - Characters

    private enum U {
        static let newline: UInt16 = 10, space: UInt16 = 32, tab: UInt16 = 9
        static let hash: UInt16 = 35, greater: UInt16 = 62, dash: UInt16 = 45, star: UInt16 = 42
        static let plus: UInt16 = 43, open: UInt16 = 91, close: UInt16 = 93, paren: UInt16 = 40
        static let parenClose: UInt16 = 41, backtick: UInt16 = 96, tilde: UInt16 = 126
        static let backslash: UInt16 = 92, pipe: UInt16 = 124, underscore: UInt16 = 95
    }

    private static func matches(_ d: [UInt16], in units: [UInt16], at i: Int, end: Int) -> Bool {
        guard i + d.count <= end else { return false }
        for k in d.indices where units[i + k] != d[k] { return false }
        return true
    }

    /// A single `*`/`_` next to another one is part of `**`/`__`, not a closing italic mark.
    private static func adjacentSame(_ units: [UInt16], _ j: Int, _ end: Int) -> Bool {
        (j + 1 < end && units[j + 1] == units[j]) || (j > 0 && units[j - 1] == units[j])
    }

    private static func find(_ pattern: [UInt16], in units: [UInt16], from: Int, to end: Int) -> Int? {
        guard from < end else { return nil }
        var j = from
        while j + pattern.count <= end {
            if matches(pattern, in: units, at: j, end: end) { return j }
            j += 1
        }
        return nil
    }

    private static func startsWithURL(_ units: [UInt16], _ i: Int, _ end: Int) -> Bool {
        matches(Array("https://".utf16), in: units, at: i, end: end)
            || matches(Array("http://".utf16), in: units, at: i, end: end)
    }

    private static func isSpace(_ u: UInt16) -> Bool { u == U.space || u == U.tab }

    private static func isWordCharacter(_ u: UInt16) -> Bool {
        (48...57).contains(u) || (65...90).contains(u) || (97...122).contains(u) || u > 127
    }

    private static func isPunctuation(_ u: UInt16) -> Bool {
        (33...47).contains(u) || (58...64).contains(u) || (91...96).contains(u) || (123...126).contains(u)
    }
}
