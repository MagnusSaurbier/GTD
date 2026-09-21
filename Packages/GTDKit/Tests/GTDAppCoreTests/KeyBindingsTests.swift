import Testing
import Foundation
@testable import GTDAppCore

/// R-10 / N7 / I9 — the rebindable key map. STYLEGUIDE §3.6/§3.10 and REQUIREMENTS I9 give the
/// literal defaults and legend strings this suite pins.
struct KeyBindingsTests {

    // MARK: Defaults (I9, STYLEGUIDE §3.6/§3.10)

    @Test func defaultsMatchRequirementsI9() {
        let d = KeyBindings.defaults
        // Step 1.
        #expect(d.key(for: .stepAction) == .letter("A"))
        #expect(d.key(for: .stepKnowledge) == .letter("K"))
        #expect(d.key(for: .stepTrash) == .letter("X"))
        #expect(d.key(for: .stepDefer) == .letter("D"))
        // Action card.
        #expect(d.key(for: .cardNext) == .arrowRight)
        #expect(d.key(for: .cardSomeday) == .arrowLeft)
        #expect(d.key(for: .cardWaiting) == .letter("W"))
        #expect(d.key(for: .cardProject) == .letter("P"))
        // Knowledge / List card.
        #expect(d.key(for: .listKnowledge) == .digit(1))
        #expect(d.key(for: .listSlot2) == .digit(2))
        #expect(d.key(for: .listSlot9) == .digit(9))
        #expect(d.key(for: .listMore) == .digit(0))
        // Review deck.
        #expect(d.key(for: .deckKeep) == .letter("K"))
        #expect(d.key(for: .deckDemote) == .letter("D"))
        #expect(d.key(for: .deckPromote) == .letter("P"))
        #expect(d.key(for: .deckTrash) == .letter("T"))
    }

    @Test func everyCommandBelongsToExactlyOneScreen() {
        let bySreen = Dictionary(grouping: KeyCommand.allCases, by: \.screen)
        #expect(bySreen[.inboxStep1]?.count == 4)
        #expect(bySreen[.actionCard]?.count == 4)
        #expect(bySreen[.knowledgeListCard]?.count == 10)
        #expect(bySreen[.reviewDeck]?.count == 4)
    }

    @Test func emptyBindingsIsExactlyTheDefaults() {
        #expect(KeyBindings() == KeyBindings.defaults)
        for command in KeyCommand.allCases {
            #expect(KeyBindings().key(for: command) == command.defaultKey)
        }
    }

    // MARK: Rebind

    @Test func rebindHappyPath() throws {
        var bindings = KeyBindings.defaults
        try bindings.rebind(.stepAction, to: .letter("Q"))
        #expect(bindings.key(for: .stepAction) == .letter("Q"))
        #expect(bindings.rebound == [.stepAction])
    }

