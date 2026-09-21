import Foundation
import GTDModel

/// The iPhone Lists tab's push stack (STYLEGUIDE §4.2 L5): lists home → one list's items → the
/// item editor. Two levels, so a single `[NoteID]` path (as `AppRouter.nextPath` uses for Next)
/// is not enough — this names both. `App/AppRouter` owns the `[ListsRoute]` array; this type has
/// no view and no SwiftUI dependency so it stays Linux-compilable.
public enum ListsRoute: Hashable, Sendable {
    case list(String)
    case item(NoteID)
}
