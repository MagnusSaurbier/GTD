import Foundation
import GTDMarkdown
import GTDModel
@testable import GTDVault

/// A deliberately tiny `VaultNoteParser` for the tests that are about the **store**, not about
/// the codec: indexing, incremental reuse, snapshot assembly, transactions.
///
/// T10's `NoteCodec` is being written in parallel and every decode still throws, so tests that
/// need real parsing are gated on `NoteCodecParser.codecIsImplemented`
/// (`SampleVaultScanTests`). Everything else uses this stub and hand-written files, which keeps
/// those tests independent of the codec's progress and of the exact markdown format.
///
/// Format it understands: frontmatter scalars (`status`, `created`, `time`, `nextCap`, `year`,
/// `week`, `entries`) plus the body as free text. `entries` is one `routine|step|result|iso`
/// triple per body line.
struct StubNoteParser: VaultNoteParser {
    /// Paths whose decode should fail, so `VaultIssue` handling can be tested.
    var failing: Set<String> = []

    private func check(_ id: NoteID) throws {
        if failing.contains(id.path) {
            throw NoteCodecError.unreadable(path: id.path, reason: "stub failure")
        }
    }

    private func body(_ text: String) -> String {
        guard let block = Frontmatter.block(in: text) else { return text }
        // Skip the opening `---`, the block and the closing `---`.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let rest = lines.dropFirst(block.count + 2)
        return rest.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    func inboxItem(id: NoteID, text: String) throws -> InboxItem {
        try check(id)
        return InboxItem(
            id: id,
            text: body(text),
            created: Self.date(Frontmatter.scalar("created", in: text)) ?? Date(timeIntervalSince1970: 0),
            reviewReason: Frontmatter.scalar("reviewReason", in: text))
    }

    func action(id: NoteID, text: String) throws -> Action {
        try check(id)
        return Action(
            id: id,
            title: id.title,
            status: ActionStatus(rawValue: Frontmatter.scalar("status", in: text) ?? "next") ?? .next,
            contexts: Self.list(Frontmatter.scalar("contexts", in: text)),
            timeEstimate: Frontmatter.scalar("timeEstimate", in: text).flatMap(Int.init),
            project: Frontmatter.scalar("project", in: text).map { NoteID(path: $0) },
            what: body(text))
    }

    func listItem(id: NoteID, text: String, layout: VaultLayout) throws -> ListItem {
        try check(id)
        return ListItem(
            id: id,
            list: layout.listName(of: id) ?? "",
            title: id.title,
            isFinished: layout.isFinishedListItem(id),
            created: Self.date(Frontmatter.scalar("created", in: text)),
            notes: body(text))
    }

    func area(id: NoteID, text: String) throws -> Area {
        try check(id)
        return Area(id: id, title: id.title)
    }

    func project(id: NoteID, text: String) throws -> Project {
        try check(id)
        return Project(
            id: id,
            title: id.title,
            area: Frontmatter.scalar("area", in: text).map { NoteID(path: $0) },
            status: ProjectStatus(rawValue: Frontmatter.scalar("status", in: text) ?? "active") ?? .active,
            outcome: body(text))
    }

    func routine(id: NoteID, text: String) throws -> Routine {
        try check(id)
        return Routine(
            id: id,
            title: id.title,
            time: Frontmatter.scalar("time", in: text).flatMap { DayTime(hhmm: $0) },
            steps: [])
    }

    func routineLog(id: NoteID, text: String) throws -> [RoutineLogEntry] {
        try check(id)
        let device = id.title.split(separator: "-").last.map(String.init) ?? "device"
        return body(text).split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 4, let day = Day(iso: String(parts[3])) else { return nil }
            return RoutineLogEntry(
                day: day,
                routine: String(parts[0]),
                step: String(parts[1]),
                result: RoutineStepResult(rawValue: String(parts[2])) ?? .done,
                at: Self.date(String(parts[3]) + "T08:00:00+00:00") ?? Date(timeIntervalSince1970: 0),
                device: device)
        }
    }

    func config(id: NoteID, text: String) throws -> GTDConfig {
        try check(id)
        var config = GTDConfig.default
        if let cap = Frontmatter.scalar("nextCap", in: text).flatMap(Int.init) { config.nextCap = cap }
        if let contexts = Frontmatter.scalar("contexts", in: text) {
            config.contexts = Self.list(contexts)
        }
        return config
    }

    func weeklyReview(id: NoteID, text: String) throws -> WeeklyReview {
        try check(id)
        return WeeklyReview(
            year: Frontmatter.scalar("year", in: text).flatMap(Int.init) ?? 0,
            week: Frontmatter.scalar("week", in: text).flatMap(Int.init) ?? 0,
            achieved: body(text))
    }

    // MARK: Helpers

    static func list(_ raw: String?) -> [String] {
        guard var raw else { return [] }
        if raw.hasPrefix("["), raw.hasSuffix("]") { raw = String(raw.dropFirst().dropLast()) }
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// `2026-09-19T08:00:00+02:00` → `Date`, without `DateFormatter` (Linux-stable).
    static func date(_ raw: String?) -> Date? {
        guard let raw, let day = Day(iso: raw) else { return nil }
        var hour = 0, minute = 0, second = 0, offset = 0
        if let tIndex = raw.firstIndex(of: "T") {
            let rest = raw[raw.index(after: tIndex)...]
            let timePart = rest.prefix(while: { $0 != "+" && $0 != "-" && $0 != "Z" })
            let fields = timePart.split(separator: ":").compactMap { Int($0) }
            if fields.count >= 2 { hour = fields[0]; minute = fields[1] }
            if fields.count >= 3 { second = fields[2] }
            if let signIndex = rest.firstIndex(where: { $0 == "+" || $0 == "-" }) {
                let sign = rest[signIndex] == "-" ? -1 : 1
                let zone = rest[rest.index(after: signIndex)...].split(separator: ":")
                    .compactMap { Int($0) }
                if zone.count >= 2 { offset = sign * (zone[0] * 3600 + zone[1] * 60) }
            }
        }
        let daysSinceEpoch = TimeInterval(day.serial) * 86_400
        return Date(timeIntervalSince1970:
            daysSinceEpoch + TimeInterval(hour * 3600 + minute * 60 + second - offset))
    }
}
