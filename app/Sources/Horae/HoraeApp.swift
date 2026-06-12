import SwiftUI

@main
struct HoraeApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(store)
                .tint(.horaeAccent)
                .preferredColorScheme(.dark) // 固定深色玻璃风
        } label: {
            // 菜单栏图标单色模板，正在更新时切到实心变体作提示。
            Image(systemName: store.current?.running == true
                ? "arrow.triangle.2.circlepath.circle.fill"
                : "arrow.triangle.2.circlepath")
        }
        .menuBarExtraStyle(.window)
    }
}
