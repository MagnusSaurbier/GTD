import Foundation

// MARK: - Screens and commands (R-10, N7/I9, STYLEGUIDE §3.6/§3.10/§4.5)

/// The four screens that own a rebindable single-key map. A duplicate key is only refused
/// **within** one screen (STYLEGUIDE §4.5) — the same key may mean different things on two
/// screens.
public enum KeyScreen: String, Sendable, CaseIterable, Codable, Hashable {
    case inboxStep1
    case actionCard
    case knowledgeListCard
    case reviewDeck
}

/// Every single-key command the Mac keyboard offers, grouped by screen (declaration order is
/// legend order). Lives here — not in `FeatureInbox`/`FeatureReview`/`FeatureSettings` — because
/// all three need it and none of the other three may depend on each other (ARCHITECTURE §2);
/// `GTDAppCore` is the one target every one of them already depends on.
///
/// This is deliberately **not** `FeatureInbox.CardTarget`: T04 is reworking that enum's targets
/// concurrently (removing the inbox "Project" filing target), and the Mac `P` key on the action
/// card is a command (open the project chip/picker) rather than a place the card can be filed —
/// modelling it here keeps `KeyMap` from depending on `CardTarget.project` at all.
public enum KeyCommand: String, Sendable, CaseIterable, Codable, Hashable {
    // Step 1 — small card, buttons only (STYLEGUIDE §3.6).
    case stepAction
    case stepKnowledge
    case stepTrash
    case stepDefer

    // Opened action card. `Esc` (collapse) and `⌘↩` (Done) are fixed, not commands.
    case cardSomeday
    case cardNext
    case cardWaiting
    case cardProject

    // Opened Knowledge / List card. `Esc` (collapse) is fixed.
    case listKnowledge
    case listSlot2
    case listSlot3
    case listSlot4
    case listSlot5
    case listSlot6
    case listSlot7
    case listSlot8
    case listSlot9
    case listMore

    // Review deck (STYLEGUIDE §3.10).
    case deckKeep
    case deckDemote
    case deckPromote
    case deckTrash

    public var screen: KeyScreen {
        switch self {
        case .stepAction, .stepKnowledge, .stepTrash, .stepDefer:
            .inboxStep1
        case .cardSomeday, .cardNext, .cardWaiting, .cardProject:
            .actionCard
        case .listKnowledge, .listSlot2, .listSlot3, .listSlot4, .listSlot5, .listSlot6,
             .listSlot7, .listSlot8, .listSlot9, .listMore:
            .knowledgeListCard
        case .deckKeep, .deckDemote, .deckPromote, .deckTrash:
            .reviewDeck
        }
    }

    /// REQUIREMENTS I9, STYLEGUIDE §3.6/§3.10 — the factory map. `KeyBindings.defaults` is built
    /// from this, and `KeyBindings` falls back to it for any command a stored value omits.
    public var defaultKey: KeyStroke {
        switch self {
        case .stepAction: .letter("A")
        case .stepKnowledge: .letter("K")
        case .stepTrash: .letter("X")
        case .stepDefer: .letter("D")
        case .cardSomeday: .arrowLeft
        case .cardNext: .arrowRight
        case .cardWaiting: .letter("W")
        case .cardProject: .letter("P")
        case .listKnowledge: .digit(1)
        case .listSlot2: .digit(2)
        case .listSlot3: .digit(3)
        case .listSlot4: .digit(4)
        case .listSlot5: .digit(5)
        case .listSlot6: .digit(6)
        case .listSlot7: .digit(7)
        case .listSlot8: .digit(8)
        case .listSlot9: .digit(9)
        case .listMore: .digit(0)
        case .deckKeep: .letter("K")
        case .deckDemote: .letter("D")
        case .deckPromote: .letter("P")
        case .deckTrash: .letter("T")
        }
    }

    /// The `2`…`9` slots of the Knowledge / List navbar, in row order — favourite lists fill
    /// these front-to-back (STYLEGUIDE §3.6, at most 4 on iPhone / 8 on Mac; this is the Mac
    /// key, the count cap is a view concern).
    public static let knowledgeListFavouriteSlots: [KeyCommand] = [
        .listSlot2, .listSlot3, .listSlot4, .listSlot5,
        .listSlot6, .listSlot7, .listSlot8, .listSlot9,
    ]
}

// MARK: - Key representation

