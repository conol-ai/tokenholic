// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tokenholic",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.47.0")
    ],
    targets: [
        .executableTarget(
            name: "Tokenholic",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: "Sources/Tokenholic",
            swiftSettings: [
                // Relaxed concurrency for now; tighten to .v6 once the
                // collector/refresh actor boundaries are settled.
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "TokenholicTests",
            dependencies: ["Tokenholic"],
            path: "Tests/TokenholicTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
