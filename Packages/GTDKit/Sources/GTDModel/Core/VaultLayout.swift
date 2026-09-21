import Foundation

/// Where things live inside the vault (ARCHITECTURE §3). Every path is vault-relative and
/// "/"-separated. Defaults are the folders the user's Obsidian vault already uses; they are
/// overridable through `GTDConfig`.
public struct VaultLayout: Sendable, Equatable, Codable {
    public var inbox: String
    public var actions: String
    public var archive: String
    public var projects: String
    public var knowledge: String
    /// Root of the lists (L2). Every **direct** subfolder of it is one list.
    public var lists: String
    public var routines: String
    public var routineLog: String
    public var reviews: String
    public var trash: String
    public var configFile: String

    public init(
        inbox: String = "Inbox",
        actions: String = "Actions",
        archive: String = "Archive",
        projects: String = "Projects",
        knowledge: String = "Knowledge",
        lists: String = "Lists",
        routines: String = "GTD/Routines",
        routineLog: String = "GTD/RoutineLog",
        reviews: String = "GTD/Reviews",
        trash: String = "GTD/Trash",
        configFile: String = "GTD/Config.md"
    ) {
        self.inbox = inbox
        self.actions = actions
        self.archive = archive
        self.projects = projects
        self.knowledge = knowledge
        self.lists = lists
        self.routines = routines
        self.routineLog = routineLog
        self.reviews = reviews
        self.trash = trash
        self.configFile = configFile
    }

    public static let `default` = VaultLayout()

    /// Folders that must exist before the app writes (T16 housekeeping).
    public var requiredFolders: [String] {
        [inbox, actions, projects, knowledge, lists, routines, routineLog, reviews, trash]
    }

    // MARK: Path builders

    /// `Inbox/<yyyy-MM-dd HHmmss>[-n].md` (C3).
    public func inboxPath(stamp: String, collision: Int = 0) -> NoteID {
        let suffix = collision > 0 ? "-\(collision)" : ""
        return NoteID(path: "\(inbox)/\(stamp)\(suffix).md")
    }

    /// `Actions/<Title>.md` (A1).
    public func actionPath(title: String, collision: Int = 0) -> NoteID {
        let suffix = collision > 0 ? " \(collision)" : ""
        return NoteID(path: "\(actions)/\(VaultLayout.sanitize(title))\(suffix).md")
    }

    /// `Projects/<Area>/<Area>.md` (P1).
    public func areaPath(title: String) -> NoteID {
        let name = VaultLayout.sanitize(title)
        return NoteID(path: "\(projects)/\(name)/\(name).md")
    }

    /// `Projects/<Area>/<Project>/<Project>.md`, or `Projects/no_area/<Project>/<Project>.md`
    /// for a project that has no area (P1, D40, R-6).
    public func projectPath(title: String, inArea area: NoteID?) -> NoteID {
        let name = VaultLayout.sanitize(title)
        let base = area?.folder ?? noArea
        return NoteID(path: "\(base)/\(name)/\(name).md")
    }

    // MARK: Area-less projects (R-6)

    /// The folder area-less projects live in — a **folder, not an area** (P1, D40, R-6).
    ///
    /// There is no `no_area/no_area.md`: the classifier never yields an `Area` for it, a project
    /// inside it has `area == nil`, and no area may be called this. Projects that a pre-rework
    /// vault kept directly under `Projects/` keep working and are never moved automatically —
    /// `docs/MANUAL_TEST.md` §9 asks the user to move them.
    public static let noAreaFolderName = "no_area"

    /// `Projects/no_area` — where `projectPath` puts a project with no area (R-6).
    public var noArea: String { "\(projects)/\(VaultLayout.noAreaFolderName)" }

    /// `Projects/no_area/no_area.md` — the file that must never be read as an area (R-6).
    /// It is reported as a `VaultIssue` and left exactly where it is.
    public var noAreaNotePath: NoteID {
        NoteID(path: "\(noArea)/\(VaultLayout.noAreaFolderName).md")
    }

    /// True when `name` is the reserved area-less folder, compared the way a macOS/iOS file
    /// system compares names — case-insensitively (R-6).
    public static func isNoAreaFolderName(_ name: String) -> Bool {
        sanitize(name).lowercased() == noAreaFolderName.lowercased()
    }

    /// True for a project note directly inside `Projects/no_area/<Project>/` (R-6). Such a
    /// project has no area; the folder says so, and no frontmatter key is needed.
    public func isAreaLessProjectPath(_ id: NoteID) -> Bool {
        let parts = id.components
        let root = noArea.split(separator: "/").map(String.init)
        guard parts.count == root.count + 2 else { return false }
        return zip(parts.prefix(root.count), root)
            .allSatisfy { $0.lowercased() == $1.lowercased() }
    }

