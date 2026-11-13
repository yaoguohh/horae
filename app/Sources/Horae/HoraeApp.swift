import SwiftUI

@main
struct HoraeApp: App {
    @StateObject private var store = Store()
    @StateObject private var updater = Updater()

    var body: some Scene {
        MenuBarExtra {
            // 外观跟随系统的浅色与深色。
            PopoverView()
                .environmentObject(store)
                .environmentObject(updater)
        } label: {
            MenuBarMark(state: store.board().overall, clock: store.markClock)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 菜单栏图标：字母 H 的四态模板图（空闲、运行、需要处理、已暂停），只靠形状区分，颜色由系统决定。
private struct MenuBarMark: View {
    let state: OverallState
    @ObservedObject var clock: MarkClock

    var body: some View {
        Image(nsImage: HMark.menuBarImage(state, phase: state == .running ? clock.phase : 0))
            .accessibilityLabel(state.accessibilityLabel)
    }
}

/// MarkClock 驱动运行时横梁上的点逐帧右移。MenuBarExtra 的标签里放 TimelineView 会让状态栏项消失，
/// 只能用一个被标签单独观察的对象推帧；减少动态效果时不推帧。
@MainActor
final class MarkClock: ObservableObject {
    @Published private(set) var phase: Double = 0
    private var timer: Timer?

    func setRunning(_ running: Bool) {
        let animate = running && !Theme.Motion.reduce
        if !animate {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Theme.Motion.Duration.markFrame, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.phase = Date().timeIntervalSinceReferenceDate / Theme.Motion.Duration.bridge
            }
        }
    }
}
