import Foundation
import GTDFixtures
import GTDModel

/// A long, ordinary working session: 22 commands covering every case of `GTDCommand`.
///
/// Each step is built from the *current* snapshot, because most of them act on notes an earlier
/// step created or renamed. The script is written so that no step is refused — the Next cap is
/// touched (step 2 fills the last slot) but never broken; the refusals have their own tests.
enum CommandScript {

    struct Step {
        var name: String
        var make: @Sendable (VaultSnapshot) -> GTDCommand?
    }

    static let steps: [Step] = [
        Step(name: "rename a capture") { s in
            guard let item = capture("call the Hausverwaltung", in: s) else { return nil }
            return .renameInboxItem(item.id, title: "call the Hausverwaltung — a mail would do")
        },
        Step(name: "edit a capture's body") { s in
            guard let item = capture("buy new running shoes", in: s) else { return nil }
            return .editInboxBody(item.id, "The ones from the shop near the Uni.")
        },
        Step(name: "file a card to Next (last free slot)") { s in
            guard let item = capture("call the Hausverwaltung", in: s) else { return nil }
            return .fileInbox(item.id, .action(ActionDraft(
                title: "Mail the Hausverwaltung",
                status: .next,
                contexts: ["mac"],
                timeEstimate: 10,
                why: "The window handle has been broken for two weeks.",
                what: "Describe the damage and ask for a repair date.")))
        },
        Step(name: "file a card to Someday") { s in
            guard let item = capture("idea a script", in: s) else { return nil }
            return .fileInbox(item.id, .action(ActionDraft(
                title: "Script that renames scanned PDFs",
                status: .someday,
                contexts: ["deep-work"],
                what: "Read the date from the scan and rename the file.")))
        },
        Step(name: "file a card to Knowledge") { s in
            guard let item = capture("ask Marie", in: s) else { return nil }
            return .fileInbox(item.id, .knowledge(.folder("Thesis"), notes: "Marie has the cable."))
        },
        // I4a/R-8 — a capture that is really a project stays an action and creates the project
        // alongside it, in one command (D33).
        Step(name: "file a card with a project chip that creates the project") { s in
            guard let item = capture("Steuererklärung", in: s) else { return nil }
            return .fileInbox(item.id, .action(ActionDraft(
                title: "Steuererklärung",
                status: .someday,
                contexts: ["mac"],
                newProjectTitle: "Steuererklärung",
                what: "Ask in the student forum whether the semester ticket is deductible.")))
        },
        Step(name: "set a Next action to Waiting") { s in
            guard let action = s.actions.first(where: { $0.title == "Book the dentist appointment" })
            else { return nil }
            return .setStatus(action.id, .waiting, waiting: WaitingInfo(
                who: "Praxis Leopoldstraße", followUp: Fixtures.day(3)))
        },
        Step(name: "complete an action of a project") { s in
            guard let action = s.actions.first(where: { $0.title == "Reply to the DAAD info mail" })
            else { return nil }
            return .complete(action.id)
        },
        Step(name: "toggle a checkbox") { s in
            guard let action = s.actions.first(where: { $0.title == "Prepare the lab presentation" })
            else { return nil }
            return .toggleCheckbox(action.id, index: 0)
        },
        Step(name: "create an action") { _ in
            .createAction(ActionDraft(
                title: "Buy a desk lamp",
                status: .someday,
                contexts: ["errands"],
                timeEstimate: 30,
                why: "The ceiling light is useless in the evening.",
                what: "Check the lamp shop on Schellingstraße."))
        },
        Step(name: "rename an action a project step links to") { s in
            guard var action = s.actions.first(where: {
                $0.title == "Compare Erasmus partner universities"
            }) else { return nil }
            action.title = "Compare Erasmus partners"
            return .updateAction(action)
        },
        Step(name: "promote a project step") { s in
            guard let project = s.projects.first(where: { $0.title == "Masterarbeit" }),
                  let index = project.steps.firstIndex(where: {
                      !$0.done && $0.promotedTo == nil
                  })
            else { return nil }
            return .promoteStep(project: project.id, stepIndex: index, ActionDraft(
                title: "Draft the thesis exposé",
                status: .someday,
                contexts: ["deep-work"],
                timeEstimate: 90,
                project: project.id,
                what: "One page: question, method, timeline."))
        },
        Step(name: "trash an action (I4c: a move into GTD/Trash/, not a status)") { s in
            guard let action = s.actions.first(where: { $0.title == "Digitise the old notes" })
            else { return nil }
            return .trashAction(action.id)
        },
        Step(name: "create an area") { _ in .createArea(title: "Gesundheit") },
        Step(name: "create a project in it") { s in
            guard let area = s.areas.first(where: { $0.title == "Gesundheit" }) else { return nil }
            return .createProject(ProjectDraft(
                title: "Zahnarzt",
                area: area.id,
                outcome: "Check-up done and the follow-up booked.",
                why: "Nine months overdue.",
                steps: ["Call the practice"]))
        },
        Step(name: "put a project on hold (demotes its Next actions)") { s in
            guard var project = s.projects.first(where: { $0.title == "Erasmus" }) else { return nil }
            project.status = .onHold
            return .updateProject(project)
        },
        Step(name: "log a routine step") { s in
            guard let routine = s.routines.first(where: { $0.title == "Morning" }),
                  let step = routine.steps.first
            else { return nil }
            return .logRoutineStep(routine: routine.id, stepID: step.id, .done)
        },
        Step(name: "log a second routine step") { s in
            guard let routine = s.routines.first(where: { $0.title == "Morning" }),
                  routine.steps.count > 1
            else { return nil }
            return .logRoutineStep(routine: routine.id, stepID: routine.steps[1].id, .skipped)
        },
        Step(name: "move a routine") { s in
            guard let routine = s.routines.first(where: { $0.title == "Bedtime" }) else { return nil }
            return .setRoutineTime(routine: routine.id, DayTime(hour: 22, minute: 30))
        },
        Step(name: "raise the Next cap") { s in
            var config = s.config
            config.nextCap = 16
            config.contexts.append("finance")
            return .updateConfig(config)
        },
        Step(name: "save the weekly review") { _ in
            .saveWeeklyReview(WeeklyReview(
                year: 2026,
                week: 38,
                wantedToAchieve: "Get the DAAD letter to a first full draft.",
                achieved: "Outline and two sections.",
                behaviorToChange: "Stop starting the day with mail.",
                whatToStop: "Reading the news before breakfast.",
                howIGrew: "Asked the chair directly instead of waiting.",
                howToGrowFurther: "Ask earlier.",
                whatToTry: "One 90-minute block before any mail.",
                goalForNextWeek: "Motivation letter finished.",
                systemFixNotes: ["Decisions need their own place."]))
        },
        Step(name: "defer a capture to the weekly review") { s in
            guard let item = capture("buy new running shoes", in: s) else { return nil }
            return .deferInboxToReview(item.id, reason: "Needs half an hour of thinking.")
        },
        Step(name: "turn an action into a project") { s in
            guard let action = s.actions.first(where: { $0.title == "Prepare the lab presentation" })
            else { return nil }
            return .convertActionToProject(action.id, ProjectDraft(
                title: "Lab presentation",
                outcome: "Fifteen minutes in front of the chair, done well.",
                why: action.why,
                steps: []))
        },
    ]

    /// The capture whose text starts like this — steps name their card instead of relying on
    /// the queue order, so the script reads like the session it describes.
    private static func capture(_ prefix: String, in s: VaultSnapshot) -> InboxItem? {
        s.inbox.first { $0.title.hasPrefix(prefix) }
    }
}
