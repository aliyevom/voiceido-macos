// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TextSnipper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TextSnipper", targets: ["TextSnipper"])
    ],
    targets: [
        .target(
            name: "TextSnipperCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "TextSnipper",
            dependencies: ["TextSnipperCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(
            name: "TextSnipperCoreTests",
            dependencies: ["TextSnipperCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
