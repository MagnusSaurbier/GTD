import Foundation
import GTDModel

/// The projects overview as a folder tree (#67), built from the project notes' paths alone.
/// Plain and Linux-compilable — `ProjectsListView` only draws `lines(collapsed:)`.
///
/// - `top`: projects in `Projects/no_area/…` and projects directly under `Projects/`
///   (`Projects/<Name>/<Name>.md`), shown flat at the top without a header.
/// - `nodes`: every other project sits under the folders between `Projects/` and its own folder,
///   like a file tree (`Growth › Coding › BrainTrain`). A folder is a node whether or not it has
///   an area note, and only folders that hold a project (at any depth) exist — so filtering the
///   rows first hides empty nodes.
///
/// Alphabetical at every level (Finder order: case-insensitive, numbers by value), sub-folders
/// before projects within a node — the VS Code explorer's order.
public struct ProjectTree<Row> {
    public struct Node: Identifiable {
        /// Vault-relative folder path, e.g. `Projects/Growth/Coding` — the key the collapsed
        /// state is remembered under.
        public let id: String
        public let name: String
        public var children: [Node]
        public var projects: [Row]
    }

    /// One visible row of the tree, depth-first. `depth` 0 = top level.
    public enum Line: Identifiable {
        case folder(id: String, name: String, depth: Int, isExpanded: Bool)
        case project(Row, id: NoteID, depth: Int)

        public var id: String {
            switch self {
            case let .folder(id, _, _, _): "folder:" + id
            case let .project(_, id, _): "project:" + id.path
            }
        }
    }

    public var top: [Row]
    public var nodes: [Node]

    public var isEmpty: Bool { top.isEmpty && nodes.isEmpty }

    /// Builds the tree. `id` gives a row's project note (`Projects/…/<Name>/<Name>.md`), `title`
    /// the name it sorts by. `layout` says where `Projects/` and `no_area` are.
    public init(
        rows: [Row],
        layout: VaultLayout,
        id: (Row) -> NoteID,
        title: (Row) -> String
    ) {
        let root = layout.projects.split(separator: "/").map(String.init)
        var top: [Row] = []
        var tree = Builder()
        for row in rows {
            let folders = ProjectTreePath.parentFolders(of: id(row), projectsRoot: root)
            if folders.isEmpty || VaultLayout.isNoAreaFolderName(folders[0]) {
                top.append(row)
            } else {
                tree.insert(row, at: folders[...], prefix: root)
            }
        }
        self.top = top.sorted { ProjectTreePath.precedes(title($0), title($1)) }
        self.nodes = tree.nodes(sortedBy: title)
    }

    /// The rows to draw: `top` first, then every node and — while expanded — its contents.
    /// A node is expanded unless its `id` is in `collapsed`, so a new area shows its projects.
    public func lines(collapsed: Set<String>, id: (Row) -> NoteID) -> [Line] {
        var out = top.map { Line.project($0, id: id($0), depth: 0) }
        func walk(_ nodes: [Node], depth: Int) {
            for node in nodes {
                let open = !collapsed.contains(node.id)
                out.append(.folder(id: node.id, name: node.name, depth: depth, isExpanded: open))
                guard open else { continue }
                walk(node.children, depth: depth + 1)
                out += node.projects.map { .project($0, id: id($0), depth: depth + 1) }
            }
        }
        walk(nodes, depth: 0)
        return out
    }

    // MARK: - Building

    /// Mutable tree of folder name → sub-builder, turned into sorted `Node`s at the end.
    private struct Builder {
        var children: [String: Builder] = [:]
        var projects: [Row] = []
        var path = ""

        mutating func insert(_ row: Row, at folders: ArraySlice<String>, prefix: [String]) {
            guard let first = folders.first else {
                projects.append(row)
                return
            }
            let childPath = (prefix + [first]).joined(separator: "/")
            var child = children[first] ?? Builder(path: childPath)
            child.insert(row, at: folders.dropFirst(), prefix: prefix + [first])
            children[first] = child
        }

        func nodes(sortedBy title: (Row) -> String) -> [Node] {
            children
                .sorted { ProjectTreePath.precedes($0.key, $1.key) }
                .map { name, builder in
                    Node(
                        id: builder.path,
                        name: name,
                        children: builder.nodes(sortedBy: title),
                        projects: builder.projects.sorted { ProjectTreePath.precedes(title($0), title($1)) })
                }
        }
    }
}

/// Path arithmetic and ordering for `ProjectTree`, plus the per-device collapsed state's
/// storage format. Plain functions so they are tested on their own.
public enum ProjectTreePath {
    /// The folders between `Projects/` and the project's own folder:
    /// `Projects/Growth/Coding/BrainTrain/BrainTrain.md` → `["Growth", "Coding"]`,
    /// `Projects/Solo/Solo.md` → `[]`. A note outside `Projects/` also yields `[]`.
    public static func parentFolders(of note: NoteID, projectsRoot root: [String]) -> [String] {
        let parts = note.components
        guard parts.count >= root.count + 2,
              zip(parts, root).allSatisfy({ $0.lowercased() == $1.lowercased() })
        else { return [] }
        // Drop the root in front, the project's own folder and file at the end.
        return Array(parts.dropFirst(root.count).dropLast(2))
    }

    /// Finder order: case-insensitive, digits compared by value ("Step 2" < "Step 10").
    public static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        let order = lhs.compare(rhs, options: [.caseInsensitive, .numeric])
        return order == .orderedSame ? lhs < rhs : order == .orderedAscending
    }

    /// The collapsed folder paths as one `UserDefaults` string (one path per line) — device
    /// state, never written to the vault.
    public static func encode(_ collapsed: Set<String>) -> String {
        collapsed.sorted().joined(separator: "\n")
    }

    public static func decode(_ stored: String) -> Set<String> {
        Set(stored.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }

    /// `collapsed` with `folder` flipped.
    public static func toggling(_ folder: String, in collapsed: Set<String>) -> Set<String> {
        var out = collapsed
        if out.remove(folder) == nil { out.insert(folder) }
        return out
    }
}
