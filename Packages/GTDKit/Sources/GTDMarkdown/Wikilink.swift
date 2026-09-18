import Foundation
import GTDModel

/// `[[path/to/Note|alias]]` ⇄ `NoteID`.
///
/// Obsidian links are written without the `.md` extension and may be bare titles
/// (`[[DAAD]]`) rather than full paths. Resolving a bare title against the vault is the
/// *index's* job (T15) — the codec only reports what the link says.
public struct Wikilink: Sendable, Equatable {
    /// The link target exactly as written, without `[[`, `]]`, the alias and any `#heading`.
    public var target: String
    public var alias: String?
    public var heading: String?
    /// The target had no `/`, so it is a title rather than a path and needs resolving.
    public var isBare: Bool { !target.contains("/") }

    public init(target: String, alias: String? = nil, heading: String? = nil) {
        self.target = target
        self.alias = alias
        self.heading = heading
    }

    /// The link as a `NoteID`, adding the `.md` extension Obsidian omits.
    public var noteID: NoteID {
        NoteID(path: target.hasSuffix(".md") ? target : target + ".md")
    }

    /// Parses the first `[[…]]` in `text`. Surrounding text (`- [ ] step → [[X]]`) is ignored.
    public static func parse(_ text: String) -> Wikilink? {
        guard let open = text.range(of: "[["),
              let close = text.range(of: "]]", range: open.upperBound..<text.endIndex)
        else { return nil }
        var inner = String(text[open.upperBound..<close.lowerBound])
        var alias: String?
        if let pipe = inner.firstIndex(of: "|") {
            alias = String(inner[inner.index(after: pipe)...]).trimmingCharacters(in: .whitespaces)
            inner = String(inner[..<pipe])
        }
        var heading: String?
        if let hash = inner.firstIndex(of: "#") {
            heading = String(inner[inner.index(after: hash)...]).trimmingCharacters(in: .whitespaces)
            inner = String(inner[..<hash])
        }
        let target = inner.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        return Wikilink(target: target, alias: alias, heading: heading)
    }

    /// `[[Projects/Applications/DAAD/DAAD]]` — the vault's own spelling: no `.md`.
    public static func render(_ id: NoteID, alias: String? = nil) -> String {
        var target = id.path
        if target.hasSuffix(".md") { target.removeLast(3) }
        if let alias, !alias.isEmpty { return "[[\(target)|\(alias)]]" }
        return "[[\(target)]]"
    }

    /// The frontmatter form: a quoted wikilink, as the vault writes it
    /// (`project: "[[Projects/…]]"`). Quoting is required — `[` starts a flow sequence.
    public static func frontmatterValue(_ id: NoteID) -> String {
        YAMLScalar.quoted(render(id))
    }
}
