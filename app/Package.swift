// swift-tools-version: 6.0
import PackageDescription

// 可执行 target；.app 包由 Makefile 组装(Info.plist / icons / ad-hoc 签名)，
// 不依赖 Xcode 工程，与现有 CLI 构建路线一致。
let package = Package(
    name: "Horae",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Sparkle: 应用内自动更新。ad-hoc 签名路径靠自带的 EdDSA 更新签名工作，独立于 Apple 公证。
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Horae",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Horae"
        )
    ]
)
