// swift-tools-version: 6.2
// Owned by T00. Nobody else edits this file — see agent_task/README.md "Contract changes".
import PackageDescription

/// Applied to every target: Swift 6 language mode (strict concurrency).
let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

/// Every source target carries a `README.md` (CLAUDE.md "Where things are"); it is documentation,
/// not a resource, so SwiftPM is told to leave it alone.
let excluded = ["README.md"]

/// Every UI target owns its own `Resources/Localizable.xcstrings` (ARCHITECTURE §5), so parallel
/// tasks never share a string catalog. `.process` is a no-op warning under `swift build` on Linux
/// and compiles the catalogs under `xcodebuild`.
let uiResources: [Resource] = [.process("Resources")]

/// Feature targets depend on `GTDAppCore` + `DesignSystem` only — never on `GTDVault`/
/// `GTDServices` (ARCHITECTURE §2).
let featureDeps: [Target.Dependency] = ["GTDAppCore", "DesignSystem", "GTDFixtures"]  // GTDFixtures: `#Preview`s in every feature (ARCHITECTURE §5)

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

        .target(name: "GTDModel", exclude: excluded, swiftSettings: swiftSettings),
        .target(
            name: "GTDMarkdown",
            dependencies: ["GTDModel", .product(name: "Yams", package: "Yams")],
            exclude: excluded,
            swiftSettings: swiftSettings),
        .target(name: "GTDVault", dependencies: ["GTDModel", "GTDMarkdown"], exclude: excluded, swiftSettings: swiftSettings),
        .target(name: "GTDServices", dependencies: ["GTDModel", "GTDMarkdown", "GTDVault"], exclude: excluded, swiftSettings: swiftSettings),
        .target(name: "GTDAppCore", dependencies: ["GTDModel"], exclude: excluded, swiftSettings: swiftSettings),
        .target(
            name: "GTDFixtures",
            dependencies: ["GTDModel"],
            exclude: excluded,
            // `.copy` (not `.process`): the sample vault must keep its folder tree byte-for-byte.
            resources: [.copy("Resources/SampleVault")],
            swiftSettings: swiftSettings),
        .target(name: "GTDNotifications", dependencies: ["GTDModel"], exclude: excluded, swiftSettings: swiftSettings),
        .target(name: "GTDStats", dependencies: ["GTDModel"], exclude: excluded, swiftSettings: swiftSettings),

        // MARK: - UI

        .target(
            name: "DesignSystem",
            dependencies: ["GTDModel", "GTDAppCore"],
            exclude: excluded,
            resources: uiResources,
            swiftSettings: swiftSettings),
        .target(name: "FeatureInbox", dependencies: featureDeps, exclude: excluded, resources: uiResources, swiftSettings: swiftSettings),
        .target(name: "FeatureNext", dependencies: featureDeps, exclude: excluded, resources: uiResources, swiftSettings: swiftSettings),
        .target(name: "FeatureProjects", dependencies: featureDeps, exclude: excluded, resources: uiResources, swiftSettings: swiftSettings),
        .target(name: "FeatureWaiting", dependencies: featureDeps, exclude: excluded, resources: uiResources, swiftSettings: swiftSettings),
        .target(name: "FeatureRoutines", dependencies: featureDeps, exclude: excluded, resources: uiResources, swiftSettings: swiftSettings),
        .target(name: "FeatureSettings", dependencies: featureDeps, exclude: excluded, resources: uiResources, swiftSettings: swiftSettings),
        .target(
            name: "FeatureReview",
            dependencies: featureDeps + ["GTDStats", "FeatureInbox", "FeatureProjects"],
            exclude: excluded,
            resources: uiResources,
            swiftSettings: swiftSettings),
        .target(
            name: "FeatureOverview",
            dependencies: featureDeps + [
                "FeatureInbox", "FeatureNext", "FeatureProjects", "FeatureWaiting",
                "FeatureRoutines", "FeatureSettings", "FeatureReview",
            ],
            exclude: excluded,
            resources: uiResources,
            swiftSettings: swiftSettings),
        .target(name: "GTDIntents", dependencies: ["GTDModel", "GTDVault"], exclude: excluded, resources: uiResources, swiftSettings: swiftSettings),

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
