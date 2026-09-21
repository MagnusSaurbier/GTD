import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import DesignSystem

/// STYLEGUIDE §2.2 — badge wording is fixed. Tests never assert on resolved asset colours or
/// catalog lookups (ARCHITECTURE §5 caveat).
struct SignalPresentationTests {
    private let today = Fixtures.today

    @Test func everyStyleGuideRowHasItsWording() {
        func text(_ kind: SignalKind, _ step: SignalStep) -> String {
            SignalPresentation.badge(for: Signal(kind: kind, step: step), today: today).text
        }
        #expect(text(.untouched(days: 16), .aging) == "16d")
        #expect(text(.untouched(days: 34), .attention) == "34d")
        #expect(text(.followUpSoon(today.adding(days: 2)), .aging).hasPrefix("follow up "))
        #expect(text(.chase(days: 9), .attention) == "chase · 9d")
        #expect(text(.dueSoon(today.adding(days: 3)), .aging).hasPrefix("due "))
        #expect(text(.dueToday, .attention) == "due today")
        #expect(text(.overdue(days: 2), .overdue) == "2d overdue")
        #expect(text(.returnedFromDefer, .neutral) == "back")
        #expect(text(.stalled, .attention) == "stalled")
        #expect(text(.cap(count: 15, cap: 15), .attention) == "15/15")
        #expect(text(.cap(count: 17, cap: 15), .overdue) == "17/15")
        #expect(text(.inboxAge(days: 8), .aging) == "8d")
    }

    @Test func symbolsComeFromTheIconMap() {
        #expect(SignalPresentation.badge(for: Signal(kind: .untouched(days: 16), step: .aging),
                                         today: today).symbol == Symbols.aging)
        #expect(SignalPresentation.badge(for: Signal(kind: .untouched(days: 34), step: .attention),
                                         today: today).symbol == Symbols.staleAttention)
        #expect(SignalPresentation.badge(for: Signal(kind: .stalled, step: .attention),
                                         today: today).symbol == Symbols.stalled)
        #expect(SignalPresentation.badge(for: Signal(kind: .cap(count: 15, cap: 15), step: .attention),
                                         today: today).symbol == nil)
    }

    @Test func atMostTwoBadgesHighestStepFirst() {
        let signals = [
            Signal(kind: .untouched(days: 20), step: .aging),
            Signal(kind: .dueToday, step: .attention),
            Signal(kind: .overdue(days: 1), step: .overdue),
        ]
        let badges = SignalPresentation.badges(for: signals, today: today)
        #expect(badges.count == 2)
        #expect(badges[0].step == .overdue)
        #expect(badges[1].step == .attention)
    }

    @Test func dateWording() {
        #expect(DateText.short(today, today: today) == "today")
        #expect(DateText.short(today.adding(days: 1), today: today) == "tomorrow")
        #expect(DateText.short(today.adding(days: 3), today: today) == "Tue")
        #expect(DateText.short(today.adding(days: 20), today: today) == "9 Oct")
        #expect(DateText.age(days: 16) == "16d")
        #expect(DateText.spelledAge(days: 1) == "1 day old")
    }

    @Test func canonicalCopy() {
        #expect(Copy.counter(remaining: 3, total: 14) == "3 of 14 left")
        #expect(Copy.movedTo(Copy.someday) == "Moved to Someday")
        #expect(Copy.whatsNext(project: "DAAD") == "What's next for DAAD?")
        #expect(Copy.timeBucket(.over60) == "60+")
        #expect(Copy.capSheetTitle == "Next is full")
    }
}
