// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CareKit",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CareKit", targets: ["CareKit"]),
    ],
    targets: [
        .target(name: "CareKit"),
        .testTarget(name: "CareKitTests", dependencies: ["CareKit"]),
    ]
)
