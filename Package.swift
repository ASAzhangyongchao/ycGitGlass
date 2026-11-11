// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GitGlass",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "GitGlass", targets: ["GitGlass"]),
        .executable(name: "GitGlassSelfTest", targets: ["GitGlassSelfTest"])
    ],
    targets: [
        // 领域层：模型 / 基础设施 / 服务，完全不依赖 SwiftUI
        .target(name: "GitCore", path: "Sources/GitCore"),
        // 表现层：SwiftUI 视图，只消费 AppState
        .executableTarget(name: "GitGlass", dependencies: ["GitCore"], path: "Sources/GitGlass"),
        // 冒烟 / 回归自检：复用真实 GitCore 服务
        .executableTarget(name: "GitGlassSelfTest", dependencies: ["GitCore"], path: "Sources/GitGlassSelfTest")
    ]
)
