// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ReelsKit",
    // macOS is supported only so `swift test` runs on the command line without a
    // simulator. Keep this module free of UIKit/SwiftUI so that stays true.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ReelsKit", targets: ["ReelsKit"])
    ],
    targets: [
        .target(name: "ReelsKit"),
        .testTarget(name: "ReelsKitTests", dependencies: ["ReelsKit"])
    ]
)
