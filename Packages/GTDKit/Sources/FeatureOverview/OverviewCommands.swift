#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

/// The window's keyboard map in the menu bar (STYLEGUIDE §4.5: every shortcut is also a menu
/// item). The app shell (T40) installs it next to the `WindowGroup` and hands the same
/// `OverviewNavigation` to `OverviewView(navigation:)`.
///
/// `⌘F` is **not** here: focusing the filter field happens inside the window, so `OverviewView`
/// owns that one. `⌘N` only raises `OverviewNavigation.isCaptureRequested` — capture writes
/// through `GTDVault`, which feature targets must not import (ARCHITECTURE §2).
public struct OverviewCommands: Commands {
    private let navigation: OverviewNavigation
    private let model: AppModel

    public init(navigation: OverviewNavigation, model: AppModel) {
        self.navigation = navigation
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(model.undoLabel ?? Copy.undo) {
                Task { await model.undo() }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(model.undoLabel == nil)
        }

        CommandGroup(after: .newItem) {
            Button(OverviewCopy.newCapture) {
                navigation.isCaptureRequested = true
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(Copy.processInbox) {
                navigation.isProcessingInbox = true
            }
            .keyboardShortcut("i", modifiers: .command)
        }

        // STYLEGUIDE §4.5 — fixed (not rebindable) shortcuts: move the action open in the
        // detail column to Next / Someday. Every transition into Next goes through
        // `AppModel.perform`, so a cap or `missingFields` refusal reaches the shell's one alert
        // instead of failing silently (deliverable 1, R-3).
        CommandGroup(after: .toolbar) {
            Button(OverviewCopy.moveToNext) {
                guard let id = navigation.openAction else { return }
                Task { await model.perform(.setStatus(id, .next, waiting: nil)) }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(navigation.openAction == nil)

            Button(OverviewCopy.moveToSomeday) {
                guard let id = navigation.openAction else { return }
                Task { await model.perform(.setStatus(id, .someday, waiting: nil)) }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(navigation.openAction == nil)
        }

        CommandMenu(OverviewCopy.go) {
            ForEach(Array(SidebarItem.counted.enumerated()), id: \.element) { index, item in
                Button(item.title) {
                    navigation.select(item)
                }
                .keyboardShortcut(OverviewCommands.digits[index], modifiers: .command)
            }
            Divider()
            ForEach(SidebarItem.flows, id: \.self) { item in
                Button(item.title) { navigation.select(item) }
            }
        }
    }

    /// `⌘1…⌘7`, in the order of `SidebarItem.counted`.
    private static let digits: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7"]
}
#endif
