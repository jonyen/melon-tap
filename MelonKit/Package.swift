// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MelonKit",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v14)],
    products: [
        .library(name: "MelonKit", targets: ["MelonKit"])
    ],
    targets: [
        .target(name: "MelonKit"),
        .testTarget(name: "MelonKitTests", dependencies: ["MelonKit"])
    ]
)
