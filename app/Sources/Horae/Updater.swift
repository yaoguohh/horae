import Combine
import Sparkle
import SwiftUI

// Updater 把 Sparkle 的 SPUStandardUpdaterController 包成 SwiftUI 可观察对象。
// 走 ad-hoc 签名 + appcast 的 EdDSA 签名校验，独立于 Apple 公证(见 scripts/package-app.sh)。
@MainActor
final class Updater: ObservableObject {
    private let controller: SPUStandardUpdaterController
    // canCheck 在 Sparkle 正忙(已有检查在跑)时为 false，用来禁用"检查更新"按钮。
    @Published var canCheck = true

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
