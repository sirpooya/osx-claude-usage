// swift-tools-version: 5.9
//
// Lightweight SwiftPM package for unit-testing pure functions extracted from
// the Xcode app target. The .xcodeproj remains the authoritative app build;
// this manifest exists only so contributors can run:
//
//     swift test
//
// against pure-function helpers without spinning up Xcode. Targets reference
// existing source files in place via `path:` + `sources:` — no duplication,
// no drift. As more pure code is extracted into focused files, add it to the
// ClaudeUsageCore target's `sources` and write tests in Tests/.
//
import PackageDescription

let package = Package(
    name: "ClaudeUsageTests",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ClaudeUsageCore", targets: ["ClaudeUsageCore"])
    ],
    targets: [
        .target(
            name: "ClaudeUsageCore",
            path: "ClaudeUsage",
            exclude: ["Resources"],
            sources: [
                "Models/ClaudeAPIResponseModels.swift",
                "Helpers/JWT.swift",
                "Models/MonitoringMode.swift",
                "Models/ProviderType.swift",
                "Helpers/SmartRefreshPolicy.swift",
                "Services/OAuthTokenCache.swift",
                "Helpers/SensitiveDataRedactor.swift",
                "Helpers/ResetTimeChange.swift",
                "Helpers/NotificationDecisionEngine.swift",
                "Models/CodexUsageData.swift"
            ]
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"],
            path: "Tests/ClaudeUsageCoreTests"
        )
    ]
)
