// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ParentalControlEndpoint",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "EndpointCore", targets: ["EndpointCore"]),
    .executable(name: "ParentalControlChild", targets: ["ParentalControlChild"]),
    .executable(name: "ParentalControlAgentDaemon", targets: ["ParentalControlAgentDaemon"]),
    .executable(name: "ParentalControlAgentUser", targets: ["ParentalControlAgentUser"]),
    .executable(name: "ParentalControlAgentCtl", targets: ["ParentalControlAgentCtl"]),
    .executable(name: "ParentalControlBrowserHost", targets: ["ParentalControlBrowserHost"]),
  ],
  dependencies: [.package(path: "../../apps/controller-macos")],
  targets: [
    .target(
      name: "EndpointCore",
      dependencies: [.product(name: "HubCore", package: "controller-macos")],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("CoreGraphics"),
        .linkedFramework("Network"),
        .linkedFramework("Security"),
        .linkedFramework("SystemConfiguration"),
        .linkedFramework("UserNotifications"),
      ]),
    .executableTarget(
      name: "ParentalControlChild", dependencies: ["EndpointCore"],
      linkerSettings: [.linkedFramework("UserNotifications")]),
    .executableTarget(name: "ParentalControlAgentDaemon", dependencies: ["EndpointCore"]),
    .executableTarget(
      name: "ParentalControlAgentUser", dependencies: ["EndpointCore"],
      linkerSettings: [.linkedFramework("UserNotifications")]),
    .executableTarget(name: "ParentalControlAgentCtl", dependencies: ["EndpointCore"]),
    .executableTarget(name: "ParentalControlBrowserHost", dependencies: ["EndpointCore"]),
    .testTarget(
      name: "EndpointCoreTests",
      dependencies: ["EndpointCore", .product(name: "HubCore", package: "controller-macos")]),
  ])
