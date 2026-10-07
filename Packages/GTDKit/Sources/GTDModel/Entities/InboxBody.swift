import Foundation

/// #85 — an inbox note's body as the processing card sees it: the capture text (`lead`) and
/// the `# Why?` / `# What?` a half-processed card was closed with.
///
/// Closing the card must not lose what was typed, and the inbox note is the one place a capture
/// lives, so the card's `Why?`/`What?` are kept there under the headings an action note uses —
/// the same shape Obsidian's own action template gives a note. Reading splits them back out, so
/// the card reopens with its fields filled, and filing does not put them into the action twice.
///
/// A body without either heading is all `lead`, exactly as before. So is the empty Why/What
/// template skeleton of an Obsidian-made note (`CaptureText.isEmptyBody`): nothing to split.
public struct InboxBody: Sendable, Equatable {
    public var lead: String
    public var why: String
    public var what: String

    public init(lead: String = "", why: String = "", what: String = "") {
        self.lead = lead
        self.why = why
        self.what = what
    }

    /// True when `body` carries a card's `Why?`/`What?` worth splitting out.
    public static func hasSections(_ body: String) -> Bool {
        !CaptureText.isEmptyBody(body)
            && NoteBody.hasAnySection(of: NoteBody.actionSections, in: body)
    }

    /// The card's view of a stored body.
    public static func read(_ body: String) -> InboxBody {
        guard hasSections(body) else { return InboxBody(lead: body) }
        return InboxBody(
            lead: NoteBody.prefix(of: body),
            why: section("Why?", in: body),
            what: section("What?", in: body))
    }

    /// `self` written over `stored`, changing **only the pieces that differ** from what `stored`
    /// reads as: an untouched lead keeps its exact bytes, an untouched section keeps its heading
    /// line, its template bullets and any section of the user's own (`# Ideas`) around it.
    public func written(over stored: String) -> String {
        let old = InboxBody.read(stored)
        var out = stored
        if lead != old.lead {
            out = InboxBody.hasSections(stored) ? NoteBody.setPrefix(lead, in: stored) : lead
        }
        if why != old.why {
            out = NoteBody.setText("Why?", why, in: out, canonicalOrder: NoteBody.actionSections)
        }
        if what != old.what {
            out = NoteBody.setText("What?", what, in: out, canonicalOrder: NoteBody.actionSections)
        }
        return out
    }

    /// A section's text; a section that holds only template bullets reads as empty.
    private static func section(_ title: String, in body: String) -> String {
        let text = NoteBody.text(of: title, in: body) ?? ""
        return CaptureText.isEmptyBody(text) ? "" : text
    }
}

/// #85 — everything a half-processed card keeps in its inbox note when it is closed
/// (`GTDCommand.saveInboxProgress`): the body (lead + `Why?`/`What?`, `InboxBody`) and the
/// card's chips under the keys an action note uses. The note stays in `Inbox/`, unprocessed.
public struct InboxProgress: Sendable, Equatable, Codable {
    public var body: String
    public var contexts: [String]
    public var timeEstimate: Int?
    public var project: NoteID?
    public var deferDate: Day?
    public var due: Day?

    public init(
        body: String,
        contexts: [String] = [],
        timeEstimate: Int? = nil,
        project: NoteID? = nil,
        deferDate: Day? = nil,
        due: Day? = nil
    ) {
        self.body = body
        self.contexts = contexts
        self.timeEstimate = timeEstimate
        self.project = project
        self.deferDate = deferDate
        self.due = due
    }
}
