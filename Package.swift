// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Soundtrack",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Soundtrack",
            path: "Sources/Soundtrack",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
