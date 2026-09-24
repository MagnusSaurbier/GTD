import Foundation
import Testing
@testable import DesignSystem

/// The version the shells stamp bottom right and Settings prints — read from the bundle's
/// `Info.plist` keys, never invented (STYLEGUIDE §1: no lying defaults).
struct AppVersionTests {

    @Test func readsBothKeysFromTheInfoDictionary() {
        let version = AppVersion(infoDictionary: ["CFBundleShortVersionString": "0.3", "CFBundleVersion": "1"])
        #expect(version == AppVersion(short: "0.3", build: "1"))
        #expect(version.stampLabel == "0.3")
        #expect(version.settingsLabel == "0.3 (1)")
        #expect(version.spokenLabel == "Version 0.3")
    }

    /// The old Settings code printed "1.0 (1)" for a bundle without a version — a made-up number.
    @Test func aMissingKeyReadsAsEmptyNotAsAnInventedNumber() {
        #expect(AppVersion(infoDictionary: nil) == AppVersion(short: "", build: ""))
        #expect(AppVersion(infoDictionary: [:]).stampLabel.isEmpty)
        #expect(AppVersion(infoDictionary: [:]).settingsLabel.isEmpty)
        #expect(AppVersion(infoDictionary: ["CFBundleShortVersionString": 3]).short.isEmpty)
        #expect(AppVersion(infoDictionary: ["CFBundleVersion": "7"]).settingsLabel == "(7)")
        #expect(AppVersion(infoDictionary: ["CFBundleShortVersionString": "0.3"]).settingsLabel == "0.3")
    }
}
