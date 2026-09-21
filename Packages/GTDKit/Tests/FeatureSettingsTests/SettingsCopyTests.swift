import Testing
import Foundation
import GTDModel
import GTDAppCore
import DesignSystem
@testable import FeatureSettings

/// The wording `SettingsCopy` supplies on top of `DesignSystem.Copy` for the Lists and Keyboard
/// sections — pinned the same way `CopyWordingTests` pins `DesignSystem.Copy`.
struct SettingsCopyTests {
    @Test func messageForInvalidPassesTheReducersOwnReason() {
        #expect(SettingsCopy.message(for: .invalid("A list name is required"))
            == "A list name is required")
    }

    @Test func messageForTitleCollisionNamesTheList() {
        #expect(SettingsCopy.message(for: .titleCollision("Read")).contains("Read"))
    }

    @Test func removeListMessageCountsItemsAndPluralises() {
        #expect(SettingsCopy.removeListMessage(name: "Read", itemCount: 0).contains("empty"))
        let one = SettingsCopy.removeListMessage(name: "Read", itemCount: 1)
        #expect(one.contains("1 item") && !one.contains("1 items"))
        let many = SettingsCopy.removeListMessage(name: "Read", itemCount: 4)
        #expect(many.contains("4 items"))
    }

    @Test func rebindErrorMessagesAreDistinctAndInline() {
        let fixed = SettingsCopy.message(for: .fixed)
        let reserved = SettingsCopy.message(for: .reserved)
        let duplicate = SettingsCopy.message(for: .duplicate(.stepKnowledge))
        #expect(fixed != reserved)
        #expect(duplicate == Copy.alreadyUsedBy(Copy.knowledgeOrList))
    }

    @Test func commandTitleUsesTheCanonicalWordForFixedCommands() {
        #expect(SettingsCopy.commandTitle(.stepAction) == Copy.actionKind)
        #expect(SettingsCopy.commandTitle(.cardWaiting) == Copy.waiting)
        #expect(SettingsCopy.commandTitle(.deckKeep) == Copy.keep)
        #expect(SettingsCopy.commandTitle(.deckTrash) == Copy.trash)
    }

    @Test func commandTitleLabelsFavouriteSlotsByPosition() {
        #expect(SettingsCopy.commandTitle(.listSlot2) == "List slot 2")
        #expect(SettingsCopy.commandTitle(.listSlot9) == "List slot 9")
    }

    @Test func screenTitlesAreAllDistinct() {
        let titles = KeyScreen.allCases.map(SettingsCopy.screenTitle)
        #expect(Set(titles).count == titles.count)
    }
}
