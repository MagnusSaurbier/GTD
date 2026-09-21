import Foundation
import GTDModel
import GTDAppCore
import DesignSystem

// The vocabulary of the two-step inbox card (I2–I4c, STYLEGUIDE §3.5/§3.6), defined **once** for
// both platforms: the three steps, the exits each step offers, the drag map and the key map.
// `InboxSession` is the state machine over them; the views hold no decision.

// MARK: - Steps

/// The three states of the inbox card (I2). Step 1 is the small card that only asks *what kind of
/// thing is this*; the other two are the same card **expanded in place** (never a sheet, never a
/// new screen).
public enum InboxStep: String, Sendable, CaseIterable, Hashable, Identifiable {
    /// Small card: the capture text, and the four kind buttons.
    case step1
    /// Step 2a — the opened action card (`Why?`, `What?`, chips, the commitment axis).
    case actionCard
    /// Step 2b — the opened Knowledge / List card (notes panel + navbar).
    case keepCard

    public var id: String { rawValue }

    /// Which rebindable key screen this step's single keys come from (R-10).
    public var keyScreen: KeyScreen {
        switch self {
        case .step1: .inboxStep1
        case .actionCard: .actionCard
        case .keepCard: .knowledgeListCard
        }
    }

    /// True for the two expanded steps — where a drag is recognised at all and where `Esc`
    /// collapses instead of quitting.
    public var isOpened: Bool { self != .step1 }
}

// MARK: - Exits

/// Every way a card can leave the step it is in, plus the two ways a step-1 card opens and the
/// way an opened card collapses (STYLEGUIDE §3.6's three tables, one case per row).
///
/// This is the single list VoiceOver reads out as custom actions (`InboxSession.exits`), the
/// single thing a key resolves to, and the single entry point `InboxSession.take(_:)` switches on.
public enum InboxExit: Sendable, Equatable, Hashable {

    // Step 1 (STYLEGUIDE §3.6, first table).
    /// `Action` — expands the card into step 2a.
    case openAction
    /// `Knowledge / List` — expands the card into step 2b.
    case openKeep
    /// `Trash` — I4c, reachable **only** from step 1.
    case trash
    /// `Defer to review` — I5, reachable **only** from step 1.
    case deferToReview

    // Step 2a — the opened action card (second table).
    case next
    case someday
    case waiting
    /// The 2-minute rule (`⌘↩`): files the card as `done`, asking nothing (I4/D13).
    case done

    // Step 2b — the opened Knowledge / List card (third table).
    case knowledge
    /// One favourite list, by name — files the card at once (I4b).
    case list(String)
    /// `More…` — the sheet with every list.
    case more

    /// `↓` / `Esc` on an opened card: back to step 1, draft intact.
    case collapse

    /// The step this exit belongs to. An exit taken from any other step is refused
    /// (`InboxRefusal.notAvailable`) rather than quietly working — Trash from an opened card is
    /// exactly the mistake STYLEGUIDE §3.6 forbids.
    public var step: InboxStep {
        switch self {
        case .openAction, .openKeep, .trash, .deferToReview: .step1
        case .next, .someday, .waiting, .done: .actionCard
        case .knowledge, .list, .more: .keepCard
        // Both opened steps collapse; `InboxSession` checks `step.isOpened` for this one.
        case .collapse: .actionCard
        }
    }

    /// The fixed vocabulary of STYLEGUIDE §6.2 — what VoiceOver says, and what a bar button and a
    /// legend row read. Never a synonym, never invented at a call site.
    public var title: String {
        switch self {
        case .openAction: Copy.actionKind
        case .openKeep: Copy.knowledgeOrList
        case .trash: Copy.trash
        case .deferToReview: Copy.deferToReview
        case .next: Copy.next
        case .someday: Copy.someday
        case .waiting: Copy.waiting
        case .done: Copy.done
        case .knowledge: Copy.knowledge
        case let .list(name): name
        case .more: Copy.more
        case .collapse: Copy.back
        }
    }

