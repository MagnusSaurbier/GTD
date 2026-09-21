import Testing
import Foundation
import GTDAppCore
@testable import FeatureSettings

/// The Keyboard pane's grouping and key-capture helpers (R-10, N7, STYLEGUIDE §4.5). The
/// rebind/conflict semantics themselves are `GTDAppCoreTests/KeyBindingsTests`' job — this only
/// covers what `KeyBindingsEditing` adds on top for the pane.
struct KeyBindingsEditingTests {
    @Test func screensCoverEveryCommandExactlyOnce() {
        let grouped = KeyBindingsEditing.screens.flatMap(\.commands)
        #expect(Set(grouped) == Set(KeyCommand.allCases))
        #expect(grouped.count == KeyCommand.allCases.count)
    }

    @Test func screensPreserveDeclarationOrderOfBothScreenAndCommand() {
        let screens = KeyBindingsEditing.screens.map(\.screen)
        #expect(screens == KeyScreen.allCases)
        let inboxStep1 = KeyBindingsEditing.screens.first { $0.screen == .inboxStep1 }?.commands
        #expect(inboxStep1 == [.stepAction, .stepKnowledge, .stepTrash, .stepDefer])
    }

    @Test func everyCommandGroupsUnderItsOwnScreen() {
        for (screen, commands) in KeyBindingsEditing.screens {
            for command in commands { #expect(command.screen == screen) }
        }
    }

    @Test func strokeForCharacterUppercasesLetters() {
        #expect(KeyBindingsEditing.stroke(forCharacter: "q") == .letter("Q"))
        #expect(KeyBindingsEditing.stroke(forCharacter: "Q") == .letter("Q"))
    }

    @Test func strokeForCharacterAcceptsDigits() {
        #expect(KeyBindingsEditing.stroke(forCharacter: "7") == .digit(7))
    }

    @Test func strokeForCharacterRejectsPunctuation() {
        #expect(KeyBindingsEditing.stroke(forCharacter: "!") == nil)
        #expect(KeyBindingsEditing.stroke(forCharacter: " ") == nil)
    }

    @Test func rebindingSucceedsForAFreeKey() {
        let result = KeyBindingsEditing.rebinding(.stepAction, to: .letter("Q"), in: .defaults)
        guard case let .success(bindings) = result else { #expect(Bool(false)); return }
        #expect(bindings.key(for: .stepAction) == .letter("Q"))
    }

    @Test func rebindingReportsAFixedKey() {
        let result = KeyBindingsEditing.rebinding(.stepAction, to: .escape, in: .defaults)
        #expect(result == .failure(.fixed))
    }

    @Test func rebindingReportsAReservedKeyOnTheActionCardOnly() {
        let reserved = KeyBindingsEditing.rebinding(.cardWaiting, to: .digit(3), in: .defaults)
        #expect(reserved == .failure(.reserved))
        // The same digit is not reserved on a screen that is not the action card.
        let elsewhere = KeyBindingsEditing.rebinding(.stepAction, to: .digit(3), in: .defaults)
        #expect(elsewhere != .failure(.reserved))
    }

    @Test func rebindingReportsADuplicateWithTheConflictingCommand() {
        // `.stepKnowledge` already owns `K` by default; binding `.stepAction` to it collides.
        let result = KeyBindingsEditing.rebinding(.stepAction, to: .letter("K"), in: .defaults)
        #expect(result == .failure(.duplicate(.stepKnowledge)))
    }
}
