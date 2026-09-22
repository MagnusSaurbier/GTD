import Foundation
import GTDModel

/// What a file in the vault is, decided from its path alone (ARCHITECTURE §3).
public enum VaultFileKind: String, Sendable, Equatable, CaseIterable {
    case inbox
    case action
    /// `Projects/…/<X>/<X>.md` — area or project, told apart by the `kind:` frontmatter key.
    case projectNote
    /// `Projects/no_area/no_area.md` — the one note under `Projects/` that is never an area
    /// (R-6): `no_area` is the folder area-less projects live in, not an area of its own.
    /// Reported as a `VaultIssue`, never moved and never rewritten.
    case noAreaNote
    case routine
    case routineLog
    case review
    case config
    /// Any other file inside a project folder — `Project.referenceFiles` (P6).
    case reference
    /// Inside `Knowledge/` — only the folder tree reaches the snapshot (I4).
    case knowledge
    /// `Lists/<list>/<note>.md` (open) or `Lists/<list>/Done/<note>.md` (finished) — §5a.
    case listItem
    /// A markdown note under `Lists/` that is in no list: directly in `Lists/`, or nested deeper
    /// than a list's `Done/`. Ignored and reported as a `VaultIssue` — never guessed at, never
    /// moved (§5a).
    case listMisplaced
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
        if VaultPath.isInside(path, layout.lists) {
            // §5a — a list is a *direct* subfolder of `Lists/`, and `Done/` inside it is the
            // finished log (L3). Anything else under `Lists/` is left alone and reported.
            guard markdown else { return .other }
            return layout.listName(of: NoteID(path: path)) == nil ? .listMisplaced : .listItem
        }
        if VaultPath.isInside(path, layout.projects) {
            // R-6 — `Projects/no_area/` is a folder, not an area, so the note that would be its
            // area note is never read as one. It is reported and left exactly where it is.
            if markdown, isNoAreaNote(path) { return .noAreaNote }
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

    // MARK: Area-less projects (R-6)

    /// `Projects/no_area/no_area.md` — the file `Projects/no_area/` would have if it were an
    /// area. It is not one, so this answers `true` for it and the index reports it (R-6).
    /// Compared case-insensitively, because the file systems this app runs on are.
    func isNoAreaNote(_ path: String) -> Bool {
        let parts = VaultPath.normalize(path).split(separator: "/").map(String.init)
        let expected = VaultPath.normalize(layout.noAreaNotePath.path)
            .split(separator: "/").map(String.init)
        guard parts.count == expected.count else { return false }
        return zip(parts, expected).allSatisfy { $0.lowercased() == $1.lowercased() }
    }

    /// True for a **folder** that is `Projects/no_area` itself (R-6) — never a list of projects'
    /// own folders, and never an area.
    public func isNoAreaFolder(of rawPath: String) -> Bool {
        let parts = VaultPath.normalize(rawPath).split(separator: "/").map(String.init)
        let expected = VaultPath.normalize(layout.noArea).split(separator: "/").map(String.init)
        guard parts.count == expected.count else { return false }
        return zip(parts, expected).allSatisfy { $0.lowercased() == $1.lowercased() }
    }

    /// Why `Projects/no_area/no_area.md` is not an area — the `VaultIssue`'s message (R-6).
    public func noAreaNoteReason() -> String {
        "\"\(VaultLayout.noAreaFolderName)\" is the folder for projects without an area, not an "
            + "area of its own (P1). The app ignores this note and leaves it where it is — "
            + "rename it in Obsidian, or move it into a real area folder."
    }

    /// Why a project inside `Projects/no_area/` must not carry an `area:` key (R-6). The value is
    /// **not** changed and the note is **not** rewritten; the contradiction is only reported.
    public func areaLessProjectHasAreaReason(_ area: NoteID) -> String {
        "This project sits in \(layout.noArea)/, which means it has no area, but its frontmatter "
            + "still says `area: \(area.title)`. The app leaves the note alone — pick an area for "
            + "the project in the app (which moves its folder), or remove the line in Obsidian."
    }

    /// A **folder** path → the list it is, or `nil`. `Lists/Read` is the list `Read`;
    /// `Lists/Read/Done` is the reserved finished-items log (L3), `Lists/Done` is reserved too,
    /// anything deeper is not a list, and the `Lists` folder itself is not one either (L2).
    public func listFolderName(of rawPath: String) -> String? {
        let path = VaultPath.normalize(rawPath)
        let base = VaultPath.normalize(layout.lists)
        guard path.hasPrefix(base + "/") else { return nil }
        let relative = String(path.dropFirst(base.count + 1))
        guard !relative.isEmpty, !relative.contains("/") else { return nil }
        return VaultLayout.isReservedListName(relative) ? nil : relative
    }

    /// Why a markdown note under `Lists/` is in no list — the `VaultIssue`'s message (§5a).
    public func misplacedListReason(of rawPath: String) -> String {
        let path = VaultPath.normalize(rawPath)
        let base = VaultPath.normalize(layout.lists)
        let relative = path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : path
        let depth = relative.split(separator: "/").count
        if depth <= 1 {
            return "A note directly in \(layout.lists)/ is not in any list. Move it into a list "
                + "folder — the app leaves it exactly where it is (§5a)."
        }
        if VaultLayout.isReservedListName(relative.split(separator: "/").first.map(String.init) ?? "") {
            return "\"\(VaultLayout.doneFolderName)\" is reserved for a list's finished items and "
                + "is not a list. Move this note into a real list folder."
        }
        return "Nested too deeply for a list item: a list holds its notes directly, and only "
            + "\(VaultLayout.doneFolderName)/ below it. The app ignores this file (§5a)."
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
    /// A deliberate false positive: `VaultLayout.actionPath(title:collision:)` and
    /// `inboxPath(title:collision:)` (two captures with the same name) use the same " 2" suffix
    /// for a genuine title collision. Reporting one file too many is the safe
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
