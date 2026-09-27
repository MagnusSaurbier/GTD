import Foundation
import GTDMarkdown
import GTDModel

/// The incremental index: one decoded entity per file, cached on `path + size + mtime`.
///
/// A full scan decodes everything; every later refresh re-decodes only the files whose
/// fingerprint changed and drops the ones that disappeared (budget: < 50 ms incremental —
/// `scripts/benchmark.sh` measures it, `docs/follow-ups/55-incremental-reindex.md` is the gap).
/// Foundation-only, so all of it runs under `swift test` on Linux.
public struct VaultIndex: Sendable {
    public let layout: VaultLayout
    public let classifier: VaultClassifier
    private let parser: any VaultNoteParser

    private var entries: [String: Entry] = [:]
    private var folders: [String] = []

    public init(layout: VaultLayout = .default, parser: any VaultNoteParser = NoteCodecParser()) {
        self.layout = layout
        self.classifier = VaultClassifier(layout: layout)
        self.parser = parser
    }

    // MARK: Entries

    struct Entry {
        var info: VaultFileInfo
        var kind: VaultFileKind
        var payload: Payload
    }

    enum Payload {
        case inbox(InboxItem)
        case action(Action)
        case listItem(ListItem)
        case area(Area)
        case project(Project)
        case routine(Routine)
        case routineLog([RoutineLogEntry])
        case config(GTDConfig)
        case review(WeeklyReview)
        case reference
        case ignored
        /// Decoding failed — becomes a `VaultIssue`, and the file is left untouched.
        case failed(String)
        /// Evicted iCloud item; the download has been requested.
        case notDownloaded
    }

    /// Files currently indexed. Test/diagnostic surface.
    public var fileCount: Int { entries.count }

    // MARK: Refresh

    /// Result of one refresh, so callers can skip publishing when nothing moved.
    public struct RefreshReport: Sendable, Equatable {
        public var added: Int = 0
        public var updated: Int = 0
        public var removed: Int = 0
        public var reused: Int = 0
        public var foldersChanged: Bool = false

        public var changed: Bool { added + updated + removed > 0 || foldersChanged }
    }

    /// Re-indexes against the current file listing, reusing unchanged decodes.
    @discardableResult
    public mutating func refresh(using fileSystem: any VaultFileSystem) throws -> RefreshReport {
        // One walk for both listings (T41) — see `VaultListing`.
        let listing = try fileSystem.listEntries()
        let files = listing.files
        let folderList = listing.folders
        var report = RefreshReport()

        if folderList != folders {
            folders = folderList
            report.foldersChanged = true
        }

        var next: [String: Entry] = [:]
        next.reserveCapacity(files.count)

        for info in files {
            let kind = classifier.kind(of: info.path)
            if let cached = entries[info.path],
               cached.info.fingerprint == info.fingerprint,
               cached.kind == kind {
                next[info.path] = cached
                report.reused += 1
                continue
            }
            if entries[info.path] == nil { report.added += 1 } else { report.updated += 1 }
            next[info.path] = decode(info: info, kind: kind, fileSystem: fileSystem)
        }

        report.removed = entries.keys.filter { next[$0] == nil }.count
        entries = next
        return report
    }

    /// Re-indexes **only** `paths` — the fast path behind a watcher hint or a commit, which is
    /// what lets an external write show up without walking the vault.
    ///
    /// Returns `nil`, having changed nothing, whenever the hint is not something a per-file look
    /// can answer honestly; the caller then does a full `refresh`:
    /// * a path that is (or was) a **folder** — everything below it moved with it,
    /// * a file in a folder the index has not seen — the folder list feeds lists (§5a) and
    ///   Knowledge folders, and only a walk rebuilds it,
    /// * more paths than a walk would cost.
    /// Everything else is exactly what `refresh` does for one file: compare the fingerprint,
    /// re-decode on a difference, drop the entry when the file is gone.
    public mutating func refresh(
        paths: Set<String>, using fileSystem: any VaultFileSystem
    ) throws -> RefreshReport? {
        guard paths.count <= Self.targetedLimit else { return nil }
        var report = RefreshReport()
        var next = entries
        let knownFolders = Set(folders)

        var files: Set<String> = []
        for raw in paths {
            var path = VaultPath.normalize(raw)
            // An eviction placeholder speaks for the file it stands in for; every other dot
            // file (atomic-write temporaries, `.DS_Store`) is invisible to the walk as well.
            if let original = VaultPath.evictedOriginal(of: path) { path = original }
            guard VaultPath.isSafe(path),
                  !path.split(separator: "/").contains(where: { $0.hasPrefix(".") })
            else { continue }
            files.insert(path)
        }

        for path in files.sorted() {
            guard !fileSystem.folderExists(path), !knownFolders.contains(path) else { return nil }
            guard let info = try fileSystem.info(path) else {
                if next.removeValue(forKey: path) != nil { report.removed += 1 }
                continue
            }
            let folder = VaultPath.folder(of: path)
            guard folder.isEmpty || knownFolders.contains(folder) else { return nil }
            let kind = classifier.kind(of: path)
            if let cached = next[path], cached.info.fingerprint == info.fingerprint,
               cached.kind == kind {
                report.reused += 1
                continue
            }
            if next[path] == nil { report.added += 1 } else { report.updated += 1 }
            next[path] = decode(info: info, kind: kind, fileSystem: fileSystem)
        }
        entries = next
        return report
    }