/// A single key press, displayable exactly as STYLEGUIDE's legends print it: an uppercase
/// letter, a digit, or one of the two arrows. Also represents the four fixed keys (`Esc`, `Tab`,
/// `⌘Z`, `⌘↩`) and the reserved `⇧1`…`⇧4` time-bucket keys, purely so `KeyBindings` can compare
/// against them — none of those four are ever the value of a command binding.
public struct KeyStroke: Sendable, Equatable, Hashable {
    /// Canonical display form. Two `KeyStroke`s are equal exactly when this is equal.
    public let display: String

    private init(display: String) {
        self.display = display
    }

    /// A letter key. Always normalised to uppercase, matching how every legend in STYLEGUIDE
    /// §3.6/§3.10 spells a letter key.
    public static func letter(_ character: Character) -> KeyStroke {
        KeyStroke(display: String(character).uppercased())
    }

    /// A digit key, `0`…`9`.
    public static func digit(_ value: Int) -> KeyStroke {
        precondition((0...9).contains(value), "digit key out of range")
        return KeyStroke(display: String(value))
    }

    /// `⇧1`…`⇧4` — the time-bucket keys reserved on the action card (STYLEGUIDE §3.6 Mac).
    public static func shiftedDigit(_ value: Int) -> KeyStroke {
        precondition((0...9).contains(value), "digit key out of range")
        return KeyStroke(display: "⇧\(value)")
    }

    public static let arrowRight = KeyStroke(display: "→")
    public static let arrowLeft = KeyStroke(display: "←")

    // Fixed, global keys (STYLEGUIDE §3.6/§4.5) — never rebindable, never assignable to a command.
    public static let escape = KeyStroke(display: "Esc")
    public static let tab = KeyStroke(display: "Tab")
    public static let commandZ = KeyStroke(display: "⌘Z")
    public static let commandReturn = KeyStroke(display: "⌘↩")

    /// Reconstructs whatever token a stored binding carries, for `KeyBindings`' tolerant
    /// `Decodable`. Accepts anything non-empty rather than validating against the constructors
    /// above, so a future build's new key shape still round-trips through an older one instead
    /// of being dropped — the only thing that must never happen is a crash.
    static func stored(_ display: String) -> KeyStroke? {
        display.isEmpty ? nil : KeyStroke(display: display)
    }
}

// MARK: - KeyBindings

/// The device-local table *command → key* (R-10, N7). Pure, `Codable`, and the single place
/// `FeatureInbox.KeyMap` and `FeatureReview.ReviewSession.choice(forKey:)` resolve a key press
/// through — both take it as a defaulted parameter so existing call sites keep working until a
/// caller passes the stored value (T08/T09/T12/T13). `FeatureSettings.DeviceSettings` carries one
/// per device; `FeatureSettings.DeviceSettingsStore` persists it exactly as it does every other
/// field, so a missing or corrupt record already falls back to `.default` at that layer.
public struct KeyBindings: Sendable, Equatable {
    /// Only the commands that differ from `KeyCommand.defaultKey`. Reading through `key(for:)`
    /// is what makes a missing entry — an older stored value, or one from a device that has
    /// never touched a given command — resolve to the default instead of crashing or nil-ing.
    private var overrides: [KeyCommand: KeyStroke]

    public init() {
        overrides = [:]
    }

    fileprivate init(overrides: [KeyCommand: KeyStroke]) {
        self.overrides = overrides
    }

    /// The factory map (I9, STYLEGUIDE §3.6/§3.10) — equal to `KeyBindings()`, spelled out so a
    /// call site reads as "the defaults" rather than "an empty table".
    public static let defaults = KeyBindings()

    /// The key bound to `command`, falling back to its default when this table has no override.
    public func key(for command: KeyCommand) -> KeyStroke {
        overrides[command] ?? command.defaultKey
    }

    /// The command bound to `key` on `screen`, or `nil` if nothing on that screen uses it.
    public func command(for key: KeyStroke, on screen: KeyScreen) -> KeyCommand? {
        KeyCommand.allCases.first { $0.screen == screen && self.key(for: $0) == key }
    }

    /// Every command that has been rebound away from its default.
    public var rebound: [KeyCommand] { Array(overrides.keys) }

    // MARK: Rebinding

    public enum RebindError: Error, Sendable, Equatable {
        /// `Esc`, `Tab`, `⌘Z` and `⌘↩` are fixed — never assignable to any command.
        case fixed
        /// On the action card, `1…8` (contexts) and `⇧1…⇧4` (time buckets) are reserved when no
        /// field is focused (STYLEGUIDE §3.6 Mac) — a rebind there cannot collide with them.
        case reserved
        /// Another command on the **same screen** already uses this key. The conflicting command
        /// travels with the error so the caller can show "Already used by <command>" without a
        /// second lookup (STYLEGUIDE §4.5).
        case duplicate(KeyCommand)
    }

