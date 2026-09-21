#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

/// Step 4 (§10.4): the reminder to read the week's handwritten journal, then the eight
/// questions, with last week's "goal for next week" shown beside the first one.
struct ReflectionStep: View {
    @Bindable var session: ReviewSession

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ReviewStepHeader(title: ReviewCopy.stageReflection, symbol: ReviewSymbols.review)

            // R4/§10.4 — journaling happens on the reMarkable; the app only reminds.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label(ReviewCopy.remarkableReminderTitle, systemImage: ReviewSymbols.journaling)
                    .font(Typo.sectionHeader)
                    .foregroundStyle(Color.ink)
                Text(ReviewCopy.remarkableReminderBody)
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.m)
            .background(Color.surfaceCard, in: Radius.tileShape)

            ForEach(ReviewQuestion.allCases) { question in
                ReviewTextField(
                    label: question.prompt,
                    placeholder: "",
                    text: Binding(
                        get: { session.answers[question] },
                        set: { session.answers[question] = $0 }),
                    footnote: footnote(for: question))
            }
        }
    }

    /// Last week's goal next to "What did I want to achieve?" (§10.4). Absent rather than
    /// empty when there is no earlier review — an empty quote would be a lying default.
    private func footnote(for question: ReviewQuestion) -> String? {
        guard question.showsLastWeeksGoal else { return nil }
        guard let goal = session.lastWeeksGoal, let last = session.lastReview else {
            return ReviewCopy.noLastReview
        }
        return "\(ReviewCopy.lastWeeksGoal(week: last.week)): \(goal)"
    }
}

/// The summary screen (§10): one of the two reward moments (STYLEGUIDE §5.2) and what this
/// review actually changed.
struct ReviewSummaryStep: View {
    @Bindable var session: ReviewSession
    let onFinished: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            RewardMoment.reviewComplete(done: session.walkedPages, total: session.totalPages)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(ReviewCopy.summaryTitle).font(Typo.sectionHeader).foregroundStyle(Color.ink)
                ForEach(session.summaryRows) { row in
                    HStack {
                        Text(row.label).font(Typo.body).foregroundStyle(Color.ink)
                        Spacer(minLength: Spacing.s)
                        Text("\(row.value)")
                            .font(Typo.counter)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .padding(Spacing.m)
            .background(Color.surfaceCard, in: Radius.tileShape)

            Text(ReviewCopy.savedAs(year: session.state.year, week: session.state.week))
                .font(Typo.counter)
                .foregroundStyle(Color.textSecondary)

            HStack {
                Spacer()
                Button(ReviewCopy.finish, action: onFinished)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
#endif
