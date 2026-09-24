import Foundation
import GTDModel
import DesignSystem

/// Strings that only the inbox card uses. The canonical strings of STYLEGUIDE §6.3 and the fixed
/// vocabulary of §6.2 live in `DesignSystem.Copy`; this is the inbox-local complement, kept here
/// because every UI target owns its own string catalog (ARCHITECTURE §5).
///
/// Same shape as `DesignSystem.Copy`: plain `String` constants, so they compile and are tested on
/// Linux (ARCHITECTURE §5).
/// Sentence case, verb-first buttons, no praise, no exclamation marks (§6.1).
public enum InboxCopy {

    // MARK: Card

    /// C3/R-4 — the prompt of the card's title field, which is the note's file name. (There is
    /// no separate `Title` label.)
    public static let rawTextPlaceholder = "What was captured"
    /// VoiceOver name of the note's body under the title, shown only when there is one.
    public static let bodyLabel = "Note"
    public static let checklist = "Checklist"
    public static let contextGroupLabel = "Context"
    public static let timeGroupLabel = "Time"
    /// Leaves a sub-flow sheet without filing the card.
    public static let cancel = "Cancel"
    public static let keyLegendLabel = "Keys"

    /// `Defer to review` under an action-bar icon and in the Mac key legend, where the full
    /// wording does not fit.
    public static let reviewShort = "Review"

    // MARK: Hint overlay (first session only)

    public static let hintTitle = "Swipe to file"
    public static let hintBody = "Right Next · left Someday · down Back"
    public static let hintDismiss = "Got it"

    // MARK: Knowledge sheet

    public static let knowledgeFolderLabel = "Folder"
    /// I4b — the optional notes panel of the Knowledge / List card (STYLEGUIDE §6.3).
    public static let notesLabel = "Notes"
    public static let notesPlaceholder = "Notes (optional)"
    public static let newFolder = "New folder"
    public static let newFolderPlaceholder = "Folder name"
    public static let knowledgeRoot = "Knowledge"
    /// Accessibility labels of the folder tree's chevron (#24).
    public static let expandFolder = "Show subfolders"
    public static let collapseFolder = "Hide subfolders"

    // MARK: More… sheet (I4b, L2)

    public static let newList = "New list…"
    public static let newListPlaceholder = "List name"
    /// Creates the list and files the card into it — verb-first (§6.1).
    public static let createList = "Create"
    public static let noListsTitle = "No lists yet"
    /// L2 — says what a list *is*, so the empty sheet is not a dead end.
    /// `folder` is the vault's lists folder (`VaultLayout.lists`), which the config can rename.
    public static func noListsBody(folder: String) -> String {
        "A list is a folder under \(folder)/, such as Read, Watch or Wish. "
            + "Create one to file this capture into it."
    }

    /// The reducer's refusal of a list name, in the sheet's words. Same wording as Settings ›
    /// Lists, which refuses the same names for the same reasons.
    public static func newListRefusal(for error: GTDError) -> String {
        switch error {
        case let .invalid(reason): reason
        case let .titleCollision(name): "A list named \"\(name)\" already exists."
        case .notFound, .nextCapReached, .missingFields: Copy.actionFailed
        }
    }

    // MARK: Project picker (I4a)

    public static let pickProject = "Pick a project"
    public static let clearProject = "No project"
    /// STYLEGUIDE §6.3 — the picker's create row, word for word.
    public static func createProject(_ name: String) -> String { "Create project \"\(name)\"" }

    // MARK: Defer to review sheet

    public static let deferReasonLabel = "Reason"

    // MARK: Session summary (STYLEGUIDE §5, reward moment)

    /// `6 Next · 3 Someday · 1 Trash` — the per-target breakdown under the summary. The
    /// `14 processed · 6 min` line above it is `DesignSystem.Copy.processedSummary`, which
    /// `RewardMoment.inboxZero` renders directly.
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
