import Foundation

/// R-4 — what a capture is called and what its body keeps.
///
/// A capture is **named after its text when it is written** (C3, 2026-09-22): the file is
/// `Inbox/<title>.md`, and the title is the first line with something on it, sanitised
/// (`VaultLayout.sanitize`) and cut at a word boundary to ≤ 60 **characters** — characters, not
/// bytes, so a dictation full of umlauts is cut where it reads, not where UTF-8 happens to end.
/// From then on the file name *is* the title, in the inbox and after filing alike; nothing ever
/// derives a title from the body again.
///
/// Nothing the user dictated is ever dropped: whenever the trimmed capture text and the title
/// are not the same string — because it was cut, because it had more lines, or because
/// sanitising changed it — the **full text** is the capture's body (`body(capture:title:notes:)`),
/// and filing carries that body above `# Why?` (actions) or above the notes (Knowledge and list
/// items).
///
/// A note made in Obsidian from the user's template carries a body that is nothing but the
/// empty `# Why?` / `# What?` skeleton. That body says nothing, so filing treats it as empty
/// (`isEmptyBody`) instead of copying the skeleton into the filed note.
public enum CaptureText {

    /// The most a file name may carry of the capture (R-4, I2 "~60 chars").
    public static let titleLimit = 60

    /// The note title for `text`, or `nil` when the capture is only whitespace — a note without
    /// a name is refused rather than filed as "Untitled" (§1 "no lying defaults").
    public static func title(of text: String) -> String? {
        guard let line = firstContentLine(text) else { return nil }
        // Only symbols the sanitiser strips (`###`, `[[]]`) leave no name — `sanitize` would
        // answer "Untitled", which is exactly the lying default this refuses.
        guard line.contains(where: { !$0.isWhitespace && !VaultLayout.illegalNameCharacters.contains($0) })
        else { return nil }
        let sanitised = VaultLayout.sanitize(line)
        return cut(sanitised, to: titleLimit)
    }

    /// The name a title field renames a note to: its lines joined with spaces (a title has
    /// one line, and nothing typed is dropped), then cut and sanitised like a capture's title.
    /// `nil` when only whitespace is left.
    public static func renamedTitle(_ input: String) -> String? {
        let oneLine = input.split(whereSeparator: \.isNewline).joined(separator: " ")
        return title(of: oneLine)
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

    // MARK: - Capture

    /// The name and body a capture of `text` is written with, or `nil` when `text` is only
    /// whitespace — an empty capture is refused, never saved under a made-up name (§1 "no lying
    /// defaults").
    public static func note(for text: String) -> (title: String, body: String)? {
        guard let title = title(of: text) else { return nil }
        return (title, body(capture: text, title: title, notes: ""))
    }

    // MARK: - Filing

    /// What a filed note's body carries over from the inbox item: the item's body — unless it
    /// says nothing (`isEmptyBody`) — then the notes panel (I4b). No stray blank lines at the ends.
    public static func filedBody(body: String, notes: String) -> String {
        let lead = content(ofBody: body)
        let rest = trimmed(notes)
        if lead.isEmpty { return rest }
        if rest.isEmpty { return lead }
        return lead + "\n\n" + rest
    }

    /// The body trimmed, or `""` when it says nothing (`isEmptyBody`).
    public static func content(ofBody body: String) -> String {
        isEmptyBody(body) ? "" : trimmed(body)
    }

    /// True when `body` holds nothing the user wrote: only whitespace, or only the Obsidian
    /// template skeleton — the headings `# Why?` / `# What?` (any heading level, any case) with
    /// nothing under them but empty bullets (`-`, `*`, `+`), empty checkboxes (`- [ ]`) and blank
    /// lines. One word anywhere, a filled bullet or any other heading makes it content.
    public static func isEmptyBody(_ body: String) -> Bool {
        body.split(whereSeparator: \.isNewline).allSatisfy { line in
            isSkeletonLine(line.trimmingCharacters(in: .whitespaces))
        }
    }

    private static func isSkeletonLine(_ line: String) -> Bool {
        if line.isEmpty { return true }
        if line.hasPrefix("#") {
            let heading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).lowercased()
            return line.prefix { $0 == "#" }.count <= 6 && (heading == "why?" || heading == "what?")
        }
        guard let marker = line.first, "-*+".contains(marker) else { return false }
        let rest = line.dropFirst().trimmingCharacters(in: .whitespaces)
        return rest.isEmpty || rest == "[ ]" || rest == "[]"
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
