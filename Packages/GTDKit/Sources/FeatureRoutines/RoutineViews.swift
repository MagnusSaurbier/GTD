#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures

/// One big button per routine, its scheduled time and today's state (R3). Doubles as the
/// landing view for the routine notification deep link and the home-screen/Shortcut entry point:
/// tapping a routine starts it right here. **Owned by T24.**
public struct RoutinesHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var presented: RoutinePresentation?

    public init() {}

    public var body: some View {
        List(model.snapshot.routines, id: \.id) { routine in
            Button {
                presented = RoutinePresentation(id: routine.id)
            } label: {
                row(for: routine)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(Copy.routines)
        #if os(iOS)
        .fullScreenCover(item: $presented) { item in
            // `RoutineRunnerView` wraps its own `NavigationStack` for the toolbar's `Close`.
            RoutineRunnerView(routine: item.id) { presented = nil }
        }
        #else
        .sheet(item: $presented) { item in
            RoutineRunnerView(routine: item.id) { presented = nil }
                .frame(minWidth: 480, minHeight: 560)
        }
        #endif
    }

    @ViewBuilder
    private func row(for routine: Routine) -> some View {
        let progress = RoutineProgress.today(
            routine: routine, log: model.snapshot.routineLog, today: model.today())
        HStack(spacing: Spacing.m) {
            Image(systemName: Symbols.routine(title: routine.title))
                .symbolRenderingMode(.hierarchical)
                .font(Typo.rowIcon)
                .foregroundStyle(Color.ink)
                .frame(width: Spacing.xxl)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(routine.title).font(Typo.body).foregroundStyle(Color.ink)
                Text(metaLine(routine: routine, progress: progress))
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: Spacing.s)
        }
        .padding(.vertical, Spacing.rowVertical)
        .frame(minHeight: Spacing.minHitTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// `07:00 · Not started`, `07:00 · 3 of 8`, `07:00 · Finished` — omits the time when the
    /// routine has none, same "missing values are simply omitted" rule as everywhere else.
    private func metaLine(routine: Routine, progress: RoutineProgress) -> String {
        var parts: [String] = []
        if let time = routine.time { parts.append(time.hhmm) }
        parts.append(progress.homeText)
        return parts.joined(separator: " · ")
    }
}

private struct RoutinePresentation: Identifiable {
    let id: NoteID
}

/// Step-by-step routine card (R1, R2, R4). One step per screen; `Skip` / `Done` log it and
/// advance; a horizontal swipe (or Mac `S` / `⏎`) is the only gesture — no swipe filing, unlike
/// the inbox card. Finishing shows the STYLEGUIDE §5 reward screen. **Owned by T24.**
public struct RoutineRunnerView: View {
    private let routineID: NoteID
    private let onFinished: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var run: RoutineRun?
    /// Local-only tick marks on the current step's sub-steps (R2). Never logged, never sent as
    /// a command — reset whenever the step changes.
    @State private var checkedSubsteps: Set<String> = []

    public init(routine: NoteID, onFinished: @escaping () -> Void) {
        self.routineID = routine
        self.onFinished = onFinished
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let run {
                    if run.isFinished {
                        summary(run)
                    } else if let step = run.currentStep {
                        runner(run, step)
                    } else {
                        // Template has no steps at all — nothing to run.
                        ContentUnavailableView(
                            Copy.routineDone(run.routine.title), systemImage: Symbols.done)
                    }
                } else {
                    ContentUnavailableView(Copy.routine, systemImage: Symbols.routineGeneric)
                }
            }
            .padding(Spacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surfaceGrouped)
            .toolbar {
                // `Close`, not a second `Done`: the bottom `Done` completes the step, this one
                // leaves the run (progress is already logged, the run resumes later).
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.close, action: onFinished)
                }
            }
        }
        .task {
            if run == nil { run = RoutineRun(model: model, routine: routineID) }
        }
    }

    @ViewBuilder
    private func runner(_ run: RoutineRun, _ step: RoutineStep) -> some View {
        VStack(spacing: Spacing.l) {
            Spacer(minLength: 0)
            ItemCard {
                Text(run.progressText)
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
                Text(step.title)
                    .font(Typo.screenTitle)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if step.substeps.isEmpty {
                    if step.isJournaling {
                        Label(Copy.onTheRemarkable, systemImage: Symbols.journaling)
                            .symbolRenderingMode(.hierarchical)
                            .font(Typo.meta)
                            .foregroundStyle(Color.textSecondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        ForEach(step.substeps, id: \.self) { substep in
                            SubstepRow(text: substep, checked: checkedSubsteps.contains(substep)) {
                                if checkedSubsteps.contains(substep) {
                                    checkedSubsteps.remove(substep)
                                } else {
                                    checkedSubsteps.insert(substep)
                                }
                            }
                        }
                    }
                }
            }
            .gesture(backGesture(run))
            Spacer(minLength: 0)
            if run.canGoBack {
                Button {
                    run.back()
                } label: {
                    Label(Copy.back, systemImage: Symbols.back)
                        .font(Typo.body)
                        .frame(minHeight: Spacing.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.screenMargin)
            }
            // R2 "big done/skip buttons": the frame sits on the *label*, so the bordered shape
            // itself fills half the bar — on the button it only padded a small pill.
            GlassActionBar {
                Button {
                    Task { await run.log(.skipped) }
                } label: {
                    Text(Copy.skip).frame(maxWidth: .infinity, minHeight: Self.actionButtonHeight)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("s", modifiers: [])
                Button {
                    Task { await run.log(.done) }
                } label: {
                    Text(Copy.done).frame(maxWidth: .infinity, minHeight: Self.actionButtonHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.gtdAccent)
                .keyboardShortcut(.return, modifiers: [])
            }
            .font(Typo.sectionHeader)
            .buttonBorderShape(.capsule)
        }
        .animation(Motion.standard(reduceMotion: reduceMotion), value: run.index)
        .onChange(of: run.index) { checkedSubsteps = [] }
        .accessibilityAction(named: Text(Copy.skip)) { Task { await run.log(.skipped) } }
        .accessibilityAction(named: Text(Copy.done)) { Task { await run.log(.done) } }
        .accessibilityAction(named: Text(Copy.back)) { run.back() }
    }

    /// Horizontal swipe back = previous step only (no swipe filing on routine cards, R2).
    private func backGesture(_ run: RoutineRun) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width > Self.backSwipeThreshold {
                    run.back()
                }
            }
    }

    /// STYLEGUIDE §5 reward moment: `Morning done` / `9 of 11 steps`, plus the done/skipped
    /// breakdown the brief asks for.
    @ViewBuilder
    private func summary(_ run: RoutineRun) -> some View {
        ContentUnavailableView {
            Label(Copy.routineDone(run.routine.title), systemImage: Symbols.done)
        } description: {
            VStack(spacing: Spacing.xs) {
                Text(Copy.stepsSummary(done: run.routine.steps.count, total: run.routine.steps.count))
                Text("\(run.doneCount) done · \(run.skippedCount) skipped")
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
            }
        } actions: {
            Button(Copy.done, action: onFinished)
                .buttonStyle(.borderedProminent)
                .tint(Color.gtdAccent)
            if run.canGoBack {
                Button(Copy.back) { run.back() }
            }
        }
    }

    private static let actionButtonHeight: CGFloat = 56
    /// Guesswork threshold (STYLEGUIDE gives none for this gesture, only for the inbox card's
    /// `DragThresholds`) — verify feel on a Mac/device.
    private static let backSwipeThreshold: CGFloat = 60
}

/// A sub-step as a tappable local checklist item (R2). Ticking it is UI-only bookkeeping for the
/// current screen — it is never logged and never sent as a command.
private struct SubstepRow: View {
    let text: String
    let checked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: Spacing.s) {
                ZStack {
                    Circle().strokeBorder(Color.textTertiary, lineWidth: 1.5)
                    if checked {
                        Circle().fill(Color.ink).frame(width: 11, height: 11)
                    }
                }
                .frame(width: 20, height: 20)
                Text(text)
                    .font(Typo.body)
                    .foregroundStyle(checked ? Color.textSecondary : Color.ink)
                    .strikethrough(checked, color: Color.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

// MARK: - Previews (STYLEGUIDE §9: light, dark, AX1)

#Preview("Home") {
    NavigationStack {
        RoutinesHomeView()
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}

#Preview("Home · dark") {
    NavigationStack {
        RoutinesHomeView()
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
    .preferredColorScheme(.dark)
}

#Preview("Home · AX1") {
    NavigationStack {
        RoutinesHomeView()
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
    .dynamicTypeSize(.accessibility1)
}

#Preview("Runner · step with sub-steps") {
    RoutineRunnerView(routine: Fixtures.morningRoutine.id, onFinished: {})
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: RoutinePreviewData.partway(2)),
            snapshot: RoutinePreviewData.partway(2),
            today: { Fixtures.today }))
}