    /// `Archive/YYYY/MM/<file>` (A5).
    public func archivePath(for id: NoteID, completedOn day: Day) -> NoteID {
        let month = day.month < 10 ? "0\(day.month)" : "\(day.month)"
        let file = id.components.last ?? id.path
        return NoteID(path: "\(archive)/\(day.year)/\(month)/\(file)")
    }

    /// `GTD/RoutineLog/<yyyy-MM-dd>--<deviceID>.md` (R5, N3).
    public func routineLogPath(day: Day, device: String) -> NoteID {
        NoteID(path: "\(routineLog)/\(day.iso)--\(VaultLayout.sanitize(device)).md")
    }

    /// `GTD/Reviews/<yyyy>/KW <ww>.md` (§10.4).
    public func reviewPath(year: Int, week: Int) -> NoteID {
        let ww = week < 10 ? "0\(week)" : "\(week)"
        return NoteID(path: "\(reviews)/\(year)/KW \(ww).md")
    }

    /// `GTD/Trash/<file>` — the app never hard-deletes (ARCHITECTURE §3).
    public func trashPath(for id: NoteID) -> NoteID {
        NoteID(path: "\(trash)/\(id.components.last ?? id.path)")
    }

    // MARK: Lists (§5a)

    /// `Lists/<name>` — the folder that *is* the list (L2).
    public func listFolder(_ name: String) -> String {
        "\(lists)/\(VaultLayout.sanitize(name))"
    }

    /// `Lists/<name>/Done` — the finished-items log (L3). Reserved: it is never a list itself.
    public func listDoneFolder(_ name: String) -> String {
        "\(listFolder(name))/\(VaultLayout.doneFolderName)"
    }

    /// `Lists/<name>/<Title>.md` (L2) or, when `finished`, `Lists/<name>/Done/<Title>.md` (L3).
    public func listItemPath(list: String, title: String, finished: Bool = false) -> NoteID {
        let base = finished ? listDoneFolder(list) : listFolder(list)
        return NoteID(path: "\(base)/\(VaultLayout.sanitize(title)).md")
    }

    /// The name of the folder inside a list that holds its finished items (L3, D38).
    /// Reserved: `createList`/`renameList` refuse it, and the classifier never reads it as a list.
    public static let doneFolderName = "Done"

    /// True when `name` is the reserved `Done` folder (compared the way a macOS file system
    /// compares names — case-insensitively).
    public static func isReservedListName(_ name: String) -> Bool {
        sanitize(name).lowercased() == doneFolderName.lowercased()
    }

    /// Which list a note belongs to, from its path alone: `Lists/Read/X.md` and
    /// `Lists/Read/Done/X.md` both answer `Read`. `nil` for anything that is not a list item —
    /// a note directly in `Lists/`, one nested deeper than `Done/`, or a note outside `Lists/`.
    public func listName(of id: NoteID) -> String? {
        let parts = id.components
        let root = lists.split(separator: "/").map(String.init)
        guard parts.count >= root.count + 2, Array(parts.prefix(root.count)) == root else { return nil }
        let name = parts[root.count]
        guard !VaultLayout.isReservedListName(name) else { return nil }
        let depth = parts.count - root.count
        if depth == 2 { return name }                                   // Lists/<n>/<file>
        if depth == 3, parts[root.count + 1] == VaultLayout.doneFolderName { return name }
        return nil
    }

    /// True for a note in `Lists/<n>/Done/` — the finished-items log (L3).
    public func isFinishedListItem(_ id: NoteID) -> Bool {
        let parts = id.components
        let root = lists.split(separator: "/").map(String.init)
        guard parts.count == root.count + 3, Array(parts.prefix(root.count)) == root else { return false }
        return parts[root.count + 1] == VaultLayout.doneFolderName
    }

    /// `Knowledge/<folder>/<Title>.md` (I4).
    public func knowledgePath(folder: String, title: String) -> NoteID {
        let base = folder.isEmpty ? knowledge : "\(knowledge)/\(folder)"
        return NoteID(path: "\(base)/\(VaultLayout.sanitize(title)).md")
    }

    /// Replaces characters that are illegal in file names on iOS/macOS and in wikilinks.
    /// Keeps umlauts and spaces — the vault already contains them.
    public static func sanitize(_ title: String) -> String {
        let illegal = Set("/\\:*?\"<>|[]#^\n\r\t")
        let cleaned = String(title.map { illegal.contains($0) ? " " : $0 })
        let collapsed = cleaned.split(separator: " ").joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(120))
    }
}
