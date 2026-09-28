// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Diple",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Diple",
            path: "Sources/Diple",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DipleTests",
            dependencies: ["Diple"],
            path: "Tests/DipleTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
