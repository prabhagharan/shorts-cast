// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ShortsCastCore",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "ShortsCastCore", targets: ["ShortsCastCore"])
    ],
    targets: [
        .target(name: "ShortsCastCore"),
        .testTarget(name: "ShortsCastCoreTests", dependencies: ["ShortsCastCore"])
    ]
)
