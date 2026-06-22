import SwiftUI

@main
struct HoraeApp: App {
    @StateObject private var store = Store()
    @StateObject private var updater = Updater()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(store)
                .environmentObject(updater)
                .tint(.horaeAccent)
                .preferredColorScheme(.dark) // 固定深色玻璃风
        } label: {
            // 菜单栏图标始终用同一字形(尺寸/形状恒定)，正在更新时叠加 pulse 闪动作提示。
            // 不再切到 .circle.fill 变体: 那会把箭头缩进实心圆里、视觉上明显变小变形。
            Image(systemName: "arrow.triangle.2.circlepath")
                .symbolEffect(.pulse, options: .repeating, isActive: store.current?.running == true)
        }
        .menuBarExtraStyle(.window)
    }
}
