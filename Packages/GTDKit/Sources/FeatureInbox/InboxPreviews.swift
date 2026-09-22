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

    /// Named after their text, like every capture (C3). The last one was made in Obsidian from
    /// the user's template: its body is the empty skeleton, and the card still shows its name.
    static let inbox: [InboxItem] = [
        InboxItem(
            id: NoteID(path: "Inbox/call the Hausverwaltung about the broken window handle.md"),
            body: "",
            created: date(today, 8, 12)),
        InboxItem(
            id: NoteID(path: "Inbox/idea a script that renames the scanned pdfs by their date.md"),
            body: "idea: a script that renames the scanned pdfs by their date",
            created: date(today.adding(days: -1), 22, 15)),
        InboxItem(
            id: NoteID(path: "Inbox/buy new running shoes.md"),
            body: "# Why?\n- \n\n# What?\n- [ ] ",
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

    /// Forty projects over four areas plus some area-less ones, and a deep knowledge tree — far
    /// more rows than a sheet is tall, to check that the pickers scroll (the fixtures have too
    /// few projects to show an overflow).
    static var crowdedSnapshot: VaultSnapshot {
        var snapshot = self.snapshot
        let areas = ["Applications", "Home", "Studies", "Work"].map {
            Area(id: NoteID(path: "Projects/\($0)/\($0).md"), title: $0)
        }
        snapshot.areas = areas
        snapshot.projects = (1...40).map { index in
            let area = index % 5 == 0 ? nil : areas[index % areas.count]
            let folder = area.map { "Projects/\($0.title)" } ?? "Projects"
            return Project(
                id: NoteID(path: "\(folder)/Project \(index)/Project \(index).md"),
                title: "Project \(index)",
                area: area?.id,
                status: .active,
                outcome: "Outcome \(index)",
                steps: [])
        }
        snapshot.knowledgeFolders = (1...30).map { "Folder \($0)" }
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

// MARK: - Step 1 (small card, buttons only)

#Preview("Step 1 — iPhone") {
    NavigationStack {
        InboxProcessingView(onFinished: {})
            .environment(InboxPreviewData.model())
    }
}

#Preview("Step 1 — dark") {
    NavigationStack {
        InboxProcessingView(onFinished: {})
            .environment(InboxPreviewData.model())
    }
    .preferredColorScheme(.dark)
}

#Preview("Step 1 — AX1") {
    NavigationStack {
        InboxProcessingView(onFinished: {})
            .environment(InboxPreviewData.model())
    }
    .environment(\.dynamicTypeSize, .accessibility1)
}

#Preview("Step 1 — Mac") {
    InboxSessionView(session: InboxPreviewData.session(), onFinished: {})
        .frame(width: 900, height: 600)
}

// MARK: - Step 2a (opened action card)

#Preview("Action card — iPhone") {
    let session = InboxPreviewData.session(
        what: "- [ ] Ring the Hausverwaltung\n- [ ] Note the case number")
    return InboxSessionView(session: session, onFinished: {})
        .task { await session.take(.openAction) }
}

#Preview("Action card — dark") {
    let session = InboxPreviewData.session()
    return InboxSessionView(session: session, onFinished: {})
        .task { await session.take(.openAction) }
        .preferredColorScheme(.dark)
}

#Preview("Action card — AX1") {
    let session = InboxPreviewData.session()
    return InboxSessionView(session: session, onFinished: {})
        .task { await session.take(.openAction) }
        .environment(\.dynamicTypeSize, .accessibility1)
}

#Preview("Action card — Mac") {
    let session = InboxPreviewData.session()
    return InboxSessionView(session: session, onFinished: {})
        .task { await session.take(.openAction) }
        .frame(width: 900, height: 700)
}

/// Refusal state (STYLEGUIDE §3.6 "Validation before leaving"): every missing field/chip group
/// carries its asterisk, no alert, no red border.
#Preview("Action card — refused, asterisks") {
    let session = InboxPreviewData.session()
    return InboxSessionView(session: session, onFinished: {})
        .task {
            await session.take(.openAction)
            await session.take(.next)
        }
}

// MARK: - Step 2b (opened Knowledge / List card)

#Preview("Keep card — iPhone") {
    let session = InboxPreviewData.session()
    return InboxSessionView(session: session, onFinished: {})
        .task { await session.take(.openKeep) }
}

#Preview("Keep card — Mac") {
    let session = InboxPreviewData.session()
    return InboxSessionView(session: session, onFinished: {})
        .task { await session.take(.openKeep) }
        .frame(width: 900, height: 600)
}

// MARK: - Sub-flows

#Preview("Knowledge") {
    KnowledgeSheet(session: InboxPreviewData.session())
}

#Preview("Project") {
    ProjectSheet(session: InboxPreviewData.session(what: "Collect the transcripts"))
}

#Preview("Project — 40 projects, must scroll") {
    ProjectSheet(session: InboxPreviewData.session(InboxPreviewData.crowdedSnapshot))
}

#Preview("Knowledge — crowded, must scroll") {
    KnowledgeSheet(session: InboxPreviewData.session(InboxPreviewData.crowdedSnapshot))
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

// MARK: - Make action (L4, T10's reusable card)

#Preview("Make action — iPhone") {
    NavigationStack {
        MakeActionCardView(
            model: MakeActionModel(
                model: InboxPreviewData.model(),
                item: ListItem(
                    id: NoteID(path: "Lists/Read/Some article.md"),
                    list: "Read",
                    title: "Some article about deep work",
                    created: InboxPreviewData.date(InboxPreviewData.today, 9, 0),
                    notes: "Recommended by a friend")),
            onFinished: {})
    }
}

#Preview("Make action — Mac") {
    NavigationStack {
        MakeActionCardView(
            model: MakeActionModel(
                model: InboxPreviewData.model(),
                item: ListItem(
                    id: NoteID(path: "Lists/Read/Some article.md"),
                    list: "Read",
                    title: "Some article about deep work",
                    created: InboxPreviewData.date(InboxPreviewData.today, 9, 0))),
            onFinished: {})
    }
    .frame(width: 900, height: 700)
}
#endif
