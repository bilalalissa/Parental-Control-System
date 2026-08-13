// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ParentalControlController",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ParentalControlController",
            targets: ["ParentalControlController"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ParentalControlController",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "ParentalControlControllerTests",
            dependencies: ["ParentalControlController"]
        )
    ]
)
