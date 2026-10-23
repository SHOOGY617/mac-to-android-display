// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacDisplayHost",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacDisplayHost",
            targets: ["MacDisplayHost"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacDisplayHost",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Network")
            ]
        )
    ]
)
