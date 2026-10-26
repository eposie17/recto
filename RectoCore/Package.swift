// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RectoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RectoCore", targets: ["RectoCore"]),
    ],
    targets: [
        .target(name: "RectoCore"),
        .testTarget(name: "RectoCoreTests", dependencies: ["RectoCore"], resources: [.copy("Resources")]),
    ]
)
