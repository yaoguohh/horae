// swift-tools-version: 6.0
import PackageDescription

// 可执行 target；.app 包由 Makefile 组装(Info.plist / icons / ad-hoc 签名)，
// 不依赖 Xcode 工程，与现有 CLI 构建路线一致。
let package = Package(
    name: "Horae",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Horae", path: "Sources/Horae")
    ]
)
