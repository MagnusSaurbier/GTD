import Foundation
import GTDModel
import GTDAppCore
import DesignSystem

/// Strings this target needs that `DesignSystem.Copy` does not carry, plus the wording of its
/// own refusals — same pattern as `FeatureProjects.ProjectsCopy` / `FeatureReview.ReviewCopy`.
/// Feature code never inlines a user-facing string.
enum SettingsCopy {

    // MARK: Lists (L2, R-5, I4b)

    static let addList = "Add a list"
    static let removeList = "Remove"
    static let removeListTitle = "Remove list?"

    /// The `confirmationDialog` body — names the list and how many items travel with it (R-5:
    /// "takes items with it"). Removing a list is undoable, but the bulk of what moves is why
    /// this one destructive action still asks first (ARCHITECTURE §6).
    static func chooseListIcon(_ name: String) -> String { "Choose icon for \(name)" }

    static func removeListMessage(name: String, itemCount: Int) -> String {
        itemCount == 0
            ? "\"\(name)\" is empty. It moves to \(Copy.trash) and can be undone."
            : "\"\(name)\" and its \(itemCount) item\(itemCount == 1 ? "" : "s") "
                + "move to \(Copy.trash). This can be undone."
    }

    static let favourites = "Favourites"
    static let addFavourite = "Add favourite…"
    static let macOnlyFavourite = "Mac only"
    static let favouritesFooter =
        "Shown in the inbox navbar, in this order. The iPhone shows the first four; "
            + "the Mac shows up to eight."

    /// `ListsEditing.FavouriteError.limitReached` — the storage cap, not a per-platform one.
    static func favouritesFull(_ limit: Int) -> String {
        "Favourites are full (\(limit)) — remove one first."
    }

    /// The reducer's own `GTDError.invalid`/`.titleCollision` wording is already
    /// user-presentable (`Reducer.Message`); this only supplies this screen's own phrasing for
    /// the cases that need it (STYLEGUIDE §4.3: inline, never an alert).
    static func message(for error: GTDError) -> String {
        switch error {
        case let .invalid(reason): reason
        case let .titleCollision(name): "A list named \"\(name)\" already exists."
        case .notFound: "That list is gone."
        case .nextCapReached, .missingFields: Copy.actionFailed
        }
    }

    // MARK: Keyboard (R-10, N7, STYLEGUIDE §4.5) — Mac only

    static let keyboardSection = "Keyboard"
    static let resetToDefaults = "Reset to defaults"
    static let pressAKey = "Press a key…"
    static let keyboardFooter = "Esc, Tab, \(KeyStroke.commandZ.display) and "
        + "\(KeyStroke.commandReturn.display) are fixed and cannot be reassigned."

    static func screenTitle(_ screen: KeyScreen) -> String {
        switch screen {
        case .inboxStep1: "Inbox — step 1"
        case .actionCard: "Inbox — action card"
        case .knowledgeListCard: "Inbox — Knowledge / List card"
        case .reviewDeck: "Weekly review deck"
        }
    }

    /// The command's name, sourced from `DesignSystem.Copy` wherever the command already has a
    /// canonical word (STYLEGUIDE §4.5: "the command's name from Copy"). The favourite-list
    /// slots (`listSlot2`…`listSlot9`) have no fixed name — which list fills a slot depends on
    /// the user's favourites order — so they are labelled by position instead.
    static func commandTitle(_ command: KeyCommand) -> String {
        switch command {
        case .stepAction: return Copy.actionKind
        case .stepKnowledge: return Copy.knowledgeOrList
        case .stepTrash: return Copy.trash
        case .stepDefer: return Copy.deferToReview
        case .cardSomeday: return Copy.someday
        case .cardNext: return Copy.next
        case .cardWaiting: return Copy.waiting
        case .cardProject: return Copy.project
        case .listKnowledge: return Copy.knowledge
        case .listMore: return Copy.more
        case .deckKeep: return Copy.keep
        case .deckDemote: return Copy.demote
        case .deckPromote: return Copy.promote
        case .deckTrash: return Copy.trash
        default:
            guard let slot = KeyCommand.knowledgeListFavouriteSlots.firstIndex(of: command)
            else { return command.rawValue }
            return "List slot \(slot + 2)"
        }
    }

    /// `KeyBindings.RebindError` — inline, never an alert (STYLEGUIDE §4.5).
    static func message(for error: KeyBindings.RebindError) -> String {
        switch error {
        case .fixed: "That key is fixed and can't be reassigned."
        case .reserved: "That key is reserved on the action card."
        case let .duplicate(command): Copy.alreadyUsedBy(commandTitle(command))
        }
    }
}
