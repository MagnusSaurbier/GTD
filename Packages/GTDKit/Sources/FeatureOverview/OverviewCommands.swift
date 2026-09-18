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
