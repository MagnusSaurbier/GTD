import Foundation

/// One physical line of a file: its content and the exact bytes that terminated it.
///
/// Keeping the terminator on the line is what makes CRLF, mixed line endings and a missing
/// final newline survive a round trip: `RawText.join(RawText.split(x)) == x` for every `x`.
public struct RawLine: Sendable, Equatable {
    public var content: String
    /// `"\n"`, `"\r\n"` or `""` (only the last line of a file that does not end in a newline).
    public var terminator: String

    public init(content: String, terminator: String = "\n") {
        self.content = content
        self.terminator = terminator
    }

    /// True for a line that is empty or only whitespace.
    public var isBlank: Bool { content.allSatisfy { $0 == " " || $0 == "\t" } }

    /// The leading run of spaces and tabs.
    public var indent: String { String(content.prefix { $0 == " " || $0 == "\t" }) }

    /// Visual indent width: a tab advances to the next multiple of four.
    public var indentWidth: Int {
        var width = 0
        for character in content {
            if character == " " { width += 1 }
            else if character == "\t" { width += 4 - (width % 4) }
            else { break }
        }
        return width
    }
}

/// Splitting and joining text without losing a byte.
public enum RawText {

    /// A UTF-8 byte-order mark, if the text starts with one. Kept out of line 0 so that
    /// frontmatter detection still works on a BOM-prefixed file.
    public static func stripBOM(_ text: String) -> (bom: String, rest: String) {
        if text.unicodeScalars.first == "\u{FEFF}" {
            return ("\u{FEFF}", String(String.UnicodeScalarView(text.unicodeScalars.dropFirst())))
        }
        return ("", text)
    }

    /// Splits into lines, keeping each line's terminator.
    ///
    /// Works on unicode scalars on purpose: Swift treats `"\r\n"` as a *single* `Character`,
    /// so a `Character`-level scan silently mis-handles CRLF files.
    public static func split(_ text: String) -> [RawLine] {
        var lines: [RawLine] = []
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\n" {
                if scalars.last == "\r" {
                    lines.append(RawLine(content: String(scalars.dropLast()), terminator: "\r\n"))
                } else {
                    lines.append(RawLine(content: String(scalars), terminator: "\n"))
                }
                scalars = String.UnicodeScalarView()
            } else {
                scalars.append(scalar)
            }
        }
        if !scalars.isEmpty {
            lines.append(RawLine(content: String(scalars), terminator: ""))
        }
        return lines
    }

    public static func join(_ lines: [RawLine]) -> String {
        var out = ""
        for line in lines {
            out += line.content
            out += line.terminator
        }
        return out
    }

    /// The terminator new lines should use: the first real one in the file, else `"\n"`.
    public static func dominantTerminator(_ lines: [RawLine]) -> String {
        for line in lines where !line.terminator.isEmpty { return line.terminator }
        return "\n"
    }

    /// Turns plain text into lines terminated with `terminator`.
    ///
    /// The text is treated as a *block*: a trailing newline in `text` does not create a trailing
    /// empty line, and every line gets a terminator.
    public static func block(_ text: String, terminator: String) -> [RawLine] {
        guard !text.isEmpty else { return [] }
        var body = text
        // Normalise whatever the caller handed us, then re-apply the file's own terminator.
        if body.hasSuffix("\r\n") { body.removeLast(2) } else if body.hasSuffix("\n") { body.removeLast() }
        let pieces = body.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
        return pieces.map { piece in
            var content = String(String.UnicodeScalarView(piece))
            if content.hasSuffix("\r") { content.removeLast() }
            return RawLine(content: content, terminator: terminator)
        }
    }

    /// Joined content of `lines` with `"\n"` separators and no trailing newline — what the model
    /// stores in fields like `Action.what`.
    public static func text(_ lines: [RawLine]) -> String {
        var out = lines.map(\.content).joined(separator: "\n")
        while out.hasSuffix("\n") { out.removeLast() }
        return out
    }

    /// Drops trailing blank lines and reports how many were removed.
    public static func trimTrailingBlanks(_ lines: [RawLine]) -> (kept: [RawLine], blanks: [RawLine]) {
        var kept = lines
        var blanks: [RawLine] = []
        while let last = kept.last, last.isBlank {
            blanks.insert(kept.removeLast(), at: 0)
        }
        return (kept, blanks)
    }
}
