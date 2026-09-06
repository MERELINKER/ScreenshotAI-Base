// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ScreenshotAIBase",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScreenshotAIKit", targets: ["ScreenshotAIKit"]),
        .executable(name: "ScreenshotAIBase", targets: ["ScreenshotAIBase"])
    ],
    targets: [
        .target(name: "ScreenshotAIKit", path: "Sources/ScreenshotAIKit"),
        .executableTarget(
            name: "ScreenshotAIBase",
            dependencies: ["ScreenshotAIKit"],
            path: "Sources/ScreenshotAIApp",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "ScreenshotAIAppTests",
            dependencies: ["ScreenshotAIBase", "ScreenshotAIKit"],
            path: "Tests/ScreenshotAIAppTests"
        ),
        .testTarget(
            name: "ScreenshotAIKitTests",
            dependencies: ["ScreenshotAIKit"],
            path: "Tests/ScreenshotAIKitTests"
        )
    ]
)
