import Foundation
import GTDModel

// Data the inbox sub-flow sheets render (I4). Pure, so the tree building, the grouping and the
// status rule are unit-tested without SwiftUI.

// MARK: - Knowledge folder tree

/// One folder under `Knowledge/`. `path` is vault-relative **without** the `Knowledge/` prefix,
/// exactly as `VaultSnapshot.knowledgeFolders` stores it, so it can be handed straight to
/// `InboxDecision.knowledge(folder:title:)`.
public struct FolderNode: Identifiable, Sendable, Equatable, Hashable {
    public var path: String
    public var name: String
    public var children: [FolderNode]

    public init(path: String, name: String, children: [FolderNode] = []) {
        self.path = path
        self.name = name
        self.children = children
    }

    public var id: String { path }

    /// `nil` for leaves — what stock `OutlineGroup(_:children:)` expects.
    public var childNodes: [FolderNode]? { children.isEmpty ? nil : children }
}

/// Builds the folder tree the knowledge picker browses (I4: free browsing and creating).
public enum KnowledgeTree {

    /// Missing intermediate folders are materialised, so `["a/b"]` yields `a` containing `b`.
    /// Siblings are sorted case-insensitively; duplicates collapse.
    public static func build(_ folders: [String]) -> [FolderNode] {
        var children: [String: [String]] = [:]   // parent path -> child paths
        var seen: Set<String> = []

        for folder in folders {
            let parts = folder.split(separator: "/").map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            var prefix = ""
            for part in parts {
                let path = prefix.isEmpty ? part : prefix + "/" + part
                if !seen.contains(path) {
                    seen.insert(path)
                    children[prefix, default: []].append(path)
                }
                prefix = path
            }
        }

        func nodes(under parent: String) -> [FolderNode] {
            (children[parent] ?? [])
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .map { path in
                    FolderNode(
                        path: path,
                        name: path.split(separator: "/").last.map(String.init) ?? path,
                        children: nodes(under: path))
                }
        }
        return nodes(under: "")
    }

    /// The folder list with `newFolder` added under `parent` — what the picker shows right after
    /// the user creates a folder, before anything is written.
    public static func adding(_ newFolder: String, under parent: String, to folders: [String]) -> [String] {
        let name = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return folders }
        let path = parent.isEmpty ? name : parent + "/" + name
        guard !folders.contains(path) else { return folders }
        return folders + [path]
    }
}

// MARK: - Project picker

/// Projects grouped by area for the project sheet. Ungrouped projects come first and carry no
/// section header — the style guide forbids inventing a "No project" heading (ARCHITECTURE §6).
public struct ProjectGroup: Identifiable, Sendable, Equatable {
    public var area: Area?
    public var projects: [Project]

    public init(area: Area?, projects: [Project]) {
        self.area = area
        self.projects = projects
    }

    public var id: String { area?.id.path ?? "" }
    public var title: String? { area?.title }
}

public enum ProjectPicker {

    /// Every project a card may be filed into: `done` projects are not offered.
    public static func groups(_ snapshot: VaultSnapshot) -> [ProjectGroup] {
        let open = snapshot.projects.filter { $0.status != .done }
        let ungrouped = open.filter { $0.area == nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        var groups: [ProjectGroup] = []
        if !ungrouped.isEmpty { groups.append(ProjectGroup(area: nil, projects: ungrouped)) }

        for area in snapshot.areas.sorted(by: {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }) {
            let projects = open.filter { $0.area == area.id }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            guard !projects.isEmpty else { continue }
            groups.append(ProjectGroup(area: area, projects: projects))
        }
        return groups
    }

    /// The status a *first next action* gets (I4). Only active projects may put actions into Next
    /// (P3), so a first action for an on-hold or someday project lands in Backlog instead of being
    /// refused.
    public static func statusForFirstAction(in project: Project?) -> ActionStatus {
        project?.status == .active ? .next : .backlog
    }
}

// MARK: - Device-local state

/// Device-local inbox state: the last knowledge folder used and whether the one-time swipe hint
/// has been shown. It is **not** vault data (ARCHITECTURE §3: device-local state lives in
/// Application Support, never in the vault).
@MainActor
public protocol InboxDefaultsStore: AnyObject {
    func string(forKey key: String) -> String?
    func setString(_ value: String?, forKey key: String)
    func flag(forKey key: String) -> Bool
    func setFlag(_ value: Bool, forKey key: String)
}

public enum InboxDefaultsKey {
    public static let lastKnowledgeFolder = "gtd.inbox.lastKnowledgeFolder"
    public static let didShowSwipeHint = "gtd.inbox.didShowSwipeHint"
}

/// `UserDefaults`-backed store used by the app.
@MainActor
public final class InboxDefaults: InboxDefaultsStore {
    public static let shared = InboxDefaults()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    public func setString(_ value: String?, forKey key: String) { defaults.set(value, forKey: key) }
    public func flag(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    public func setFlag(_ value: Bool, forKey key: String) { defaults.set(value, forKey: key) }
}

/// Store for tests and previews — nothing touches the real `UserDefaults`.
@MainActor
public final class EphemeralInboxDefaults: InboxDefaultsStore {
    private var values: [String: String] = [:]
    private var flags: [String: Bool] = [:]

    public init(lastKnowledgeFolder: String? = nil, didShowSwipeHint: Bool = true) {
        values[InboxDefaultsKey.lastKnowledgeFolder] = lastKnowledgeFolder
        flags[InboxDefaultsKey.didShowSwipeHint] = didShowSwipeHint
    }

    public func string(forKey key: String) -> String? { values[key] }
    public func setString(_ value: String?, forKey key: String) { values[key] = value }
    public func flag(forKey key: String) -> Bool { flags[key] ?? false }
    public func setFlag(_ value: Bool, forKey key: String) { flags[key] = value }
}
