import Foundation
import GTDModel

/// `Fixtures.sampleSnapshot` as real markdown files.
///
/// The rendering below is a **fixtures-only** writer — deliberately not `GTDMarkdown.NoteCodec`,
/// because `GTDFixtures` must not depend on the codec (it is what T10 and T15 test *against*).
/// The formats follow ARCHITECTURE §3 exactly; if T10 changes a format, change it here too and
/// re-export the committed copy (see `Sources/GTDFixtures/README.md`).
public enum SampleVault {

    /// Every file of the sample vault: vault-relative path → contents.
    public static var files: [String: String] { render(Fixtures.sampleSnapshot) }

    /// The committed copy under `Sources/GTDFixtures/Resources/SampleVault`, when the resource
    /// bundle is available (it is under `swift build` and under `xcodebuild`).
    public static var bundleURL: URL? {
        Bundle.module.url(forResource: "SampleVault", withExtension: nil)
    }

    /// Writes a throw-away copy of the sample vault and returns its root.
    ///
    /// Uses the committed files when the resource bundle resolves, and falls back to rendering
    /// `Fixtures.sampleSnapshot` otherwise — so tests work in every build system. The caller owns
    /// the directory and should remove it when done.
    @discardableResult
    public static func copyToTemporaryDirectory() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("GTDSampleVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        if let bundleURL {
            try copyTree(from: bundleURL, to: root)
        } else {
            try write(files, to: root)
        }
        return root
    }

    /// Writes `files` (path → text) under `root`, creating intermediate folders.
    public static func write(_ files: [String: String], to root: URL) throws {
        for path in files.keys.sorted() {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files[path]?.write(to: url, atomically: true, encoding: .utf8)
        }
        // Empty folders the app expects to exist (a scan must not create them).
        for folder in Fixtures.knowledgeFolders {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("\(VaultLayout.default.knowledge)/\(folder)"),
                withIntermediateDirectories: true)
        }
    }

    /// Reads a vault tree back into path → text, ignoring dot files.
    public static func read(tree root: URL) throws -> [String: String] {
        var out: [String: String] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return out }
        let prefix = root.standardizedFileURL.path
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: Set(keys)))?.isRegularFile == true else { continue }
            var relative = url.standardizedFileURL.path
            guard relative.hasPrefix(prefix) else { continue }
            relative = String(relative.dropFirst(prefix.count))
            while relative.hasPrefix("/") { relative.removeFirst() }
            out[relative] = try String(contentsOf: url, encoding: .utf8)
        }
        return out
    }

    private static func copyTree(from source: URL, to destination: URL) throws {
        try write(try read(tree: source), to: destination)
    }

    // MARK: - Rendering

    /// The whole snapshot as files (ARCHITECTURE §3 formats).
    public static func render(_ s: VaultSnapshot) -> [String: String] {
        var files: [String: String] = [:]
        let layout = s.config.layout

        for item in s.inbox { files[item.id.path] = renderInbox(item) }
        for action in s.actions { files[action.id.path] = renderAction(action) }
        for item in s.listItems { files[item.id.path] = renderListItem(item) }
        for area in s.areas { files[area.id.path] = renderArea(area) }
        for project in s.projects { files[project.id.path] = renderProject(project) }
        for routine in s.routines { files[routine.id.path] = renderRoutine(routine) }

        // One log file per day per device (R5, N3).
        var byFile: [NoteID: [RoutineLogEntry]] = [:]
        for entry in s.routineLog {
            byFile[layout.routineLogPath(day: entry.day, device: entry.device), default: []].append(entry)
        }
        for (id, entries) in byFile { files[id.path] = renderRoutineLog(entries) }

        files[layout.configFile] = renderConfig(s.config)
        if let review = s.lastReview { files[review.noteID(layout: layout).path] = renderReview(review) }
        return files
    }

    // MARK: Note renderers

    static func renderInbox(_ item: InboxItem) -> String {
        var frontmatter = ["created: \(iso(item.created))"]
        if let reason = item.reviewReason { frontmatter.append("reviewReason: \(quote(reason))") }
        return document(frontmatter: frontmatter, body: item.text + "\n")
    }

    static func renderAction(_ action: Action) -> String {
        var frontmatter = ["status: \(action.status.rawValue)"]
        if !action.contexts.isEmpty {
            frontmatter.append("contexts: [\(action.contexts.joined(separator: ", "))]")
        }
        if let estimate = action.timeEstimate { frontmatter.append("timeEstimate: \(estimate)") }
        if let project = action.project { frontmatter.append("project: \(wikilink(project))") }
        if let deferDate = action.deferDate { frontmatter.append("defer: \(deferDate.iso)") }
        if let due = action.due { frontmatter.append("due: \(due.iso)") }
        if let who = action.waitingFor { frontmatter.append("waitingFor: \(quote(who))") }
        if let followUp = action.followUpDate { frontmatter.append("followUpDate: \(followUp.iso)") }
        if let created = action.created { frontmatter.append("created: \(iso(created))") }
        if let completed = action.completedDate { frontmatter.append("completedDate: \(iso(completed))") }
        if let reason = action.reviewReason { frontmatter.append("reviewReason: \(quote(reason))") }

        var body = "# Why?\n\(action.why)\n"
        body += "\n# What?\n\(action.what)\n"
        return document(frontmatter: frontmatter, body: body)
    }

    /// §5a — the leanest note in the vault: an optional `created`, and the notes as the body.
    static func renderListItem(_ item: ListItem) -> String {
        let frontmatter = item.created.map { ["created: \(iso($0))"] } ?? []
        return document(frontmatter: frontmatter, body: item.notes.isEmpty ? "" : item.notes + "\n")
    }

    static func renderArea(_ area: Area) -> String {
        document(frontmatter: ["kind: area"], body: "# \(area.title)\n")
    }

    static func renderProject(_ project: Project) -> String {
        var frontmatter = ["kind: project", "status: \(project.status.rawValue)"]
        if let area = project.area { frontmatter.append("area: \(wikilink(area))") }

        var body = "# Outcome\n\(project.outcome)\n"
        body += "\n# Why?\n\(project.why)\n"
        body += "\n# Steps\n"
        for step in project.steps {
            let mark = step.done ? "x" : " "
            let promoted = step.promotedTo.map { " → \(bareWikilink($0))" } ?? ""
            body += "- [\(mark)] \(step.text)\(promoted)\n"
        }
        body += "\n# Log\n"
        for entry in project.log {
            body += "- \(entry.day.iso) \(entry.text)\n"
        }
        return document(frontmatter: frontmatter, body: body)
    }

    static func renderRoutine(_ routine: Routine) -> String {
        var body = ""
        for step in routine.steps {
            body += "- [ ] \(step.title)\n"
            for substep in step.substeps { body += "    - [ ] \(substep)\n" }
        }
        let time = routine.time.map { ["time: \"\($0.hhmm)\""] } ?? []
        return document(frontmatter: time, body: body)
    }

    static func renderRoutineLog(_ entries: [RoutineLogEntry]) -> String {
        var frontmatter = ["entries:"]
        for entry in entries.sorted(by: { $0.at < $1.at }) {
            frontmatter.append("  - routine: \(quote(entry.routine))")
            frontmatter.append("    step: \(quote(entry.step))")
            frontmatter.append("    result: \(entry.result.rawValue)")
            frontmatter.append("    at: \(iso(entry.at))")
        }
        return document(frontmatter: frontmatter, body: "")
    }

    static func renderConfig(_ config: GTDConfig) -> String {
        let frontmatter = [
            "contexts: [\(config.contexts.joined(separator: ", "))]",
            "onTheGoContexts: [\(config.onTheGoContexts.joined(separator: ", "))]",
            "nextCap: \(config.nextCap)",
        ]
        return document(
            frontmatter: frontmatter,
            body: "# Config\nSettings synced through the vault. Edited by the app.\n")
    }

    static func renderReview(_ review: WeeklyReview) -> String {
        var frontmatter = ["kind: review", "year: \(review.year)", "week: \(review.week)"]
        if let savedAt = review.savedAt { frontmatter.append("savedAt: \(iso(savedAt))") }

        var body = ""
        let questions: [(String, String)] = [
            ("What did I want to achieve?", review.wantedToAchieve),
            ("What did I achieve?", review.achieved),
            ("Which behavior do I want to change?", review.behaviorToChange),
            ("What do I want to stop?", review.whatToStop),
            ("How did I grow?", review.howIGrew),
            ("How do I want to grow further?", review.howToGrowFurther),
            ("What do I want to try out?", review.whatToTry),
            ("Goal for next week", review.goalForNextWeek),
        ]
        for (heading, answer) in questions { body += "# \(heading)\n\(answer)\n\n" }
        body += "# System fixes\n"
        for note in review.systemFixNotes { body += "- \(note)\n" }
        return document(frontmatter: frontmatter, body: body)
    }

    // MARK: Primitives

    private static func document(frontmatter: [String], body: String) -> String {
        guard !frontmatter.isEmpty else { return body }
        return "---\n" + frontmatter.joined(separator: "\n") + "\n---\n" + body
    }

    /// `"[[Projects/Applications/DAAD/DAAD]]"` — quoted, without the `.md` extension.
    private static func wikilink(_ id: NoteID) -> String { "\"\(bareWikilink(id))\"" }

    private static func bareWikilink(_ id: NoteID) -> String {
        let path = id.path.hasSuffix(".md") ? String(id.path.dropLast(3)) : id.path
        return "[[\(path)]]"
    }

    private static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// ISO-8601 with the fixture offset, e.g. `2026-09-18T21:04:11+02:00`. Written by hand so
    /// the output is identical on every platform (`ISO8601DateFormatter` differs subtly).
    static func iso(_ date: Date) -> String {
        let calendar = Fixtures.calendar
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?, _ width: Int = 2) -> String {
            let s = String(value ?? 0)
            return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
        }
        let offset = Fixtures.timeZoneOffsetSeconds
        let sign = offset < 0 ? "-" : "+"
        let minutes = abs(offset) / 60
        return "\(pad(c.year, 4))-\(pad(c.month))-\(pad(c.day))T"
            + "\(pad(c.hour)):\(pad(c.minute)):\(pad(c.second))"
            + "\(sign)\(pad(minutes / 60)):\(pad(minutes % 60))"
    }
}
