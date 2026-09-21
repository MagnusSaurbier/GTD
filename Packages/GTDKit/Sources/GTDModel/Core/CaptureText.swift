import Foundation

/// R-4 — what a capture becomes when it is filed: its title, and the body that keeps whatever
/// the title could not hold.
///
/// The capture text **is** the title (I2, D27/D30): the file keeps its timestamp name while it
/// sits in `Inbox/` and is renamed on filing. A title is a file name, so it is sanitised
/// (`VaultLayout.sanitize`) and cut at a word boundary to ≤ 60 **characters** — characters, not
/// bytes, so a dictation full of umlauts is cut where it reads, not where UTF-8 happens to end.
///
/// Nothing the user dictated is ever dropped: whenever the trimmed capture text and the title
/// are not the same string — because it was cut, because it had more lines, or because
/// sanitising changed it — the **full text** is written as the note's first paragraph, above
/// `# Why?` (actions) or above the notes (Knowledge and list items).
public enum CaptureText {

    /// The most a file name may carry of the capture (R-4, I2 "~60 chars").
    public static let titleLimit = 60

    /// The note title for `text`, or `nil` when the capture is only whitespace — a note without
    /// a name is refused rather than filed as "Untitled" (§1 "no lying defaults").
    public static func title(of text: String) -> String? {
        guard let line = firstContentLine(text) else { return nil }
        let sanitised = VaultLayout.sanitize(line)
        guard !sanitised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return cut(sanitised, to: titleLimit)
    }

    /// True when `title` does not carry everything `text` said, so the full text belongs in the
    /// body (R-4).
    public static func carriesMore(_ text: String, than title: String) -> Bool {
        trimmed(text) != title
    }

    /// The body of a filed note: the full capture text first when the title could not hold it,
    /// then the notes panel (I4b). Either half may be empty; the result never has stray blank
    /// lines at its ends.
    public static func body(capture: String, title: String, notes: String) -> String {
        let lead = carriesMore(capture, than: title) ? trimmed(capture) : ""
        let rest = trimmed(notes)
        if lead.isEmpty { return rest }
        if rest.isEmpty { return lead }
        return lead + "\n\n" + rest
    }

    // MARK: - Pieces

    /// The first line with something on it — a dictation often starts with a blank line.
    static func firstContentLine(_ text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let candidate = line.trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty { return candidate }
        }
        return nil
    }

    /// Cuts to at most `limit` characters, at the last word boundary that fits. A single word
    /// longer than the limit is cut hard — a file name has to end somewhere.
    static func cut(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        if let lastSpace = head.lastIndex(of: " ") {
            let word = head[head.index(after: lastSpace)...]
            // Keep the whole-word cut unless it would throw away most of the line.
            let kept = head[..<lastSpace].trimmingCharacters(in: .whitespaces)
            if !kept.isEmpty, !word.isEmpty { return kept }
        }
        return head.trimmingCharacters(in: .whitespaces)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