    /// Every key that is fixed and global — never rebindable, never assignable to a command
    /// (STYLEGUIDE §3.6 "Always", §4.5).
    public static let fixedKeys: Set<KeyStroke> = [.escape, .tab, .commandZ, .commandReturn]

    /// `1…8` and `⇧1…⇧4`, reserved on the action card only (STYLEGUIDE §3.6 Mac).
    public static let reservedActionCardKeys: Set<KeyStroke> =
        Set((1...8).map(KeyStroke.digit)).union((1...4).map(KeyStroke.shiftedDigit))

    /// Binds `command` to `key`, throwing:
    /// - `.fixed` for one of the four fixed keys,
    /// - `.reserved` for a context/time-bucket key reserved on the action card,
    /// - `.duplicate(_:)` for a key another command on the same screen already uses.
    ///
    /// The same key on a **different** screen is always fine — screens never compete for focus.
    /// Binding a command to its own current key throws nothing (not a self-conflict).
    public mutating func rebind(_ command: KeyCommand, to key: KeyStroke) throws(RebindError) {
        if KeyBindings.fixedKeys.contains(key) {
            throw .fixed
        }
        if command.screen == .actionCard, KeyBindings.reservedActionCardKeys.contains(key) {
            throw .reserved
        }
        if let conflict = KeyCommand.allCases.first(where: {
            $0 != command && $0.screen == command.screen && self.key(for: $0) == key
        }) {
            throw .duplicate(conflict)
        }
        overrides[command] = key
    }

    /// Restores every command on every screen to `KeyCommand.defaultKey`.
    public mutating func reset() {
        overrides.removeAll()
    }

    /// Restores one command to its default.
    public mutating func reset(_ command: KeyCommand) {
        overrides.removeValue(forKey: command)
    }
}

// MARK: - Legends (STYLEGUIDE §3.6/§3.10 "the legend always renders the current bindings")

extension KeyBindings {
    /// One row of a Mac key legend: the current key, and the label the caller supplies (the
    /// wording itself comes from `DesignSystem.Copy` at the call site — this target has no UI
    /// strings).
    public struct LegendEntry: Sendable, Equatable {
        public let key: String
        public let label: String

        public init(key: String, label: String) {
            self.key = key
            self.label = label
        }
    }

    /// The commands of `screen`, each paired with its current key and the label `titles` gives
    /// it, in the screen's canonical order (`KeyCommand`'s declaration order — the order every
    /// STYLEGUIDE legend lists them in). A command `titles` has no entry for is left out, so a
    /// caller with only some of the Knowledge/List slots filled (0-8 favourite lists) gets
    /// exactly the row it can label.
    public func legend(for screen: KeyScreen, titles: [KeyCommand: String]) -> [LegendEntry] {
        KeyCommand.allCases
            .filter { $0.screen == screen }
            .compactMap { command in
                titles[command].map { LegendEntry(key: key(for: command).display, label: $0) }
            }
    }

    /// `legend(for:titles:)` joined the way STYLEGUIDE's simple legends read, e.g. step 1:
    /// `A Action · K Knowledge / List · X Trash · D Defer to review`. The action-card legend
    /// mixes in fixed keys (`⌘↩ Done`, `Esc Back`) that are not commands, so its exact two-group
    /// spacing is a view concern built from `legend(for:titles:)` plus those two fixed rows.
    public func legendString(
        for screen: KeyScreen, titles: [KeyCommand: String], separator: String = " · "
    ) -> String {
        legend(for: screen, titles: titles)
            .map { "\($0.key) \($0.label)" }
            .joined(separator: separator)
    }
}

// MARK: - Codable (tolerant: a missing or unknown command never crashes or loses the rest)

extension KeyBindings: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: String].self)
        var overrides: [KeyCommand: KeyStroke] = [:]
        for (rawCommand, rawKey) in raw {
            // An unknown command (an older or newer build's spelling, or a hand-edited file) is
            // skipped rather than thrown: every other command in the record still loads.
            guard let command = KeyCommand(rawValue: rawCommand) else { continue }
            guard let key = KeyStroke.stored(rawKey) else { continue }
            overrides[command] = key
        }
        self.overrides = overrides
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let raw = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value.display) })
        try container.encode(raw)
    }
}