#Preview("Runner · step with sub-steps · dark") {
    RoutineRunnerView(routine: Fixtures.morningRoutine.id, onFinished: {})
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: RoutinePreviewData.partway(2)),
            snapshot: RoutinePreviewData.partway(2),
            today: { Fixtures.today }))
        .preferredColorScheme(.dark)
}

#Preview("Runner · step with sub-steps · AX1") {
    RoutineRunnerView(routine: Fixtures.morningRoutine.id, onFinished: {})
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: RoutinePreviewData.partway(2)),
            snapshot: RoutinePreviewData.partway(2),
            today: { Fixtures.today }))
        .dynamicTypeSize(.accessibility1)
}

#Preview("Runner · last step") {
    // Resumes at "Get things done" (step 8 of 8, no sub-steps) — the final step's own screen,
    // distinct from the summary that follows once it is logged.
    RoutineRunnerView(routine: Fixtures.morningRoutine.id, onFinished: {})
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: RoutinePreviewData.partway(7)),
            snapshot: RoutinePreviewData.partway(7),
            today: { Fixtures.today }))
}

#Preview("Runner · journaling step") {
    // Resumes at "Record dreams" (no sub-steps, matches R4's journaling keywords) — shows the
    // "On the reMarkable" meta line instead of an empty card.
    RoutineRunnerView(routine: Fixtures.morningRoutine.id, onFinished: {})
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: RoutinePreviewData.partway(1)),
            snapshot: RoutinePreviewData.partway(1),
            today: { Fixtures.today }))
}