    @Test func duplicateWithinTheSameScreenIsRefusedWithTheConflictingCommand() {
        var bindings = KeyBindings.defaults
        // `stepKnowledge` already owns `K` on `inboxStep1`.
        #expect(throws: KeyBindings.RebindError.duplicate(.stepKnowledge)) {
            try bindings.rebind(.stepAction, to: .letter("K"))
        }
        // The refused rebind must not have taken effect.
        #expect(bindings.key(for: .stepAction) == .letter("A"))
    }

    @Test func sameKeyOnADifferentScreenIsAllowed() throws {
        var bindings = KeyBindings.defaults
        // `deckKeep` already uses `K`, same as `stepKnowledge` (a different screen) — fine.
        try bindings.rebind(.cardWaiting, to: .letter("K"))
        #expect(bindings.key(for: .cardWaiting) == .letter("K"))
    }

    @Test func rebindingACommandToItsOwnCurrentKeyDoesNotThrow() throws {
        var bindings = KeyBindings.defaults
        try bindings.rebind(.stepAction, to: .letter("A"))
        #expect(bindings.key(for: .stepAction) == .letter("A"))
    }

    @Test func fixedKeysAreNeverAssignable() {
        var bindings = KeyBindings.defaults
        for fixed in [KeyStroke.escape, .tab, .commandZ, .commandReturn] {
            #expect(throws: KeyBindings.RebindError.fixed) {
                try bindings.rebind(.stepAction, to: fixed)
            }
        }
        #expect(bindings.key(for: .stepAction) == .letter("A"))
    }

    @Test func reservedActionCardKeysAreRefusedOnTheActionCardOnly() throws {
        var bindings = KeyBindings.defaults
        for context in 1...8 {
            #expect(throws: KeyBindings.RebindError.reserved) {
                try bindings.rebind(.cardWaiting, to: .digit(context))
            }
        }
        for bucket in 1...4 {
            #expect(throws: KeyBindings.RebindError.reserved) {
                try bindings.rebind(.cardWaiting, to: .shiftedDigit(bucket))
            }
        }
        // The same digits are not reserved on a screen that has no context/time-bucket keys.
        try bindings.rebind(.deckKeep, to: .digit(3))
        #expect(bindings.key(for: .deckKeep) == .digit(3))
    }

    @Test func resetRestoresOneOrEveryCommand() throws {
        var bindings = KeyBindings.defaults
        try bindings.rebind(.stepAction, to: .letter("Q"))
        try bindings.rebind(.deckKeep, to: .letter("J"))

        bindings.reset(.stepAction)
        #expect(bindings.key(for: .stepAction) == .letter("A"))
        #expect(bindings.key(for: .deckKeep) == .letter("J"))     // untouched

        bindings.reset()
        #expect(bindings == KeyBindings.defaults)
    }

    @Test func commandForKeyFindsItOnItsScreenOnly() {
        let bindings = KeyBindings.defaults
        #expect(bindings.command(for: .letter("A"), on: .inboxStep1) == .stepAction)
        #expect(bindings.command(for: .letter("A"), on: .actionCard) == nil)
        #expect(bindings.command(for: .arrowRight, on: .actionCard) == .cardNext)
    }

    // MARK: Codable

    @Test func codableRoundTrip() throws {
        var bindings = KeyBindings.defaults
        try bindings.rebind(.stepAction, to: .letter("Q"))
        try bindings.rebind(.deckTrash, to: .letter("X"))

        let data = try JSONEncoder().encode(bindings)
        let decoded = try JSONDecoder().decode(KeyBindings.self, from: data)
        #expect(decoded == bindings)
        #expect(decoded.key(for: .stepAction) == .letter("Q"))
        #expect(decoded.key(for: .deckTrash) == .letter("X"))
        // Everything else still falls back to its default.
        #expect(decoded.key(for: .cardNext) == .arrowRight)
    }

    @Test func decodingAMissingCommandFallsBackToItsDefault() throws {
        // A record from before `cardProject` existed: the key is simply absent.
        let json = #"{"stepAction":"Q"}"#
        let bindings = try JSONDecoder().decode(KeyBindings.self, from: Data(json.utf8))
        #expect(bindings.key(for: .stepAction) == .letter("Q"))
        #expect(bindings.key(for: .cardProject) == .letter("P"))
    }

    @Test func decodingAnUnknownCommandIsIgnoredRatherThanThrowing() throws {
        // `futureDeckCommand` does not exist in this build; the rest of the record still loads.
        let json = #"{"stepAction":"Q","futureDeckCommand":"Z"}"#
        let bindings = try JSONDecoder().decode(KeyBindings.self, from: Data(json.utf8))
        #expect(bindings.key(for: .stepAction) == .letter("Q"))
    }

    @Test func decodingGarbageNeverCrashesTheApp() {
        let json = "not json at all"
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(KeyBindings.self, from: Data(json.utf8))
        }
    }

    // MARK: Legends

    @Test func step1LegendReadsAsTheStyleGuideSpellsIt() {
        let titles: [KeyCommand: String] = [
            .stepAction: "Action",
            .stepKnowledge: "Knowledge / List",
            .stepTrash: "Trash",
            .stepDefer: "Defer to review",
        ]
        let legend = KeyBindings.defaults.legendString(for: .inboxStep1, titles: titles)
        #expect(legend == "A Action · K Knowledge / List · X Trash · D Defer to review")
    }

    @Test func knowledgeListLegendTakesFavouriteNamesAsInput() {
        let titles: [KeyCommand: String] = [
            .listKnowledge: "Knowledge",
            .listSlot2: "Read",
            .listSlot3: "Watch",
            .listSlot4: "Wish",
            .listMore: "More…",
        ]
        let legend = KeyBindings.defaults.legendString(for: .knowledgeListCard, titles: titles)
        #expect(legend == "1 Knowledge · 2 Read · 3 Watch · 4 Wish · 0 More…")
    }

    @Test func deckLegendListsTheFourChoices() {
        let titles: [KeyCommand: String] = [
            .deckKeep: "Keep", .deckDemote: "Demote", .deckPromote: "Promote", .deckTrash: "Trash",
        ]
        let legend = KeyBindings.defaults.legendString(for: .reviewDeck, titles: titles)
        #expect(legend == "K Keep · D Demote · P Promote · T Trash")
    }

    @Test func legendReflectsARebind() throws {
        var bindings = KeyBindings.defaults
        try bindings.rebind(.stepAction, to: .letter("B"))
        let titles: [KeyCommand: String] = [
            .stepAction: "Action", .stepKnowledge: "Knowledge / List",
            .stepTrash: "Trash", .stepDefer: "Defer to review",
        ]
        let legend = bindings.legendString(for: .inboxStep1, titles: titles)
        #expect(legend == "B Action · K Knowledge / List · X Trash · D Defer to review")
    }

    @Test func legendOmitsACommandWithNoTitle() {
        // Only three of eight favourite slots filled — matches a device with three favourites.
        let titles: [KeyCommand: String] = [.listSlot2: "Read", .listSlot3: "Watch"]
        let entries = KeyBindings.defaults.legend(for: .knowledgeListCard, titles: titles)
        #expect(entries.map(\.label) == ["Read", "Watch"])
    }

    // MARK: KeyStroke display

    @Test func keyStrokeDisplayCoversLettersDigitsAndArrows() {
        #expect(KeyStroke.letter("a").display == "A")
        #expect(KeyStroke.letter("Z").display == "Z")
        #expect(KeyStroke.digit(0).display == "0")
        #expect(KeyStroke.digit(9).display == "9")
        #expect(KeyStroke.arrowLeft.display == "←")
        #expect(KeyStroke.arrowRight.display == "→")
        #expect(KeyStroke.shiftedDigit(2).display == "⇧2")
    }
}
