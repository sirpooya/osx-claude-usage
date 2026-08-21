// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeUsage", targets: ["ClaudeUsage"]),
        .library(name: "ClaudeUsageCore", targets: ["ClaudeUsageCore"]),
    ],
    targets: [
        // Pure logic. No AppKit, no SwiftUI, so it stays unit testable.
        .target(
            name: "ClaudeUsageCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The menu bar app itself.
        .executableTarget(
            name: "ClaudeUsage",
            dependencies: ["ClaudeUsageCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
