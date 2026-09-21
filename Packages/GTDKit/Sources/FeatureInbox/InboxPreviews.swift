#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

// Previews for every state of the card and every sub-flow, light / dark / AX1 (STYLEGUIDE §9).
//
// The data is built here rather than taken from `GTDFixtures`: `FeatureInbox` depends on
// `GTDAppCore` + `DesignSystem` only (ARCHITECTURE §2), and previews must not add a dependency
// to the shipping target.

enum InboxPreviewData {

    static let today = Day(year: 2026, month: 9, day: 19)

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7200) ?? .gmt
        return calendar
    }

    static func date(_ day: Day, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(secondsFromGMT: 7200)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    static let area = Area(id: NoteID(path: "Projects/Applications/Applications.md"), title: "Applications")

    static let project = Project(
        id: NoteID(path: "Projects/Applications/DAAD/DAAD.md"),
        title: "DAAD",
        area: area.id,
        status: .active,
        outcome: "Application submitted",
        steps: [ProjectStep(text: "Write the motivation letter")])

    static let inbox: [InboxItem] = [
        InboxItem(
            id: NoteID(path: "Inbox/2026-09-19 081204.md"),
            text: "call the Hausverwaltung about the broken window handle",
            created: date(today, 8, 12)),
        InboxItem(
            id: NoteID(path: "Inbox/2026-09-18 221501.md"),
            text: "idea: a script that renames the scanned pdfs by their date",
            created: date(today.adding(days: -1), 22, 15)),
        InboxItem(
            id: NoteID(path: "Inbox/2026-09-08 071233.md"),
            text: "buy new running shoes before the knee gets worse",
            created: date(today.adding(days: -11), 7, 12)),
    ]

    static func action(_ title: String, _ status: ActionStatus, contexts: [String] = ["mac"]) -> Action {
        Action(
            id: NoteID(path: "Actions/\(title).md"),
            title: title,
            status: status,
            contexts: contexts,
            timeEstimate: 30,
            created: date(today.adding(days: -4), 9, 0),
            modified: date(today.adding(days: -2), 9, 0),
            what: "- [ ] \(title)")
    }

    /// A vault with room in Next.
    static var snapshot: VaultSnapshot {
        VaultSnapshot(
            inbox: inbox,
            actions: [
                action("Write DAAD motivation letter", .next),
                action("Return the library books", .next, contexts: ["errands"]),
                action("Fix the bike light", .someday, contexts: ["home"]),
            ],
            areas: [area],
            projects: [project],
            knowledgeFolders: ["Finanzen", "Studium", "Studium/Thesis", "Technik", "Wohnen"],
            config: .default)
    }

    /// A vault sitting exactly at the cap, so the next card triggers the forced choice (A3).
    static var atCapSnapshot: VaultSnapshot {
        var snapshot = self.snapshot
        snapshot.actions = (0..<snapshot.config.nextCap).map {
            action("Next action \($0 + 1)", .next)
        }
        return snapshot
    }

    @MainActor
    static func model(_ snapshot: VaultSnapshot = InboxPreviewData.snapshot) -> AppModel {
        AppModel(
            backend: InMemoryBackend(snapshot: snapshot),
            snapshot: snapshot,
            today: { today })
    }

    @MainActor
    static func session(
        _ snapshot: VaultSnapshot = InboxPreviewData.snapshot,
        sheet: InboxSession.Sheet? = nil,
        what: String = "",
        lastKnowledgeFolder: String? = "Studium/Thesis"
    ) -> InboxSession {
        let session = InboxSession(
            model: model(snapshot),
            defaults: EphemeralInboxDefaults(lastKnowledgeFolder: lastKnowledgeFolder),
            now: { date(today, 10, 6) })
        session.draft.what = what
        session.sheet = sheet
        return session
    }
}

// MARK: - Card

#Preview("Card — iPhone") {
    NavigationStack {
        InboxProcessingView(onFinished: {})
            .environment(InboxPreviewData.model())
    }
}

#Preview("Card — dark") {
    NavigationStack {
        InboxProcessingView(onFinished: {})
            .environment(InboxPreviewData.model())
    }
    .preferredColorScheme(.dark)
}

#Preview("Card — AX1") {
    NavigationStack {
        InboxProcessingView(onFinished: {})
            .environment(InboxPreviewData.model())
    }
    .environment(\.dynamicTypeSize, .accessibility1)
}

#Preview("Card — filled in, two checkboxes") {
    NavigationStack {
        InboxSessionView(
            session: InboxPreviewData.session(
                what: "- [ ] Ring the Hausverwaltung\n- [ ] Note the case number"),
            onFinished: {})
    }
}

// MARK: - Sub-flows

#Preview("Knowledge") {
    KnowledgeSheet(session: InboxPreviewData.session())
}

#Preview("Project") {
    ProjectSheet(session: InboxPreviewData.session(what: "Collect the transcripts"))
}

#Preview("Waiting") {
    WaitingInfoSheet(today: InboxPreviewData.today) { _ in }
}

#Preview("Defer to review") {
    DeferToReviewSheet(session: InboxPreviewData.session())
}

#Preview("Next is full") {
    CapSheet(session: InboxPreviewData.session(InboxPreviewData.atCapSnapshot))
}

#Preview("Full text") {
    FullTextSheet(session: InboxPreviewData.session())
}

// MARK: - Empty state

#Preview("Inbox zero") {
    NavigationStack {
        InboxZeroView(
            session: InboxPreviewData.session(VaultSnapshot(config: .default)),
            onFinished: {})
    }
}

#Preview("Start button") {
    InboxStartButton(action: {})
        .environment(InboxPreviewData.model())
}
#endif
