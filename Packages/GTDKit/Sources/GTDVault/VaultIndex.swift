import Foundation
import GTDMarkdown
import GTDModel

/// The incremental index: one decoded entity per file, cached on `path + size + mtime`.
///
/// A full scan decodes everything; every later refresh re-decodes only the files whose
/// fingerprint changed and drops the ones that disappeared (T15 budget: < 50 ms incremental).
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

    private func decode(
        info: VaultFileInfo, kind: VaultFileKind, fileSystem: any VaultFileSystem
    ) -> Entry {
        func entry(_ payload: Payload) -> Entry { Entry(info: info, kind: kind, payload: payload) }

        switch kind {
        case .reference:
            return entry(.reference)
        case .knowledge, .archive, .trash, .other:
            return entry(.ignored)
        case .inbox, .action, .projectNote, .routine, .routineLog, .review, .config:
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
                return entry(.inbox(try parser.inboxItem(id: id, text: text)))
            case .action:
                var action = try parser.action(id: id, text: text)
                // The only field the codec cannot know: file mtime drives the staleness
                // signals (STYLEGUIDE §2.2, ARCHITECTURE §5).
                action.modified = info.modified
                return entry(.action(action))
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
            case .reference, .knowledge, .archive, .trash, .other:
                return entry(.ignored)
            }
        } catch {
            return entry(.failed(Self.reason(error)))
        }
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
