#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures

/// The In progress board (#87): In progress | Agent | Review, filtered by context and project.
///
/// Side by side where the width allows (the Mac's list column, widened for this section);
/// otherwise — the iPhone, a narrow Mac column — one list with a section per column. Every
/// card is draggable onto another column (or a sidebar section), and its context menu has the
/// same moves (`Move to column`, `Move to…`), so the iPhone and VoiceOver reach every one
/// (STYLEGUIDE §8). A move goes through the host's `moveNote` handler (`MovePlan`), so a card
/// entering In progress from Agent/Review is asked what Next asks, and the cap holds.
public struct InProgressBoardView: View {
    private let selection: NoteID?
    private let onOpen: (NoteID) -> Void
    @Environment(AppModel.self) private var model

    public init(selection: NoteID? = nil, onOpen: @escaping (NoteID) -> Void) {
        self.selection = selection
        self.onOpen = onOpen
    }

    public var body: some View {
        InProgressBoardContent(model: model, selection: selection, onOpen: onOpen)
    }
}

/// Owns the `InProgressBoardModel` with stable identity, so the filters survive every snapshot
/// update (same pattern as `NextListContent`).
private struct InProgressBoardContent: View {
    let selection: NoteID?
    let onOpen: (NoteID) -> Void
    @State private var board: InProgressBoardModel
    @Environment(AppModel.self) private var model
    @Environment(\.moveNote) private var moveNote
    @State private var errorMessage: String?

    /// A column narrower than this squeezes the card titles to a word per line.
    private static let columnMinWidth: CGFloat = 160

    init(model: AppModel, selection: NoteID?, onOpen: @escaping (NoteID) -> Void) {
        self.selection = selection
        self.onOpen = onOpen
        _board = State(initialValue: InProgressBoardModel(model: model))
    }

