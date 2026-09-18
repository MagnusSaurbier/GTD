#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import GTDStats
import FeatureInbox
import FeatureProjects
import GTDFixtures

/// The guided, resumable weekly review (§10). **Owned by T27** — this is the compiling shell.
public struct WeeklyReviewView: View {
    private let onFinished: () -> Void
    @Environment(AppModel.self) private var model

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        let session = ReviewSession(model: model)
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(Copy.weeklyReview).font(Typo.screenTitle)
            Text("KW \(session.state.week)").font(Typo.counter).foregroundStyle(Color.textSecondary)
            ForEach(ReviewStage.allCases, id: \.self) { stage in
                Text(String(describing: stage))
                    .font(Typo.body)
                    .foregroundStyle(stage == session.state.stage ? Color.ink : Color.textSecondary)
            }
            Spacer()
            Button(Copy.done, action: onFinished)
        }
        .padding(Spacing.screenMargin)
    }
}

/// Shown by the shell while a review is in progress.
public struct ReviewResumeBanner: View {
    private let onResume: () -> Void

    public init(onResume: @escaping () -> Void) {
        self.onResume = onResume
    }

    public var body: some View {
        HStack {
            Label(Copy.weeklyReview, systemImage: Symbols.weeklyReview)
                .font(Typo.meta)
            Spacer()
            Button("Resume", action: onResume)
        }
        .padding(Spacing.m)
        .background(Color.surfaceCard, in: Radius.tileShape)
    }
}

#Preview {
    WeeklyReviewView(onFinished: {})
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
}
#endif
