#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import GTDModel
import GTDAppCore

/// One note being dragged between categories (E3): a row in Next, Someday, Waiting or Deferred
/// picked up and dropped on a sidebar section or a project row. The payload is the `NoteID`
/// alone — what happens on the drop is decided by `MovePlan`, never by the row.
///
/// The type is app-private (`exportedAs`), so a row dragged into another app carries nothing
/// and nothing from another app can be dropped on a section.
public struct NoteDragItem: Codable, Transferable, Sendable, Hashable {
    public static let contentType = UTType(exportedAs: "com.magnussaurbier.gtd.note")

    public let path: String

    public init(_ id: NoteID) { path = id.path }
    public var id: NoteID { NoteID(path: path) }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }
}

/// What a category drop or a `Move to…` choice does. The shell that hosts the sheets sets it
/// (`OverviewView`, `PhoneShell`); rows and sidebar sections only read it. `nil` means the
/// screen has nowhere to move a note to, and the rows show no `Move to…`.
public struct MoveNoteHandler {
    /// Whether dropping `id` on `destination` would do anything — the drop highlight.
    public let accepts: @MainActor (NoteID, MoveDestination) -> Bool
    /// Do it: move at once, or open the dialogue the destination needs.
    public let move: @MainActor (NoteID, MoveDestination) -> Void

    public init(
        accepts: @escaping @MainActor (NoteID, MoveDestination) -> Bool,
        move: @escaping @MainActor (NoteID, MoveDestination) -> Void
    ) {
        self.accepts = accepts
        self.move = move
    }
}

extension EnvironmentValues {
    @Entry public var moveNote: MoveNoteHandler? = nil
}

extension View {
    /// Makes a list row a drag source for its note. Stock `.draggable` (STYLEGUIDE "stock
    /// first"): a mouse drag on the Mac, a long press then drag on iOS.
    public func draggableNote(_ id: NoteID) -> some View {
        draggable(NoteDragItem(id))
    }

    /// Makes a view a drop target for dragged notes. `accepts` decides the highlight and
    /// whether the drop lands at all (a row that would refuse never invites the drop);
    /// `perform` gets the note's id.
    public func noteDropTarget(
        isTargeted: Binding<Bool>,
        accepts: @escaping (NoteID) -> Bool,
        perform: @escaping (NoteID) -> Void
    ) -> some View {
        dropDestination(for: NoteDragItem.self) { items, _ in
            guard let item = items.first, accepts(item.id) else { return false }
            perform(item.id)
            return true
        } isTargeted: { targeted in
            isTargeted.wrappedValue = targeted
        }
    }
}

/// A list row that takes dropped notes: the stock drop target plus the `accentWash` row tint
/// while a note hovers over it (STYLEGUIDE §2.2's drag-target tint). Rows of the sidebar and
/// of the Projects list wrap themselves in it.
public struct NoteDropRow<Content: View>: View {
    private let accepts: (NoteID) -> Bool
    private let perform: (NoteID) -> Void
    private let content: Content
    @State private var isTargeted = false

    public init(
        accepts: @escaping (NoteID) -> Bool,
        perform: @escaping (NoteID) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.accepts = accepts
        self.perform = perform
        self.content = content()
    }

    public var body: some View {
        content
            .noteDropTarget(isTargeted: $isTargeted, accepts: accepts, perform: perform)
            .listRowBackground(isTargeted ? Color.accentWash : nil)
    }
}

/// The drag's twin in a row's context menu (STYLEGUIDE §8: every gesture has a menu or key
/// route; the iPhone has no sidebar to drop on at all). Renders nothing when the screen has no
/// `moveNote` handler, so a row never offers a move it cannot make.
public struct MoveToMenu: View {
    private let id: NoteID
    @Environment(\.moveNote) private var handler

    public init(id: NoteID) { self.id = id }

    public var body: some View {
        if let handler {
            Menu(Copy.moveTo) {
                ForEach(Self.entries, id: \.destination) { entry in
                    Button {
                        handler.move(id, entry.destination)
                    } label: {
                        Label(entry.title, systemImage: entry.symbol)
                    }
                    .disabled(!handler.accepts(id, entry.destination))
                }
            }
        }
    }

    private static let entries: [(destination: MoveDestination, title: String, symbol: String)] = [
        (.next, Copy.next, Symbols.next),
        (.someday, Copy.someday, Symbols.someday),
        (.waiting, Copy.waiting, Symbols.waiting),
        (.deferred, Copy.deferred, Symbols.deferred),
        (.projects, Copy.projectEllipsis, Symbols.projects),
    ]
}
#endif
