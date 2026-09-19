import Foundation
import GTDModel
import DesignSystem

/// Strings that only the inbox card uses. The canonical strings of STYLEGUIDE §6.3 and the fixed
/// vocabulary of §6.2 live in `DesignSystem.Copy`; this is the inbox-local complement, kept here
/// because every UI target owns its own string catalog (ARCHITECTURE §5).
///
/// Same shape as `DesignSystem.Copy`: plain `String` constants today, so they compile and test on
/// Linux; T12's `LocalizedStringResource` conversion does not change the call sites.
/// Sentence case, verb-first buttons, no praise, no exclamation marks (§6.1).
public enum InboxCopy {

    // MARK: Card

    public static let titleLabel = "Title"
    public static let titlePlaceholder = "Title of the action note"
    public static let rawTextPlaceholder = "What was captured"
    public static let showAll = "Show all"
    public static let checklist = "Checklist"
    public static let contextGroupLabel = "Context"
    public static let timeGroupLabel = "Time"
    public static let quit = "Quit"
    /// Leaves a sub-flow sheet without filing the card.
    public static let cancel = "Cancel"
    public static let keyLegendLabel = "Keys"

    /// Value chips of STYLEGUIDE §3.5, unset state.
    public static let addDefer = "defer"
    public static let addDue = "due"
    public static let addProject = "project"

    // MARK: Hint overlay (first session only)

    public static let hintTitle = "Swipe to file"
    public static let hintBody = "Right Next · left Backlog · up Maybe · down Trash"
    public static let hintDismiss = "Got it"

    // MARK: Knowledge sheet

    public static let knowledgeFolderLabel = "Folder"
    public static let knowledgeTitleLabel = "Note title"
    public static let newFolder = "New folder"
    public static let newFolderPlaceholder = "Folder name"
    public static let knowledgeRoot = "Knowledge"

    // MARK: Project sheet

    public static let pickProject = "Pick a project"
    public static let newProject = "New project"
    public static let existingProject = "Existing project"
    public static let projectTitleLabel = "Project title"
    public static let outcomeLabel = "Outcome"
    public static let outcomePlaceholder = "Done when…"
    public static let areaLabel = "Area"
    public static let newArea = "New area"
    public static let newAreaPlaceholder = "Area name"
    public static let firstActionsLabel = "First next action"
    public static let addAnotherAction = "Add another"
    public static let noProjectsYet = "No project yet"
    public static let noProjectsYetBody = "Create one for this item."

    // MARK: Defer to review sheet

    public static let deferReasonLabel = "Reason"

    // MARK: Session summary (STYLEGUIDE §5, reward moment)

    /// `14 processed · 6 min`. One wording, owned by `DesignSystem` — `RewardMoment.inboxZero`
    /// renders the same line in the §5.1 moment itself (T41).
    public static func sessionSummary(processed: Int, minutes: Int) -> String {
        Copy.processedSummary(processed: processed, minutes: minutes)
    }

    /// `6 Next · 3 Backlog · 1 Trash` — the per-target breakdown under the summary.
    public static func targetBreakdown(_ counts: [(target: CardTarget, count: Int)]) -> String {
        counts.filter { $0.count > 0 }
            .map { "\($0.count) \($0.target.title)" }
            .joined(separator: " · ")
    }

    // MARK: Capture timestamp (STYLEGUIDE §6.3 — the only place a time of day is shown)

    /// `today 08:12` · `Thu 17:33` · `17 Sep 08:12`. Written by hand rather than with
    /// `DateFormatter` so the output is identical on every platform and locale (§6.1).
    public static func captureStamp(
        _ date: Date,
        today: Day,
        calendar: Calendar = .current
    ) -> String {
        let day = Day(date, calendar: calendar)
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return "\(DateText.short(day, today: today)) \(pad(hour)):\(pad(minute))"
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

/// Turning `What?` lines into checkboxes (STYLEGUIDE §3.5: typing `- ` or pressing the checklist
/// button). Pure text work, so it is unit-tested without a view.
public enum ChecklistText {

    static let marker = "- [ ] "

    /// True when the line already carries a checkbox marker.
    public static func isCheckbox(_ line: String) -> Bool {
        !Checkbox.scan(line).isEmpty
    }

    /// Turns every non-empty line into a checkbox; a text that is already a checklist is left
    /// alone, so the button is idempotent rather than destructive.
    public static func asChecklist(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        return lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !isCheckbox(line) else { return line }
            return marker + trimmed
        }.joined(separator: "\n")
    }

    /// Strips the checkbox markers again (the checklist button toggles).
    public static func asPlainText(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            guard let box = Checkbox.scan(line).first else { return line }
            return box.text
        }.joined(separator: "\n")
    }

    /// True when every non-empty line is a checkbox.
    public static func isChecklist(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return false }
        return lines.allSatisfy(isCheckbox)
    }

    /// Live formatting while typing: a line that starts with `- ` (and is not a checkbox yet)
    /// becomes one. Everything else is returned unchanged.
    public static func autoFormat(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var changed = false
        let formatted = lines.map { line -> String in
            let leading = line.prefix { $0 == " " || $0 == "\t" }
            let rest = line.dropFirst(leading.count)
            guard rest.hasPrefix("- "), !isCheckbox(line) else { return line }
            let body = rest.dropFirst(2)
            // `- [` is the user halfway through typing a marker — leave it be.
            guard !body.hasPrefix("[") else { return line }
            changed = true
            return leading + marker + body
        }
        return changed ? formatted.joined(separator: "\n") : text
    }

    /// First line that carries content, with any bullet or checkbox marker removed.
    /// This is what an action note's title is derived from (I2, T20 brief).
    public static func firstContentLine(_ text: String) -> String {
        for line in text.components(separatedBy: "\n") {
            if let box = Checkbox.scan(line).first {
                let trimmed = box.text.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return trimmed }
                continue
            }
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            while trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("#") {
                trimmed = String(trimmed.dropFirst(trimmed.hasPrefix("#") ? 1 : 2))
                    .trimmingCharacters(in: .whitespaces)
            }
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}
