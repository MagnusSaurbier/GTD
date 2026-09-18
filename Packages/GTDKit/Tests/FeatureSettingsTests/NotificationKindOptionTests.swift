import Testing
@testable import FeatureSettings

/// Guards the mirror of `GTDNotifications.NotificationKind`'s raw values (see the doc comment on
/// `NotificationKindOption`): if T13 renames a case, this drifts and should be caught in review.
struct NotificationKindOptionTests {
    @Test func rawValuesMatchNotificationKind() {
        let expected: Set<String> = ["deferReturn", "dueApproaching", "followUp", "routineStart", "summary"]
        #expect(Set(NotificationKindOption.allCases.map(\.rawValue)) == expected)
    }

    @Test func everyOptionHasALabel() {
        for option in NotificationKindOption.allCases {
            #expect(!option.label.isEmpty)
        }
    }
}