    /// Icon map (STYLEGUIDE §7). A custom list falls back to `list.bullet` via `Symbols.list`.
    public var symbol: String {
        switch self {
        case .openAction: Symbols.actionKind
        case .openKeep: Symbols.knowledgeOrListKind
        case .trash: Symbols.trash
        case .deferToReview: Symbols.deferToReview
        case .next: Symbols.next
        case .someday: Symbols.someday
        case .waiting: Symbols.waiting
        case .done: Symbols.done
        case .knowledge: Symbols.knowledge
        case let .list(name): Symbols.list(named: name)
        case .more: Symbols.more
        case .collapse: Symbols.collapse
        }
    }

    /// The `CardTarget` this exit files to, for the session summary and the undo toast.
    /// `nil` for the three exits that file nothing (open, open, collapse).
    public var target: CardTarget? {
        switch self {
        case .openAction, .openKeep, .collapse: nil
        case .trash: .trash
        case .deferToReview: .deferToReview
        case .next: .next
        case .someday: .someday
        case .waiting: .waiting
        case .done: .done
        case .knowledge: .knowledge
        case .list, .more: .list
        }
    }

    /// The three kind buttons of the step-1 bar, in the order STYLEGUIDE §3.6 fixes. `Defer to
    /// review` is **not** among them — it is the quiet text button under the card.
    public static let stepOneButtons: [InboxExit] = [.openAction, .openKeep, .trash]
}

// MARK: - Card targets (the summary and the undo toast)

/// Where a card ended up, once it is gone. This is the *outcome* taxonomy — the per-target
/// breakdown of the session summary and the wording of the undo toast — not the map of what a
/// gesture or a key does; that is `InboxExit`.
public enum CardTarget: String, Sendable, CaseIterable, Hashable, Identifiable {
    case next
    case someday
    /// I4/D13 — the 2-minute rule: "I just did it". Files the card as `done`, asking nothing.
    case done
    case waiting
    case trash
    case knowledge
    /// §5a — the card became one item of a list.
    case list
    case deferToReview

    public var id: String { rawValue }

    /// The status a target files to — and, through `RequiredField.missing`, what it demands
    /// before it may be reached (R-3).
    public var status: ActionStatus? {
        switch self {
        case .next: .next
        case .someday: .someday
        case .done: .done
        case .waiting: .waiting
        // I4c — Trash is not a status: the card's note is moved to `GTD/Trash/`. Knowledge and
        // the lists are not actions at all.
        default: nil
        }
    }

    /// Fixed vocabulary (STYLEGUIDE §6.2) — never a synonym, never invented at a call site.
    public var title: String {
        switch self {
        case .next: Copy.next
        case .someday: Copy.someday
        case .done: Copy.done
        case .waiting: Copy.waiting
        case .trash: Copy.trash
        case .knowledge: Copy.knowledge
        case .list: Copy.list
        case .deferToReview: Copy.deferToReview
        }
    }

    /// Icon map (STYLEGUIDE §7).
    public var symbol: String {
        switch self {
        case .next: Symbols.next
        case .someday: Symbols.someday
        case .done: Symbols.done
        case .waiting: Symbols.waiting
        case .trash: Symbols.trash
        case .knowledge: Symbols.knowledge
        case .list: Symbols.listBullet
        case .deferToReview: Symbols.deferToReview
        }
    }

    /// The short label under an action-bar icon and in the Mac legend: `Defer to review` does not
    /// fit a quarter of an iPhone bar, so that one target reads `Review` there.
    public var shortTitle: String {
        self == .deferToReview ? InboxCopy.reviewShort : title
    }

