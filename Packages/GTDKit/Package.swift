// swift-tools-version: 6.2
// Owned by T00. Nobody else edits this file — see agent_task/README.md "Contract changes".
import PackageDescription

/// Applied to every target: Swift 6 language mode (strict concurrency).
let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

/// Every UI target owns its own `Resources/Localizable.xcstrings` (ARCHITECTURE §5), so parallel
/// tasks never share a string catalog. `.process` is a no-op warning under `swift build` on Linux
/// and compiles the catalogs under `xcodebuild`.
let uiResources: [Resource] = [.process("Resources")]

let package = Package(
    name: "GTDKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "GTDKit", targets: [
            "GTDModel", "GTDMarkdown", "GTDVault", "GTDServices", "GTDAppCore", "GTDFixtures",
            "DesignSystem", "GTDNotifications", "GTDStats",
            "FeatureInbox", "FeatureNext", "FeatureProjects", "FeatureWaiting", "FeatureRoutines",
            "FeatureOverview", "FeatureSettings", "FeatureReview", "GTDIntents",
        ]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        // MARK: - Domain

        .target(name: "GTDModel", swiftSettings: swiftSettings),
        .target(
            name: "GTDMarkdown",
            dependencies: ["GTDModel", .product(name: "Yams", package: "Yams")],
            swiftSettings: swiftSettings),
        .target(name: "GTDVault", dependencies: ["GTDModel", "GTDMarkdown"], swiftSettings: swiftSettings),
        .target(name: "GTDServices", dependencies: ["GTDModel", "GTDMarkdown", "GTDVault"], swiftSettings: swiftSettings),
        .target(name: "GTDAppCore", dependencies: ["GTDModel"], swiftSettings: swiftSettings),
        .target(
            name: "GTDFixtures",
            dependencies: ["GTDModel"],
            // `.copy` (not `.process`): the sample vault must keep its folder tree byte-for-byte.
            resources: [.copy("Resources/SampleVault")],
            swiftSettings: swiftSettings),
        .target(name: "GTDNotifications", dependencies: ["GTDModel"], swiftSettings: swiftSettings),
        .target(name: "GTDStats", dependencies: ["GTDModel"], swiftSettings: swiftSettings),

        // MARK: - UI

        .target(
            name: "DesignSystem",
            dependencies: ["GTDModel", "GTDAppCore"],
            resources: uiResources,
            swiftSettings: swiftSettings),
        .target(name: "FeatureInbox", dependencies: ["GTDAppCore", "DesignSystem"], resources: uiResources, swiftSettings: swiftSettings),
        .target(name: "FeatureNext", dependencies: ["GTDAppCore", "DesignSystem"], resources: uiResources, swiftSettings: swiftSettings),
        .target(name: "FeatureProjects", dependencies: ["GTDAppCore", "DesignSystem"], resources: uiResources, swiftSettings: swiftSettings),
        .target(name: "FeatureWaiting", dependencies: ["GTDAppCore", "DesignSystem"], resources: uiResources, swiftSettings: swiftSettings),
        .target(name: "FeatureRoutines", dependencies: ["GTDAppCore", "DesignSystem"], resources: uiResources, swiftSettings: swiftSettings),
        .target(name: "FeatureSettings", dependencies: ["GTDAppCore", "DesignSystem"], resources: uiResources, swiftSettings: swiftSettings),
        .target(
            name: "FeatureReview",
            dependencies: ["GTDAppCore", "DesignSystem", "GTDStats", "FeatureInbox", "FeatureProjects"],
            resources: uiResources,
            swiftSettings: swiftSettings),
        .target(
            name: "FeatureOverview",
            dependencies: [
                "GTDAppCore", "DesignSystem",
                "FeatureInbox", "FeatureNext", "FeatureProjects", "FeatureWaiting",
                "FeatureRoutines", "FeatureSettings", "FeatureReview",
            ],
            resources: uiResources,
            swiftSettings: swiftSettings),
        .target(name: "GTDIntents", dependencies: ["GTDModel", "GTDVault"], resources: uiResources, swiftSettings: swiftSettings),

        // MARK: - Tests

        .testTarget(name: "GTDModelTests", dependencies: ["GTDModel", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "GTDMarkdownTests", dependencies: ["GTDMarkdown", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "GTDVaultTests", dependencies: ["GTDVault", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "GTDServicesTests", dependencies: ["GTDServices", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "GTDAppCoreTests", dependencies: ["GTDAppCore", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "GTDFixturesTests", dependencies: ["GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "GTDNotificationsTests", dependencies: ["GTDNotifications", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "GTDStatsTests", dependencies: ["GTDStats", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "FeatureInboxTests", dependencies: ["FeatureInbox", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "FeatureNextTests", dependencies: ["FeatureNext", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "FeatureProjectsTests", dependencies: ["FeatureProjects", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "FeatureWaitingTests", dependencies: ["FeatureWaiting", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "FeatureRoutinesTests", dependencies: ["FeatureRoutines", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "FeatureOverviewTests", dependencies: ["FeatureOverview", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "FeatureSettingsTests", dependencies: ["FeatureSettings", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "FeatureReviewTests", dependencies: ["FeatureReview", "GTDFixtures"], swiftSettings: swiftSettings),
        .testTarget(name: "GTDIntentsTests", dependencies: ["GTDIntents", "GTDFixtures"], swiftSettings: swiftSettings),
    ]
)