    var body: some View {
        Group {
            if board.isEmpty {
                ContentUnavailableView(
                    board.emptyStateTitle,
                    systemImage: Symbols.inProgress,
                    description: Text(board.emptyStateBody))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ViewThatFits(in: .horizontal) {
                    sideBySide
                    stacked
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                filterBar
                Divider()
            }
        }
        .pinnedScreenTitle(Copy.inProgress)
        .alert(
            errorMessage ?? "",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button(Copy.done) { errorMessage = nil }
        }
    }

    // MARK: - Filters

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(Copy.contextFilterHeader).font(Typo.meta).foregroundStyle(Color.textSecondary)
            ContextChipGroup(
                contexts: board.availableContexts,
                selection: Binding(get: { board.contexts }, set: { board.setContexts($0) }))
            HStack(spacing: Spacing.m) {
                Text(Copy.projectFilterHeader).font(Typo.meta).foregroundStyle(Color.textSecondary)
                Menu(board.projectFilterTitle) {
                    Button(Copy.allProjects) { board.setProject(nil) }
                    if !board.availableProjects.isEmpty { Divider() }
                    ForEach(board.availableProjects) { choice in
                        Button(choice.title) { board.setProject(choice.id) }
                    }
                }
                .fixedSize()
                Spacer(minLength: 0)
                if board.isFiltered {
                    Button(Copy.clearFilters) { board.clearFilters() }
                        .buttonStyle(.plain)
                        .font(Typo.meta)
                        .foregroundStyle(Color.gtdAccent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.s)
    }

    // MARK: - Layouts

    /// Three columns next to each other — the kanban proper.
    private var sideBySide: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            ForEach(board.columns) { column in
                BoardColumnView(column: column) {
                    ScrollView {
                        LazyVStack(spacing: Spacing.s) {
                            if column.actions.isEmpty {
                                emptyColumn
                            }
                            ForEach(column.actions) { action in
                                card(action)
                                    .padding(.horizontal, Spacing.s)
                                    .background(
                                        Color.surfaceCard,
                                        in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                                    .overlay {
                                        if selection == action.id {
                                            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                                                .stroke(Color.gtdAccent, lineWidth: 2)
                                        }
                                    }
                            }
                        }
                        .padding(Spacing.s)
                    }
                } onDrop: { id in drop(id, on: column) }
                .frame(minWidth: Self.columnMinWidth, idealWidth: Self.columnMinWidth, maxWidth: .infinity)
            }
        }
        .padding(Spacing.m)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// One list, a section per column — the iPhone, and a Mac column too narrow for three.
    private var stacked: some View {
        List {
            ForEach(board.columns) { column in
                Section {
                    if column.actions.isEmpty {
                        emptyColumn
                    }
                    ForEach(column.actions) { action in
                        card(action)
                            .listRowBackground(selection == action.id ? Color.dropTargetWash.opacity(0.5) : nil)
                    }
                } header: {
                    NoteDropRow(destination: column.destination) {
                        columnHeader(column)
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private var emptyColumn: some View {
        Text(Copy.emptyColumn)
            .font(Typo.meta)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.s)
    }

    private func columnHeader(_ column: BoardColumn) -> some View {
        HStack(spacing: Spacing.s) {
            Label(column.title, systemImage: Symbols.board(column.status))
                .font(Typo.sectionHeader)
            Text("\(column.actions.count)")
                .font(Typo.counter)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func card(_ action: Action) -> some View {
        ActionRow(
            action: action,
            projectTitle: board.projectTitle(for: action),
            badges: board.badges(for: action),
            onComplete: { perform(.complete(action.id)) })
            .contentShape(Rectangle())
            .draggableNote(action.id)
            .onTapGesture { onOpen(action.id) }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen(action.id) }
            .contextMenu {
                Button(Copy.done) { perform(.complete(action.id)) }
                Divider()
                Menu(Copy.moveToColumn) {
                    ForEach(board.moveTargets(for: action), id: \.self) { status in
                        Button {
                            move(action.id, to: status)
                        } label: {
                            Label(Copy.status(status), systemImage: Symbols.board(status))
                        }
                    }
                }
                MoveToMenu(id: action.id)
            }
    }

    // MARK: - Moves

    private func drop(_ id: NoteID, on column: BoardColumn) {
        guard let moveNote else {
            perform(.setStatus(id, column.status, waiting: nil))
            return
        }
        guard moveNote.accepts(id, column.destination) else { return }
        moveNote.move(id, column.destination)
    }

    private func move(_ id: NoteID, to status: ActionStatus) {
        guard let destination = InProgressBoardModel.destination(for: status) else { return }
        if let moveNote {
            moveNote.move(id, destination)
        } else {
            perform(.setStatus(id, status, waiting: nil))
        }
    }

    private func perform(_ command: GTDCommand) {
        Task {
            do {
                try await model.send(command)
            } catch let GTDError.missingFields(fields) {
                errorMessage = Copy.missingFields(fields)
            } catch GTDError.nextCapReached {
                errorMessage = Copy.capSheetTitle
            } catch {
                errorMessage = Copy.actionFailed
            }
        }
    }
}

/// One column of the side-by-side board: header with count, the cards, and the drop target
/// that tints while a card it would accept hovers over it.
private struct BoardColumnView<Cards: View>: View {
    let column: BoardColumn
    @ViewBuilder let cards: () -> Cards
    let onDrop: (NoteID) -> Void
    @Environment(\.moveNote) private var moveNote
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Label(column.title, systemImage: Symbols.board(column.status))
                    .font(Typo.sectionHeader)
                Text("\(column.actions.count)")
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, Spacing.s)
            .padding(.top, Spacing.s)
            cards()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            isLit ? Color.dropTargetWash : Color.fillQuiet,
            in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .noteDropTarget(isTargeted: $isTargeted) { onDrop($0) }
    }

    private var isLit: Bool {
        guard isTargeted, let moveNote else { return false }
        guard let id = moveNote.currentDrag() else { return true }
        return moveNote.accepts(id, column.destination)
    }
}

#Preview("In progress board") {
    InProgressBoardView(onOpen: { _ in })
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
        .frame(width: 720, height: 600)
}
#endif
