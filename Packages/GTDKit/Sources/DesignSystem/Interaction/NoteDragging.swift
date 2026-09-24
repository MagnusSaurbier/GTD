#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import GTDModel
import GTDAppCore

/// One note being dragged between categories (E3): a row in Next, Someday, Waiting or Deferred
/// picked up and dropped on a sidebar section or a project row. The payload is the `NoteID`
/// alone — what happens on the drop is decided by `MovePlan`, never by the row.
///
/// The type is app-private (`exportedAs`, declared in the app's `Info.plist` under
/// `UTExportedTypeDeclarations`), so a row dragged into another app carries nothing and nothing
/// from another app can be dropped on a section.
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
/// (`OverviewView`, `PhoneShell`); rows and drop targets only read it. `nil` means the
/// screen has nowhere to move a note to, and the rows show no `Move to…`.
public struct MoveNoteHandler {
    /// Whether dropping `id` on `destination` would do anything — the drop highlight.
    public let accepts: @MainActor (NoteID, MoveDestination) -> Bool
    /// Do it: move at once, or open the dialogue the destination needs.
    public let move: @MainActor (NoteID, MoveDestination) -> Void
    /// A row was picked up. The drop targets read `currentDrag` while it hovers, because the
    /// hover callback of a drop target carries no payload — only the drop itself does.
    public let beginDrag: @MainActor (NoteID) -> Void
    public let currentDrag: @MainActor () -> NoteID?

    public init(
        accepts: @escaping @MainActor (NoteID, MoveDestination) -> Bool,
        move: @escaping @MainActor (NoteID, MoveDestination) -> Void,
        beginDrag: @escaping @MainActor (NoteID) -> Void,
        currentDrag: @escaping @MainActor () -> NoteID?
    ) {
        self.accepts = accepts
        self.move = move
        self.beginDrag = beginDrag
        self.currentDrag = currentDrag
    }
}

extension EnvironmentValues {
    @Entry public var moveNote: MoveNoteHandler? = nil
}

extension View {
    /// Makes a list row a drag source for its note: a mouse drag on the Mac, a long press then
    /// drag on iOS. `onDrag` rather than `draggable`, because it is the one that reliably
    /// starts a drag from a row of a selectable `List` on macOS, and because it has a start
    /// hook — the drop targets need to know *which* note hovers to light up only where the
    /// drop would do something.
    public func draggableNote(_ id: NoteID) -> some View {
        modifier(NoteDragSource(id: id))
    }

    /// Makes a view a drop target for dragged notes. `isTargeted` follows the hover; `perform`
    /// gets the note's id on the drop. `onDrop` rather than `dropDestination` for the same
    /// reason as above: it is the API that works on the rows of a macOS sidebar `List`.
    public func noteDropTarget(
        isTargeted: Binding<Bool>,
        perform: @escaping @MainActor (NoteID) -> Void
    ) -> some View {
        modifier(NoteDropTarget(isTargeted: isTargeted, perform: perform))
    }
}

private struct NoteDragSource: ViewModifier {
    let id: NoteID
    @Environment(\.moveNote) private var moveNote

    func body(content: Content) -> some View {
        content.onDrag {
            moveNote?.beginDrag(id)
            let provider = NSItemProvider()
            provider.register(NoteDragItem(id))
            return provider
        }
    }
}

private struct NoteDropTarget: ViewModifier {
    @Binding var isTargeted: Bool
    let perform: @MainActor (NoteID) -> Void
    @Environment(\.moveNote) private var moveNote

    func body(content: Content) -> some View {
        content.onDrop(of: [NoteDragItem.contentType], isTargeted: $isTargeted) { providers in
            // The note that was picked up in this window is known already; the payload is the
            // fallback for a drag that did not start here.
            if let id = moveNote?.currentDrag() {
                perform(id)
                return true
            }
            guard let provider = providers.first,
                  provider.hasItemConformingToTypeIdentifier(NoteDragItem.contentType.identifier)
            else { return false }
            _ = provider.loadTransferable(type: NoteDragItem.self) { result in
                guard case let .success(item) = result else { return }
                Task { @MainActor in perform(item.id) }
            }
            return true
        }
    }
}

/// A list row that takes dropped notes: the drop target plus the light-blue row tint
/// (`Color.dropTargetWash`) while a note that the row would accept hovers over it. A row that
/// would refuse the drop (the note is already there) does not light up and ignores the drop.
/// Rows of the sidebar and of the Projects list wrap themselves in it.
public struct NoteDropRow<Content: View>: View {
    private let destination: MoveDestination
    private let content: Content
    @Environment(\.moveNote) private var moveNote
    @State private var isTargeted = false

    public init(destination: MoveDestination, @ViewBuilder content: () -> Content) {
        self.destination = destination
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Radius.cell, style: .continuous)
                    .fill(isLit ? Color.dropTargetWash : Color.clear)
                    .padding(.horizontal, -Spacing.xs))
            .listRowBackground(isLit ? Color.dropTargetWash : nil)
            .noteDropTarget(isTargeted: $isTargeted) { id in
                guard let moveNote, moveNote.accepts(id, destination) else { return }
                moveNote.move(id, destination)
            }
    }

    private var isLit: Bool {
        guard isTargeted, let moveNote else { return false }
        guard let id = moveNote.currentDrag() else { return true }
        return moveNote.accepts(id, destination)
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
