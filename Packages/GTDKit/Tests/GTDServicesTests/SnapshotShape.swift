import Foundation
import GTDModel

/// A snapshot reduced to what both backends can be expected to agree on.
///
/// Three groups of fields are left out, and each for a reason, not for convenience:
///
/// * `NotePassthrough` — the original file text. An entity built in memory has none; the same
///   entity read back from the vault carries the file it came from. Comparing them would only
///   assert that one side read a file.
/// * `Action.modified` and `VaultSnapshot.issues` — produced by the file system and the scanner.
///   `InMemoryBackend` has no files to have modification dates or unreadable notes.
/// * `knowledgeFolders` — discovered by walking the vault. The reducer does not model the
///   knowledge tree (I4: it is a free folder structure), so filing a card to `Knowledge/` adds a
///   folder on the vault side and nothing in memory. The scenario tests assert the file instead.
///
/// Everything else — every action field, every project step and log line, the routine log, the
/// config, the weekly review — is compared, as text, so a failure names the note that differs.
struct SnapshotShape: Equatable {
    var inbox: [String] = []
    var actions: [String] = []
    var areas: [String] = []
    var projects: [String] = []
    var routines: [String] = []
    var routineLog: [String] = []
    var config: String = ""
    var lastReview: String = ""

    init(_ s: VaultSnapshot) {
        inbox = s.inbox.map {
            "\($0.id) | \($0.body) | created \(stamp($0.created)) | review \($0.reviewReason ?? "-")"
        }.sorted()

        actions = s.actions.map { action in
            [
                "\(action.id)",
                "title \(action.title)",
                "status \(action.status.rawValue)",
                "contexts \(action.contexts.joined(separator: ","))",
                "estimate \(action.timeEstimate.map(String.init) ?? "-")",
                "project \(action.project?.path ?? "-")",
                "defer \(action.deferDate?.iso ?? "-")",
                "due \(action.due?.iso ?? "-")",
                "waitingFor \(action.waitingFor ?? "-")",
                "followUp \(action.followUpDate?.iso ?? "-")",
                "created \(stamp(action.created))",
                "completed \(stamp(action.completedDate))",
                "review \(action.reviewReason ?? "-")",
                "why \(action.why)",
                "what \(action.what)",
            ].joined(separator: " | ")
        }.sorted()

        areas = s.areas.map { "\($0.id) | \($0.title)" }.sorted()

        projects = s.projects.map { project in
            let steps = project.steps.map {
                "[\($0.done ? "x" : " ")] \($0.text) → \($0.promotedTo?.path ?? "-")"
            }.joined(separator: "; ")
            let log = project.log.map { "\($0.day.iso) \($0.text)" }.joined(separator: "; ")
            return [
                "\(project.id)",
                "title \(project.title)",
                "area \(project.area?.path ?? "-")",
                "status \(project.status.rawValue)",
                "outcome \(project.outcome)",
                "why \(project.why)",
                "steps \(steps)",
                "log \(log)",
                "refs \(project.referenceFiles.sorted().joined(separator: ","))",
            ].joined(separator: " | ")
        }.sorted()

        routines = s.routines.map { routine in
            let steps = routine.steps.map {
                "\($0.id):\($0.title)[\($0.substeps.joined(separator: ","))]"
            }.joined(separator: "; ")
            return "\(routine.id) | \(routine.title) | \(routine.time?.hhmm ?? "-") | \(steps)"
        }.sorted()

        routineLog = s.routineLog.map {
            "\($0.day.iso) | \($0.routine) | \($0.step) | \($0.result.rawValue) "
                + "| \(stamp($0.at)) | \($0.device)"
        }.sorted()

        config = "\(s.config.contexts) \(s.config.onTheGoContexts) \(s.config.nextCap) "
            + "\(s.config.layout)"

        lastReview = s.lastReview.map { review in
            [
                "\(review.year)-KW\(review.week)",
                review.wantedToAchieve, review.achieved, review.behaviorToChange,
                review.whatToStop, review.howIGrew, review.howToGrowFurther,
                review.whatToTry, review.goalForNextWeek,
                review.systemFixNotes.joined(separator: ";"),
                stamp(review.savedAt),
            ].joined(separator: " | ")
        } ?? "-"
    }

    /// Whole seconds: the markdown timestamps carry no sub-second part, so a `Date` that went
    /// through a file compares equal to the one that stayed in memory.
    private func stamp(_ date: Date?) -> String {
        guard let date else { return "-" }
        return String(Int(date.timeIntervalSince1970.rounded()))
    }

    /// The lines that differ, for a readable failure message.
    func difference(from other: SnapshotShape) -> String {
        var out: [String] = []
        func compare(_ name: String, _ lhs: [String], _ rhs: [String]) {
            for line in lhs where !rhs.contains(line) { out.append("only in A \(name): \(line)") }
            for line in rhs where !lhs.contains(line) { out.append("only in B \(name): \(line)") }
        }
        compare("inbox", inbox, other.inbox)
        compare("actions", actions, other.actions)
        compare("areas", areas, other.areas)
        compare("projects", projects, other.projects)
        compare("routines", routines, other.routines)
        compare("routineLog", routineLog, other.routineLog)
        if config != other.config { out.append("config:\n  A \(config)\n  B \(other.config)") }
        if lastReview != other.lastReview {
            out.append("lastReview:\n  A \(lastReview)\n  B \(other.lastReview)")
        }
        return out.joined(separator: "\n")
    }
}
