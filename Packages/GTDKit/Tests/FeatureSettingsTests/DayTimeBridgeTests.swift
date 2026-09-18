import Testing
import Foundation
import GTDModel
@testable import FeatureSettings

/// `DayTime <-> Date` round trip used to bind routine/morning times to a stock `DatePicker`.
struct DayTimeBridgeTests {
    @Test func roundTripsHourAndMinute() {
        let time = DayTime(hour: 6, minute: 45)
        #expect(DayTime(time.asDate) == time)
    }

    @Test func midnightRoundTrips() {
        let time = DayTime(hour: 0, minute: 0)
        #expect(DayTime(time.asDate) == time)
    }

    @Test func lateEveningRoundTrips() {
        let time = DayTime(hour: 23, minute: 59)
        #expect(DayTime(time.asDate) == time)
    }
}