    /// Past this many hinted paths a sync is landing; one walk is cheaper than that many stats.
    static let targetedLimit = 64

    private func decode(
        info: VaultFileInfo, kind: VaultFileKind, fileSystem: any VaultFileSystem
    ) -> Entry {
        func entry(_ payload: Payload) -> Entry { Entry(info: info, kind: kind, payload: payload) }

        switch kind {
        case .reference:
            return entry(.reference)
        case .knowledge, .archive, .trash, .other:
            return entry(.ignored)
        case .listMisplaced:
            // §5a — the app never guesses which list a stray note belongs to and never moves it.
            return entry(.failed(classifier.misplacedListReason(of: info.path)))
        case .noAreaNote:
            // R-6 — `no_area` is a folder, never an area. Reported, never moved, never rewritten.
            return entry(.failed(classifier.noAreaNoteReason()))
        case .inbox, .action, .listItem, .projectNote, .routine, .routineLog, .review, .config:
            break
        }

        guard info.isDownloaded else {
            // N3 §7.4: ask iCloud for it and report it until it arrives.
            try? fileSystem.requestDownload(info.path)
            return entry(.notDownloaded)
        }

        let text: String
        do {
            guard let read = try fileSystem.readText(info.path) else { return entry(.ignored) }
            text = read
        } catch let error as VaultError {
            if case .notDownloaded = error {
                try? fileSystem.requestDownload(info.path)
                return entry(.notDownloaded)
            }
            return entry(.failed(Self.reason(error)))
        } catch {
            return entry(.failed(Self.reason(error)))
        }

        let id = NoteID(path: info.path)
        do {
            switch kind {
            case .inbox:
                // A capture from outside the app has no `created`; the file's date stands in.
                return entry(.inbox(try parser.inboxItem(
                    id: id, text: text, fileDate: info.modified)))
            case .action:
                var action = try parser.action(id: id, text: text)
                // The only field the codec cannot know: file mtime drives the staleness
                // signals (STYLEGUIDE §2.2, ARCHITECTURE §5).
                action.modified = info.modified
                return entry(.action(action))
            case .listItem:
                return entry(.listItem(try parser.listItem(id: id, text: text, layout: layout)))
            case .projectNote:
                if Frontmatter.scalar("kind", in: text) == "area" {
                    return entry(.area(try parser.area(id: id, text: text)))
                }
                return entry(.project(try parser.project(id: id, text: text)))
            case .routine:
                return entry(.routine(try parser.routine(id: id, text: text)))
            case .routineLog:
                return entry(.routineLog(try parser.routineLog(id: id, text: text)))
            case .review:
                return entry(.review(try parser.weeklyReview(id: id, text: text)))
            case .config:
                return entry(.config(try parser.config(id: id, text: text)))
            case .reference, .knowledge, .archive, .trash, .listMisplaced, .noAreaNote, .other:
                return entry(.ignored)
            }
        } catch {
            return entry(.failed(Self.reason(error)))
        }
    }

    /// Every list of the vault (§5a, L2): one per **direct** subfolder of `Lists/`, `Done/`
    /// excluded because it is the finished-items log of a list, not a list.
    ///
    /// Empty folders count — a list the user just created has no items yet. The names of the
    /// indexed items are folded in as well, so a list can never go missing because a folder
    /// listing came back short.
    private func listFolders(holding items: [ListItem]) -> [GTDList] {
        var names: [String: String] = [:]      // lowercased → the name as the folder spells it
        for folder in folders {
            guard let name = classifier.listFolderName(of: folder) else { continue }
            names[name.lowercased()] = name
        }
        for item in items where names[item.list.lowercased()] == nil {
            names[item.list.lowercased()] = item.list
        }
        return names.values.sorted().map { GTDList(name: $0) }
    }

