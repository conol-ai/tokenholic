// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tokenholic",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Tokenholic",
            path: "Sources/Tokenholic",
            swiftSettings: [
                // Relaxed concurrency for now; tighten to .v6 once the
                // collector/refresh actor boundaries are settled.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
