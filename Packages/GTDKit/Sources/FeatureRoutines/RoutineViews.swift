#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures

/// One big button per routine with its time and today's progress (R3).
/// **Owned by T24** — this is the compiling shell.
public struct RoutinesHomeView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        List(model.snapshot.routines, id: \.id) { routine in
            Label {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(routine.title).font(Typo.body)
                    if let time = routine.time {
                        Text(time.hhmm).font(Typo.counter).foregroundStyle(Color.textSecondary)
                    }
                }
            } icon: {
                Image(systemName: Symbols.routine(title: routine.title))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .navigationTitle(Copy.routine)
    }
}

/// Step-by-step routine card (R2). **Owned by T24.**
public struct RoutineRunnerView: View {
    private let routine: NoteID
    private let onFinished: () -> Void
    @Environment(AppModel.self) private var model

    public init(routine: NoteID, onFinished: @escaping () -> Void) {
        self.routine = routine
        self.onFinished = onFinished
    }

    public var body: some View {
        let run = RoutineRun(model: model, routine: routine)
        VStack(spacing: Spacing.l) {
            if let run, let step = run.currentStep {
                ItemCard {
                    Text(run.progressText).font(Typo.counter).foregroundStyle(Color.textSecondary)
                    Text(step.title).font(Typo.cardText).foregroundStyle(Color.ink)
                    ForEach(step.substeps, id: \.self) { substep in
                        Text(substep).font(Typo.body).foregroundStyle(Color.textSecondary)
                    }
                }
                GlassActionBar {
                    Button(Copy.skip) { Task { await run.log(.skipped) } }
                    Button(Copy.done) { Task { await run.log(.done) } }
                }
            } else {
                ContentUnavailableView(
                    Copy.routineDone(model.snapshot.routine(routine)?.title ?? ""),
                    systemImage: Symbols.done)
                Button(Copy.done, action: onFinished)
            }
        }
        .padding(Spacing.screenMargin)
        .background(Color.surfaceGrouped)
    }
}

#Preview {
    NavigationStack {
        RoutinesHomeView()
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}
#endif
