#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures

/// The full inbox-processing session (I1–I6). **Owned by T20** — this is the compiling shell.
public struct InboxProcessingView: View {
    private let onFinished: () -> Void
    @Environment(AppModel.self) private var model

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        VStack(spacing: Spacing.l) {
            if let item = Rules.inboxQueue(model.snapshot).first {
                ItemCard {
                    Text(item.text).font(Typo.cardText).foregroundStyle(Color.ink)
                }
            } else {
                ContentUnavailableView(Copy.emptyInboxTitle, systemImage: Symbols.inbox)
            }
        }
        .padding(Spacing.screenMargin)
        .background(Color.surfaceGrouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(Copy.done, action: onFinished)
            }
        }
    }
}

/// Home-screen entry point: shows the queue count and starts a session (I1).
public struct InboxStartButton: View {
    private let action: () -> Void
    @Environment(AppModel.self) private var model

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(
                "\(Copy.processInbox) (\(Rules.inboxQueue(model.snapshot).count))",
                systemImage: Symbols.inbox)
        }
        .disabled(Rules.inboxQueue(model.snapshot).isEmpty)
    }
}

#Preview {
    InboxProcessingView(onFinished: {})
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
}
#endif
