import Foundation

/// The two contexts the Knowledge/List navbar renders in (STYLEGUIDE §3.6): iPhone caps
/// favourites at four slots, Mac at eight.
public enum NavbarPlatform: Sendable, Equatable, CaseIterable {
    case iPhone
    case mac

    /// "at most four on iPhone, eight on Mac".
    public var favouriteLimit: Int {
        switch self {
        case .iPhone: 4
        case .mac: 8
        }
    }
}

/// One fixed-position slot of the Knowledge/List navbar (STYLEGUIDE §3.6): `Knowledge` first,
/// then the favourite lists **in the order set in Settings**, then `More…`. "Positions never
/// reorder by use" — this type only ever appends, it never sorts by recency or count.
public struct NavbarSlot: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case knowledge
        case list(name: String)
        case more
    }

    public let kind: Kind
    /// The Mac key legend index (§3.6's table): `1` for Knowledge, `2`…`9` for favourites in
    /// order, `0` for `More…`.
    public let keyIndex: Int

    public init(kind: Kind, keyIndex: Int) {
        self.kind = kind
        self.keyIndex = keyIndex
    }

    public var id: String {
        switch kind {
        case .knowledge: "knowledge"
        case let .list(name): "list:\(name)"
        case .more: "more"
        }
    }

    /// `1`…`9`, or `0` for `More…` — what the Mac key legend shows next to the slot.
    public var keyLabel: String { String(keyIndex) }
}

/// Computes the navbar's fixed slots from the user's favourite lists and the platform limit.
/// Pure and Linux-testable — the SwiftUI navbar (`KnowledgeListNavbar`) is a thin loop over this.
public enum NavbarLayout {
    /// `favourites` is already in the user's chosen order (`GTDConfig.favouriteLists`, or the
    /// alphabetical default `Rules.favouriteLists` derives when nothing has been chosen) — this
    /// function only clips it to the platform limit and assigns key indices; it never reorders
    /// and never drops `Knowledge`/`More…`, even when there are zero favourites.
    public static func slots(favourites: [String], platform: NavbarPlatform) -> [NavbarSlot] {
        let shown = Array(favourites.prefix(platform.favouriteLimit))
        var slots: [NavbarSlot] = [NavbarSlot(kind: .knowledge, keyIndex: 1)]
        for (offset, name) in shown.enumerated() {
            slots.append(NavbarSlot(kind: .list(name: name), keyIndex: offset + 2))
        }
        slots.append(NavbarSlot(kind: .more, keyIndex: 0))
        return slots
    }
}
