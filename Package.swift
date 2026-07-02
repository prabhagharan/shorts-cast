// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ShortsCast",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "ShortsCastCore", targets: ["ShortsCastCore"]),
        .library(name: "ShortsCastCapture", targets: ["ShortsCastCapture"]),
        .library(name: "ShortsCastRender", targets: ["ShortsCastRender"]),
        .library(name: "ShortsCastEditor", targets: ["ShortsCastEditor"]),
        .executable(name: "shortscast-rec", targets: ["shortscast-rec"]),
        .executable(name: "shortscast-export", targets: ["shortscast-export"]),
        .executable(name: "shortscast-app", targets: ["shortscast-app"]),
        .executable(name: "shortscast-mcp", targets: ["shortscast-mcp"]),
    ],
    targets: [
        .target(name: "ShortsCastCore"),
        .testTarget(name: "ShortsCastCoreTests", dependencies: ["ShortsCastCore"]),
        .target(name: "ShortsCastCapture", dependencies: ["ShortsCastCore"]),
        .testTarget(name: "ShortsCastCaptureTests", dependencies: ["ShortsCastCapture"]),
        .target(name: "ShortsCastRender", dependencies: ["ShortsCastCore", "ShortsCastCapture"]),
        .testTarget(name: "ShortsCastRenderTests", dependencies: ["ShortsCastRender"]),
        .target(name: "ShortsCastEditor", dependencies: ["ShortsCastCore", "ShortsCastCapture", "ShortsCastRender"]),
        .testTarget(name: "ShortsCastEditorTests", dependencies: ["ShortsCastEditor"]),
        .executableTarget(name: "shortscast-rec", dependencies: ["ShortsCastCapture", "ShortsCastCore"]),
        .executableTarget(name: "shortscast-export", dependencies: ["ShortsCastRender", "ShortsCastCore", "ShortsCastCapture"]),
        .executableTarget(name: "shortscast-app", dependencies: ["ShortsCastEditor", "ShortsCastCore", "ShortsCastCapture", "ShortsCastRender"]),
        .target(name: "ShortsCastMCP",
                dependencies: ["ShortsCastCore", "ShortsCastCapture", "ShortsCastRender", "ShortsCastEditor"]),
        .testTarget(name: "ShortsCastMCPTests", dependencies: ["ShortsCastMCP"]),
        .executableTarget(name: "shortscast-mcp", dependencies: ["ShortsCastMCP"]),
    ]
)