    private static func reason(_ error: any Error) -> String {
        switch error {
        case let error as NoteCodecError:
            switch error {
            case let .notImplemented(what):
                return "the markdown codec is not available in this build (\(what))"
            case let .unreadable(path, reason):
                return "\(path): \(reason)"
            }
        case let error as VaultError:
            switch error {
            case let .ioFailed(_, reason): return reason
            case let .notDownloaded(path): return "not downloaded from iCloud yet (\(path))"
            default: return "\(error)"
            }
        default:
            return "\(error)"
        }
    }

    // MARK: Snapshot

    /// Assembles the current index into a `VaultSnapshot`.
    ///
    /// `today` decides the 14-day window of the routine log; everything else is derived from the
    /// files alone, so two scans of the same vault produce the same snapshot.
    public func snapshot(today: Day) -> VaultSnapshot {
        var inbox: [InboxItem] = []
        var actions: [Action] = []
        var listItems: [ListItem] = []
        var areas: [Area] = []
        var projects: [Project] = []
        var routines: [Routine] = []
        var routineLog: [RoutineLogEntry] = []
        var reviews: [WeeklyReview] = []
        var config: GTDConfig?
        var issues: [VaultIssue] = []
        var referencesByFolder: [String: [String]] = [:]

        for (path, entry) in entries {
            switch entry.payload {
            case let .inbox(item): inbox.append(item)
            case let .action(action): actions.append(action)
            case let .listItem(item): listItems.append(item)
            case let .area(area): areas.append(area)
            case let .project(project): projects.append(project)
            case let .routine(routine): routines.append(routine)
            case let .routineLog(entries): routineLog.append(contentsOf: entries)
            case let .review(review): reviews.append(review)
            case let .config(decoded): config = decoded
            case .reference:
                referencesByFolder[VaultPath.folder(of: path), default: []].append(path)
            case .ignored:
                break
            case let .failed(reason):
                issues.append(VaultIssue(path: path, message: reason))
            case .notDownloaded:
                issues.append(VaultIssue(
                    path: path,
                    message: "Not downloaded from iCloud yet. The download was requested; "
                        + "this note is missing from the lists until it arrives."))
            }
        }

        // P6: every other file in the project's own folder.
        for index in projects.indices {
            let folder = classifier.projectFolder(of: projects[index].id.path)
            projects[index].referenceFiles = (referencesByFolder[folder] ?? []).sorted()
            // R-6 — the folder says a project in `Projects/no_area/` has no area. A leftover
            // `area:` key contradicts that; the value is left exactly as the file spells it and
            // the note is never rewritten, but the user is told rather than shown two truths.
            if layout.isAreaLessProjectPath(projects[index].id), let area = projects[index].area {
                issues.append(VaultIssue(
                    path: projects[index].id.path,
                    message: classifier.areaLessProjectHasAreaReason(area)))
            }
        }

        // #53 — a `project:` link that names no project (renamed or moved in Obsidian, or a bare
        // `[[Title]]`). The action still works; the user is told where to fix the link. A target
        // that exists but failed to decode or is still in iCloud already has its own issue.
        let projectIDs = Set(projects.map(\.id))
        for action in actions where !action.status.isClosed {
            guard let projectID = action.project, !projectIDs.contains(projectID),
                  entries[projectID.path] == nil
            else { continue }
            issues.append(VaultIssue(
                path: action.id.path,
                message: "`project:` links to \(projectID.path), which is not a project note. "
                    + "Fix the link in Obsidian."))
        }

        // N3 §7.5 — surfaced, never resolved.
        for path in VaultClassifier.conflictCopies(among: Array(entries.keys)) {
            issues.append(VaultIssue(
                path: path,
                message: "Looks like an iCloud conflict copy. Compare it with the original in "
                    + "Obsidian and remove the copy there — the app never touches it."))
        }

        let cutoff = today.adding(days: -13)
        routineLog = routineLog.filter { $0.day >= cutoff && $0.day <= today }

        return VaultSnapshot(
            inbox: inbox.sorted { ($0.created, $0.id) < ($1.created, $1.id) },
            actions: actions.sorted { $0.id < $1.id },
            areas: areas.sorted { $0.id < $1.id },
            projects: projects.sorted { $0.id < $1.id },
            lists: listFolders(holding: listItems),
            listItems: listItems.sorted { $0.id < $1.id },
            routines: routines.sorted { $0.id < $1.id },
            routineLog: routineLog.sorted {
                ($0.at, $0.routine, $0.step) < ($1.at, $1.routine, $1.step)
            },
            knowledgeFolders: folders.compactMap(classifier.knowledgeFolder).sorted(),
            config: config ?? .default,
            // "Newest" by ISO week, not by mtime: re-syncing an old note must not change it.
            lastReview: reviews.max { ($0.year, $0.week) < ($1.year, $1.week) },
            issues: issues.sorted { ($0.path, $0.message) < ($1.path, $1.message) })
    }
}