    /// R-3 — what this target needs from the draft before the card may leave through it. Empty
    /// for Trash, Knowledge, the lists and `Done` (STYLEGUIDE §3.6 "Validation before leaving").
    public func missingFields(
        why: String, what: String, contexts: [String], timeEstimate: Int?, followUpDate: Day?
    ) -> [RequiredField] {
        guard let status else { return [] }
        return RequiredField.missing(
            status: status, previous: nil, why: why, what: what,
            contexts: contexts, timeEstimate: timeEstimate, followUpDate: followUpDate)
    }

    /// What the undo toast says after this card left: `Moved to Someday` (STYLEGUIDE §3.8, §6.3).
    /// A list filing carries its own name, so it reads `Added to Read` (`Copy.addedTo`).
    public func undoToastLabel(listName: String? = nil) -> String {
        switch self {
        case .deferToReview: Copy.deferToReview
        case .list: Copy.addedTo(listName ?? Copy.list)
        default: Copy.movedTo(title)
        }
    }

    /// The labelled buttons of the opened action card's bar (STYLEGUIDE §3.6): the two targets
    /// that are neither a swipe nor a chip.
    public static let actionCardButtons: [CardTarget] = [.waiting, .done]

    /// What the `⋯` ("File to") menu on the action card holds: the two swipe targets, so a card
    /// taller than the screen can still be filed. Same order as the legend.
    public static let actionCardMenu: [CardTarget] = directionalTargets

    /// The directional targets, in legend order. Trash is not among them: no swipe ever
    /// trashes (STYLEGUIDE decision #12) — it is a step-1 button.
    public static let directionalTargets: [CardTarget] = [.someday, .next]

    /// Drag tint of a destructive target: `signalOverdue` at 18 % (STYLEGUIDE §3.6). The two
    /// directional targets use a token colour as is (`accentWash`, `fillQuiet`).
    public static let trashTintOpacity: Double = 0.18
}

/// Inbox-local symbol aliases. Everything the card draws is in `DesignSystem.Symbols` now
/// (T06 added the step-1 kinds, `more`, `collapse` and the required-field asterisk); this enum
/// only keeps the one name the card's views already spell, so no view writes a literal.
public enum InboxSymbols {
    /// The overflow menu of the action card's bar (`⋯`), and the navbar's `More…` slot.
    public static let more = Symbols.more
}

// MARK: - Drag (STYLEGUIDE §3.6)

/// The directions a card can be thrown in. There is no `up` (the two "not now" tiers merged into
/// Someday, A3 — an upward drag does **nothing**), and `down` files nothing: it collapses the
/// opened card back to step 1 (D10, STYLEGUIDE decision #12).
public enum SwipeDirection: Sendable, Equatable, CaseIterable {
    case left, right, down

    public var isHorizontal: Bool { self == .left || self == .right }

    /// The exit this direction reaches on the opened action card, or `nil` for `down`.
    public var exit: InboxExit? {
        switch self {
        case .right: .next
        case .left: .someday
        case .down: nil
        }
    }
}

/// What a completed drag does.
public enum DragOutcome: Sendable, Equatable {
    case file(InboxExit)
    /// `↓` past 25 % of the card height — back to step 1, draft intact.
    case collapse
}

/// Everything the drag map needs to know about the card underneath the finger. Passing it as one
/// value is what keeps "no drag on step 1" and "swipes are off while a field is focused" from
/// being re-decided in a view.
public struct DragContext: Sendable, Equatable {
    public var step: InboxStep
    /// STYLEGUIDE §3.6: "Swipes are disabled while any text field is focused (keyboard up)."
    public var isFieldFocused: Bool

    public init(step: InboxStep, isFieldFocused: Bool = false) {
        self.step = step
        self.isFieldFocused = isFieldFocused
    }
}

/// Which direction a drag resolves to, given the step, the focus, the card size and the
/// translation. Pure, so axis lock, thresholds and the per-step gating are unit-tested without a
/// UI (STYLEGUIDE §3.6).
public enum DragResolver {

