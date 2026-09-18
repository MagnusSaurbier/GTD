import Foundation
import GTDModel

/// What a file in the vault is, decided from its path alone (ARCHITECTURE §3).
public enum VaultFileKind: String, Sendable, Equatable, CaseIterable {
    case inbox
    case action
    /// `Projects/…/<X>/<X>.md` — area or project, told apart by the `kind:` frontmatter key.
    case projectNote
    case routine
    case routineLog
    case review
    case config
    /// Any other file inside a project folder — `Project.referenceFiles` (P6).
    case reference
    /// Inside `Knowledge/` — only the folder tree reaches the snapshot (I4).
    case knowledge
    /// Inside `Archive/` — excluded from the snapshot (A5).
    case archive
    /// Inside `GTD/Trash/` — invisible to the app.
    case trash
    /// Anything the app does not model. Left completely alone.
    case other
}

/// Path → kind. Pure and total, so every classification rule is unit-testable on Linux.
public struct VaultClassifier: Sendable {
    public let layout: VaultLayout

    public init(layout: VaultLayout = .default) {
        self.layout = layout
    }

    public func kind(of rawPath: String) -> VaultFileKind {
        let path = VaultPath.normalize(rawPath)
        let markdown = VaultPath.isMarkdown(path)

        if path == VaultPath.normalize(layout.configFile) { return .config }
        if VaultPath.isInside(path, layout.trash) { return .trash }
        if VaultPath.isInside(path, layout.archive) { return .archive }
        if VaultPath.isInside(path, layout.routines) { return markdown ? .routine : .other }
        if VaultPath.isInside(path, layout.routineLog) { return markdown ? .routineLog : .other }
        if VaultPath.isInside(path, layout.reviews) { return markdown ? .review : .other }
        if VaultPath.isInside(path, layout.inbox) { return markdown ? .inbox : .other }
        if VaultPath.isInside(path, layout.actions) { return markdown ? .action : .other }
        if VaultPath.isInside(path, layout.knowledge) { return .knowledge }
        if VaultPath.isInside(path, layout.projects) {
            // `Projects/[<Area>/]<Name>/<Name>.md` is the area or project note; everything else
            // in the folder is a reference file.
            let folderName = VaultPath.name(of: VaultPath.folder(of: path))
            if markdown, !folderName.isEmpty, folderName == VaultPath.stem(of: path) {
                return .projectNote
            }
            return .reference
        }
        return .other
    }

    /// The folder a project or area note owns — where its reference files live.
    public func projectFolder(of notePath: String) -> String {
        VaultPath.folder(of: notePath)
    }

    /// `Knowledge/Studium/Thesis` → `Studium/Thesis`; the `Knowledge` folder itself → `nil`.
    public func knowledgeFolder(of rawPath: String) -> String? {
        let path = VaultPath.normalize(rawPath)
        let base = VaultPath.normalize(layout.knowledge)
        guard path.hasPrefix(base + "/") else { return nil }
        let relative = String(path.dropFirst(base.count + 1))
        return relative.isEmpty ? nil : relative
    }

    /// Paths that look like an iCloud conflict copy: `Foo 2.md` next to an existing `Foo.md`
    /// (N3 §7.5). Never auto-resolved — the app only reports them.
    ///
    /// A deliberate false positive: `VaultLayout.actionPath(title:collision:)` uses the same
    /// " 2" suffix for a genuine title collision. Reporting one file too many is the safe
    /// direction; the user decides.
    public static func conflictCopies(among paths: [String]) -> [String] {
        let all = Set(paths.map(VaultPath.normalize))
        return all.filter { path in
            guard VaultPath.isMarkdown(path) else { return false }
            let stem = VaultPath.stem(of: path)
            guard let space = stem.lastIndex(of: " ") else { return false }
            let suffix = stem[stem.index(after: space)...]
            guard suffix.count <= 3, !suffix.isEmpty, suffix.allSatisfy(\.isNumber),
                  let number = Int(suffix), number >= 2
            else { return false }
            let original = VaultPath.join(
                VaultPath.folder(of: path), String(stem[stem.startIndex..<space]) + ".md")
            return all.contains(original)
        }.sorted()
    }
}

// MARK: - Frontmatter peek

/// A *classification-only* look at YAML frontmatter.
///
/// `GTDMarkdown.NoteCodec` owns parsing; the scanner only needs one scalar (`kind:`) to know
/// whether `Projects/X/X.md` should be decoded as an area or as a project, and reading the whole
/// note through the codec twice to find out would be wasteful. Deliberately dumb: top-level
/// `key: value` lines inside the first `---` block, nothing else.
enum Frontmatter {
    /// The lines between the opening and closing `---`, or `nil` when there is no frontmatter.
    static func block(in text: String) -> [Substring]? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        // A leading BOM or blank line still counts as "starts with ---".
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---"
        else { return nil }
        lines.removeFirst()
        guard let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }
        return Array(lines[lines.startIndex..<end])
    }

    /// The value of a top-level scalar key, unquoted and trimmed.
    static func scalar(_ key: String, in text: String) -> String? {
        guard let block = block(in: text) else { return nil }
        for line in block {
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"), !line.hasPrefix("-") else { continue }
            guard let colon = line.firstIndex(of: ":"), String(line[line.startIndex..<colon]) == key
            else { continue }
            var value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            } else if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
