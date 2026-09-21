#if canImport(SwiftUI)
import SwiftUI
import GTDModel

/// Every `DesignSystem` component, in every state, for review (T12 acceptance; STYLEGUIDE §9
/// checklist — "previews exist for light, dark, AX1, and every component state"). Sample data is
/// built inline rather than from `GTDFixtures`: that target is not a declared dependency of this
/// one (ARCHITECTURE §2 — `DesignSystem` depends on `GTDModel` + `GTDAppCore` only), so pulling it
/// in here would need a Package.swift change this task does not own.
public struct DesignGallery: View {
    @State private var contexts: [String] = ["mac"]
    @State private var bucket: TimeBucket? = .upTo30
    @State private var deferDate: Day?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                section("Chip") { chipStates }
                section("Chip groups") { chipGroups }
                section("Badge") { badgeStates }
                section("ActionRow") { actionRows }
                section("ListItemRow") { listItemRows }
                section("ProjectRow") { ProjectRow(row: Self.sampleProjectRow, today: Self.today) }
                section("ItemCard") { itemCard }
                section("GlassActionBar") { glassActionBar }
                section("Inbox bars") { inboxBars }
                section("Required-field label") { requiredFieldLabels }
                section("WaitingInfoSheet") { waitingInfoSheet }
                section("UndoToast") { UndoToast(label: Copy.movedTo(Copy.someday), onUndo: {}) }
                section("Empty states") { emptyStates }
                section("Reward moments") { rewardMoments }
                section("Review pieces") { reviewPieces }
                section("Key legend") {
                    KeyLegendRow([
                        .init(key: "←", label: Copy.someday),
                        .init(key: "→", label: Copy.next),
                        .init(key: "↓", label: Copy.close),
                        .init(key: "P"), .init(key: "K"), .init(key: "W"), .init(key: "R"),
                    ])
                }
            }
            .padding(Spacing.screenMargin)
        }
        .background(Color.surfaceGrouped)
    }

    @ViewBuilder private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(title).font(Typo.sectionHeader).foregroundStyle(Color.ink)
            content()
        }
    }

    // MARK: Chip

    private var chipStates: some View {
        FlowLayout {
            Chip("Unset", state: .unset)
            Chip("Suggested", state: .suggested)
            Chip("Confirmed", state: .confirmed)
            Chip("Disabled", state: .disabled)
        }
    }

    private var chipGroups: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ContextChipGroup(
                contexts: ["mac", "phone", "home", "campus", "errands", "calls", "errands", "deep-work"],
                selection: $contexts)
            TimeBucketChipGroup(selection: $bucket)
            DateValueChip(label: Copy.deferLabel, value: $deferDate, today: Self.today)
        }
    }

    // MARK: Badge

    private static let today = Day(year: 2026, month: 9, day: 19)

    private var badgeStates: some View {
        FlowLayout {
            Badge(SignalPresentation.badge(for: Signal(kind: .untouched(days: 16), step: .aging), today: Self.today))
            Badge(SignalPresentation.badge(for: Signal(kind: .untouched(days: 34), step: .attention), today: Self.today))
            Badge(SignalPresentation.badge(for: Signal(kind: .overdue(days: 2), step: .overdue), today: Self.today))
            Badge(SignalPresentation.badge(for: Signal(kind: .stalled, step: .attention), today: Self.today))
            Badge(SignalPresentation.badge(for: Signal(kind: .returnedFromDefer, step: .neutral), today: Self.today))
            Badge(SignalPresentation.badge(for: Signal(kind: .cap(count: 15, cap: 15), step: .attention), today: Self.today))
        }
    }

    // MARK: Rows

    private static let sampleAction = Action(
        id: NoteID(path: "Actions/Write DAAD motivation letter.md"),
        title: "Write DAAD motivation letter",
        status: .next,
        contexts: ["mac", "deep-work"],
        timeEstimate: 60,
        modified: Calendar.current.date(byAdding: .day, value: -16, to: Date()))

    private static let sampleProject = Project(
        id: NoteID(path: "Projects/Applications/DAAD/DAAD.md"),
        title: "DAAD application",
        status: .active,
        outcome: "Submitted before the deadline",
        steps: [ProjectStep(text: "Collect transcripts"), ProjectStep(text: "Write motivation letter")])

    private static let sampleProjectRow = Rules.ProjectRow(
        project: sampleProject,
        activeActions: [sampleAction],
        remainingSteps: 2,
        isStalled: false)

    private var actionRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ActionRow(
                action: Self.sampleAction,
                projectTitle: "DAAD application",
                badges: [SignalPresentation.badge(for: Signal(kind: .untouched(days: 16), step: .aging), today: Self.today)],
                onComplete: {})
            Divider()
            ActionRow(action: Self.sampleAction, onComplete: nil)
        }
    }

    // MARK: List items

    private static let sampleListItem = ListItem(
        id: NoteID(path: "Lists/Read/Sapiens.md"), list: "Read", title: "Sapiens")

    private var listItemRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListItemRow(item: Self.sampleListItem, onComplete: {})
            Divider()
            ListItemRow(item: Self.sampleListItem, onComplete: nil)
        }
    }

    // MARK: ItemCard

    private var itemCard: some View {
        ItemCard {
            Text("today").font(Typo.counter).foregroundStyle(Color.textSecondary)
            CollapsibleText("Call the Studierendenwerk about the deposit before Friday, otherwise the refund slips into next month.")
            Text(Copy.why).font(Typo.sectionHeader).foregroundStyle(Color.ink)
            Text(Copy.what).font(Typo.sectionHeader).foregroundStyle(Color.ink)
        }
        .itemCardPeek(hasNext: true)
    }

    // MARK: Glass

    private var glassActionBar: some View {
        GlassActionBar {
            Label(Copy.project, systemImage: Symbols.projects)
            Label(Copy.knowledge, systemImage: Symbols.knowledge)
            Label(Copy.waiting, systemImage: Symbols.waiting)
        }
        .labelStyle(.iconOnly)
    }

    // MARK: Inbox bars (T06)

    @State private var isFieldFocused = false
    @State private var validationTrigger = 0

    private var inboxBars: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            StepOneBar(onAction: {}, onKnowledgeOrList: {}, onTrash: {})
            ActionCardBar(
                isFieldFocused: isFieldFocused,
                onWaiting: {}, onDone: {}, onFileToNext: {}, onFileToSomeday: {},
                onDismissKeyboard: { isFieldFocused = false })
            Button(isFieldFocused ? "Show buttons" : "Show keyboard Done bar") {
                isFieldFocused.toggle()
            }
            .font(Typo.meta)
            KnowledgeListNavbar(
                favourites: ["Read", "Watch", "Wish"],
                platform: .iPhone,
                onKnowledge: {}, onList: { _ in }, onMore: {})
            ItemCard {
                Text(Copy.whyPlaceholder).font(Typo.body)
            }
            .shake(trigger: validationTrigger)
            Button("Trigger shake") { validationTrigger += 1 }
                .font(Typo.meta)
        }
    }

    // MARK: Required-field label (T06)

    private var requiredFieldLabels: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionLabel(Copy.why)
            SectionLabel(Copy.why, isMissing: true)
            SectionLabel("Context", isMissing: true, font: Typo.meta, foreground: .textSecondary)
        }
    }

    // MARK: WaitingInfoSheet (T06)

    private var waitingInfoSheet: some View {
        WaitingInfoSheet(suggestedWho: ["Marie", "Landlord"], today: Self.today, onSave: { _ in })
            .frame(maxWidth: 360)
            .background(Color.surfaceCard, in: Radius.cardShape)
    }

    // MARK: Empty states (T06 — Someday and Lists)

    private var emptyStates: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ContentUnavailableView(
                Copy.emptySomedayTitle, systemImage: Symbols.someday)
            ContentUnavailableView(
                Copy.emptyListTitle("Read"), systemImage: Symbols.list(named: "Read"))
        }
    }

    // MARK: Reward moments

    private var rewardMoments: some View {
        VStack(spacing: Spacing.l) {
            RewardMoment.inboxZero(processed: 14, minutes: 6)
            Divider()
            RewardMoment.routineComplete(routine: "Morning", done: 9, total: 11)
        }
    }

    // MARK: Review pieces

    private var reviewPieces: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(spacing: Spacing.m) {
                StatTile(label: "Processed", value: "14", trend: "▲ 3 vs last week")
                StatTile(label: "Completed", value: "22")
            }
            RoutineHeatmap(
                rows: [
                    RoutineHeatmap.Row(
                        title: "Cold shower",
                        cells: [.done, .done, .skipped, .done, .noData, .done, .done],
                        completionPercent: 71),
                ],
                columnLabels: ["M", "T", "W", "T", "F", "S", "S"])
            ReviewWizardRail(
                stages: [
                    .init(title: "Inbox", isComplete: true),
                    .init(title: "Projects", subSteps: ["Stalled", "On hold"], isComplete: false),
                    .init(title: "Next & Waiting", isComplete: false),
                    .init(title: "Look ahead", isComplete: false),
                ],
                current: "Projects")
        }
    }
}

#Preview("Light") {
    DesignGallery()
}

#Preview("Dark") {
    DesignGallery().preferredColorScheme(.dark)
}

#Preview("AX1") {
    DesignGallery().environment(\.sizeCategory, .accessibilityMedium)
}
#endif