    /// The directions this context recognises at all:
    /// - **step 1**: none — "no drag is recognised on the small card".
    /// - **opened action card**: `←`, `→`, `↓`.
    /// - **opened Knowledge / List card**: `↓` only.
    /// - **any step with a field focused**: none.
    public static func recognised(in context: DragContext) -> Set<SwipeDirection> {
        guard !context.isFieldFocused else { return [] }
        switch context.step {
        case .step1: return []
        case .actionCard: return [.left, .right, .down]
        case .keepCard: return [.down]
        }
    }

    /// The dominant axis after the 12 pt axis lock, or `nil` when this context recognises
    /// nothing there. Upward always yields `nil` — the card springs back.
    public static func direction(dx: CGFloat, dy: CGFloat, in context: DragContext) -> SwipeDirection? {
        let allowed = recognised(in: context)
        guard !allowed.isEmpty else { return nil }
        guard max(abs(dx), abs(dy)) >= DragThresholds.axisLock else { return nil }
        let direction: SwipeDirection?
        if abs(dx) >= abs(dy) {
            direction = dx > 0 ? .right : .left
        } else {
            // Up files nothing since the tiers were merged into Someday (A3).
            direction = dy < 0 ? nil : .down
        }
        guard let direction, allowed.contains(direction) else { return nil }
        return direction
    }

    /// What releasing here does, or `nil` when the card springs back.
    public static func outcome(
        dx: CGFloat, dy: CGFloat, cardSize: CGSize, in context: DragContext
    ) -> DragOutcome? {
        guard let direction = direction(dx: dx, dy: dy, in: context) else { return nil }
        guard progress(dx: dx, dy: dy, cardSize: cardSize, in: context)
            >= threshold(for: direction) else { return nil }
        guard let exit = direction.exit else { return .collapse }
        return .file(exit)
    }

    /// How far the drag has come towards its outcome, as a fraction of the threshold (0…1+).
    /// The destination label and the tint appear at `1` (STYLEGUIDE §3.6).
    public static func commitment(
        dx: CGFloat, dy: CGFloat, cardSize: CGSize, in context: DragContext
    ) -> CGFloat {
        guard let direction = direction(dx: dx, dy: dy, in: context) else { return 0 }
        return progress(dx: dx, dy: dy, cardSize: cardSize, in: context) / threshold(for: direction)
    }

    /// The translation the card is allowed to follow: the dominant recognised axis only (axis
    /// lock). A context that recognises nothing holds the card still.
    public static func lockedTranslation(dx: CGFloat, dy: CGFloat, in context: DragContext) -> CGSize {
        guard let direction = direction(dx: dx, dy: dy, in: context) else { return .zero }
        return direction.isHorizontal ? CGSize(width: dx, height: 0) : CGSize(width: 0, height: dy)
    }

    private static func progress(
        dx: CGFloat, dy: CGFloat, cardSize: CGSize, in context: DragContext
    ) -> CGFloat {
        guard let direction = direction(dx: dx, dy: dy, in: context) else { return 0 }
        return direction.isHorizontal
            ? abs(dx) / max(cardSize.width, 1)
            : abs(dy) / max(cardSize.height, 1)
    }

    private static func threshold(for direction: SwipeDirection) -> CGFloat {
        switch direction {
        case .left, .right: DragThresholds.horizontal
        case .down: DragThresholds.vertical   // 25 % of card height collapses it (§3.6)
        }
    }
}

// MARK: - Keyboard (STYLEGUIDE §3.6, Mac)

