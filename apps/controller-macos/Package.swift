// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ParentalControlController",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "HubCore",
            targets: ["HubCore"]
        ),
        .executable(
            name: "ParentalControlController",
            targets: ["ParentalControlController"]
        ),
        .executable(
            name: "ParentalControlHub",
            targets: ["ParentalControlHub"]
        ),
        .executable(
            name: "ParentalControlMockAgent",
            targets: ["ParentalControlMockAgent"]
        )
    ],
    targets: [
        .target(
            name: "HubCore",
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("Security"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "ParentalControlController",
            dependencies: ["HubCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "ParentalControlHub",
            dependencies: ["HubCore"]
        ),
        .executableTarget(
            name: "ParentalControlMockAgent",
            dependencies: ["HubCore"]
        ),
        .testTarget(
            name: "ParentalControlControllerTests",
            dependencies: ["ParentalControlController", "HubCore"]
        ),
        .testTarget(
            name: "HubCoreTests",
            dependencies: ["HubCore"]
        )
    ]
)
