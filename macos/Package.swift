// swift-tools-version:5.9
import PackageDescription

#if os(macOS)
let appProducts: [Product] = [
    .executable(name: "JTCopilot", targets: ["JTCopilot"])
]
let appTargets: [Target] = [
    .executableTarget(
        name: "JTCopilot",
        dependencies: ["JTCopilotCore"],
        path: "Sources/JTCopilot"
    )
]
let appTestTargets: [Target] = [
    .testTarget(
        name: "JTCopilotUITests",
        dependencies: ["JTCopilot"],
        path: "Tests/JTCopilotUITests"
    )
]
#else
// Linux 沙箱只验证与平台无关的核心逻辑，不构建 AppKit 可执行目标。
let appProducts: [Product] = []
let appTargets: [Target] = []
let appTestTargets: [Target] = []
#endif

let package = Package(
    name: "JTCopilot",
    platforms: [
        .macOS(.v14)
    ],
    products: appProducts,
    targets: [
        .target(
            name: "JTCopilotCore",
            path: "Sources/JTCopilotCore"
        )
    ] + appTargets + appTestTargets + [
        .testTarget(
            name: "JTCopilotCoreTests",
            dependencies: ["JTCopilotCore"],
            path: "Tests/JTCopilotCoreTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
