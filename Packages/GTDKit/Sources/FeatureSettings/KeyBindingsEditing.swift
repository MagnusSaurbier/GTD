import Foundation
import GTDAppCore

/// Pure helpers for the Settings › Keyboard pane (R-10, N7, STYLEGUIDE §4.5): grouping
/// `KeyCommand`s by `KeyScreen` for "one row per command, grouped by screen", and turning a
/// captured key press into the `KeyStroke` a rebind is attempted with. The rebind/refusal logic
/// itself already lives in `GTDAppCore.KeyBindings.rebind(_:to:)` — this only prepares its inputs
/// and outputs for a view. Mac only in the UI; this file has no SwiftUI import, so it is
/// Linux-tested like every other model here.
public enum KeyBindingsEditing {
    /// `KeyScreen.allCases` in declaration order, each paired with its commands in
    /// `KeyCommand`'s declaration order — the same order STYLEGUIDE's own legends list them in.
    public static var screens: [(screen: KeyScreen, commands: [KeyCommand])] {
        KeyScreen.allCases.map { screen in (screen, KeyCommand.allCases.filter { $0.screen == screen }) }
    }

    /// A captured key-recorder character as the `KeyStroke` it would be bound to: a letter
    /// (normalised to uppercase by `KeyStroke.letter`) or a single digit `0`…`9`. Everything
    /// else (punctuation, function keys, modifiers alone) is not a bindable stroke here — the
    /// arrows are their own fixed constants (`KeyStroke.arrowLeft`/`.arrowRight`), which the view
    /// reports directly since SwiftUI's `KeyPress` already distinguishes them from characters.
    public static func stroke(forCharacter character: Character) -> KeyStroke? {
        if let digit = character.wholeNumberValue, character.isNumber, (0...9).contains(digit) {
            return .digit(digit)
        }
        if character.isLetter {
            return .letter(character)
        }
        return nil
    }

    /// Attempts the rebind without throwing, so a view can hold the outcome as plain state and
    /// show the refusal inline (STYLEGUIDE §4.5: "never an alert") instead of unwinding a
    /// `do`/`catch` at the call site.
    public static func rebinding(
        _ command: KeyCommand, to key: KeyStroke, in bindings: KeyBindings
    ) -> Result<KeyBindings, KeyBindings.RebindError> {
        var next = bindings
        do {
            try next.rebind(command, to: key)
            return .success(next)
        } catch {
            return .failure(error)
        }
    }
}