/// What a key press means on the inbox card. Everything rebindable arrives as a
/// `GTDAppCore.KeyCommand` — the map itself lives in `KeyBindings` (R-10, N7), not here — and the
/// four fixed keys (`Esc`, `⌘↩`, `⌘Z`, and the reserved context/time digits) get their own cases.
public enum InboxKey: Sendable, Equatable {
    /// A rebindable single-key command of the current step's `KeyScreen`.
    case command(KeyCommand)
    /// `1…8` — the n-th context of `GTDConfig.contexts`, zero-based. Action card only.
    case context(index: Int)
    /// `⇧1…⇧4` — a time bucket. Action card only.
    case time(TimeBucket)
    /// `⌘↩` — Done (fixed). Action card only.
    case done
    /// `⌘Z` (fixed).
    case undo
    /// `Esc` (fixed) — the ladder of STYLEGUIDE §3.6, resolved by `InboxSession.escape()`.
    case escape
}

/// The single place that resolves a Mac key press on the inbox card (ARCHITECTURE §6).
///
/// Every letter and digit goes through `KeyBindings.command(for:on:)` for the *current step's*
/// screen, so a rebind in Settings › Keyboard takes effect here without a line changing. Keys
/// only apply **when no text field is focused** — the caller checks that, because focus is a
/// view concern (`InboxSession.isFieldFocused` carries it for the model).
public enum KeyMap {

    /// Resolves a `KeyStroke` — what the arrow keys and the legend already speak in.
    public static func resolve(
        stroke: KeyStroke,
        step: InboxStep,
        bindings: KeyBindings = .defaults
    ) -> InboxKey? {
        if stroke == .escape { return .escape }
        if stroke == .commandZ { return .undo }
        if stroke == .commandReturn { return step == .actionCard ? .done : nil }
        // The action card reserves `1…8` for contexts and `⇧1…⇧4` for time buckets, so they are
        // never looked up as commands there (`KeyBindings.reservedActionCardKeys`).
        if step == .actionCard {
            if let bucket = timeBucket(for: stroke) { return .time(bucket) }
            if let index = contextIndex(for: stroke) { return .context(index: index) }
        }
        guard let command = bindings.command(for: stroke, on: step.keyScreen) else { return nil }
        return .command(command)
    }

    /// Resolves a character press. `shift` may be reported either through the modifier flag or
    /// through the shifted character itself (`!@#$`), depending on the keyboard layout — both
    /// work.
    public static func resolve(
        _ character: Character,
        shift: Bool = false,
        command: Bool = false,
        step: InboxStep,
        bindings: KeyBindings = .defaults
    ) -> InboxKey? {
        if character == "\u{1B}" { return .escape }
        if command {
            if character == "\r" || character == "\n" {
                return resolve(stroke: .commandReturn, step: step, bindings: bindings)
            }
            return character.lowercased() == "z" ? .undo : nil
        }
        if let bucket = shiftedTimeBucket(character), step == .actionCard { return .time(bucket) }
        if let digit = character.wholeNumberValue, (0...9).contains(digit) {
            let stroke = shift ? KeyStroke.shiftedDigit(digit) : KeyStroke.digit(digit)
            return resolve(stroke: stroke, step: step, bindings: bindings)
        }
        guard !shift else { return nil }
        return resolve(stroke: .letter(character), step: step, bindings: bindings)
    }

    private static func contextIndex(for stroke: KeyStroke) -> Int? {
        guard let digit = Int(stroke.display), (1...8).contains(digit) else { return nil }
        return digit - 1
    }

    private static func timeBucket(for stroke: KeyStroke) -> TimeBucket? {
        guard stroke.display.hasPrefix("⇧"),
              let digit = Int(stroke.display.dropFirst()),
              digit >= 1, digit <= TimeBucket.allCases.count
        else { return nil }
        return TimeBucket.allCases[digit - 1]
    }

    /// `⇧1…⇧4` on a US layout arrives as `!`, `@`, `#`, `$`.
    private static func shiftedTimeBucket(_ character: Character) -> TimeBucket? {
        guard let index = "!@#$".firstIndex(of: character) else { return nil }
        let offset = "!@#$".distance(from: "!@#$".startIndex, to: index)
        guard offset < TimeBucket.allCases.count else { return nil }
        return TimeBucket.allCases[offset]
    }
}