#Preview("Runner · summary") {
    RoutineRunnerView(routine: Fixtures.morningRoutine.id, onFinished: {})
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: RoutinePreviewData.partway(8)),
            snapshot: RoutinePreviewData.partway(8),
            today: { Fixtures.today }))
}

#Preview("Runner · summary · dark") {
    RoutineRunnerView(routine: Fixtures.morningRoutine.id, onFinished: {})
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: RoutinePreviewData.partway(8)),
            snapshot: RoutinePreviewData.partway(8),
            today: { Fixtures.today }))
        .preferredColorScheme(.dark)
}

/// Fabricates today's log partway through the Morning routine so previews can show every state
/// without waiting on a real session. Preview-only — never used by the app or by tests.
private enum RoutinePreviewData {
    static func partway(_ loggedSteps: Int) -> VaultSnapshot {
        var snapshot = Fixtures.sampleSnapshot
        let routine = Fixtures.morningRoutine
        let entries = routine.steps.prefix(loggedSteps).enumerated().map { index, step in
            RoutineLogEntry(
                day: Fixtures.today,
                routine: routine.title,
                step: step.id,
                result: index == 1 ? .skipped : .done,
                at: Date(),
                device: "preview")
        }
        snapshot.routineLog.append(contentsOf: entries)
        return snapshot
    }
}
#endif
