import AppKit
import SwiftUI

/// 弹窗里的页面。日志、设置、管理来源都在同一个弹窗里换页，左上角返回上一级。
enum Page: Equatable {
    case main
    /// focus：打开时滚到并展开的那条记录（LogEntry.id）。
    case log(focus: String?)
    case settings
    /// focus：打开时滚到并标出的来源。
    case sources(focus: String?)

    /// 返回与 Esc 回到哪一页；主弹窗没有上一级。管理来源从设置进，回到设置。
    var parent: Page? {
        switch self {
        case .main: nil
        case .log, .settings: .main
        case .sources: .settings
        }
    }
}

/// 菜单栏弹窗：宽 344，高度随内容。主弹窗是来源表，次级页是运行日志、设置与管理来源。
struct PopoverView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var escFocused: Bool
    @StateObject private var flyouts = FlyoutModel()
    @State private var page: Page = .main
    /// 当前页面内容的高度，窗口按它收放。
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        content
            .padding(.bottom, Theme.Space.panelBottom)
            .frame(width: Theme.Metric.popoverWidth)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .coordinateSpace(name: FlyoutLayer.space)
            .overlay { FlyoutLayer() }
            // 窗口还没收回时内容贴顶，底色铺满整个窗口。
            .frame(maxHeight: .infinity, alignment: .top)
            .background { PanelBackground() }
            .background { WindowHeightFitter(height: contentHeight) }
            .environmentObject(flyouts)
            // MenuBarExtra(.window) 不像 NSMenu 那样按 esc 自动关闭; onExitCommand 接住 cancel(esc)。
            // onExitCommand 仅在视图获焦时触发(否则系统 ding), 故 focusable + onAppear 主动取焦;
            // focusEffectDisabled 去掉焦点环。dismiss 在 MenuBarExtra 内即关闭整个弹窗。
            .focusable()
            .focusEffectDisabled()
            .focused($escFocused)
            .onAppear {
                escFocused = true
                page = .main
                flyouts.close()
                store.popoverOpened()
            }
            .onExitCommand {
                // 先关弹出菜单，再从次级页返回上一级，主弹窗时关闭。
                if flyouts.open != nil {
                    flyouts.close()
                } else if let parent = page.parent {
                    navigate(parent)
                } else {
                    dismiss()
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .main: MainPage(navigate: navigate)
        case let .log(focus): LogPage(focus: focus, navigate: navigate)
        case .settings: SettingsPage(navigate: navigate)
        case let .sources(focus): SourcesPage(focus: focus, navigate: navigate)
        }
    }

    private func navigate(_ next: Page) {
        flyouts.close()
        page = next
    }
}

/// MenuBarExtra 的窗口只随内容长高，不随内容变矮（换到更矮的页面时窗口留在原高度）。
/// 这里在内容高度变化后把窗口的内容区收成内容的高度，顶边不动，弹窗仍挂在菜单栏下面。
private struct WindowHeightFitter: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let height = height
        DispatchQueue.main.async {
            guard height > 0, let window = view.window else { return }
            let frame = window.frame
            let content = window.contentRect(forFrameRect: frame)
            guard abs(content.height - height) > Theme.Metric.hairline else { return }
            var fitted = window.frameRect(forContentRect: NSRect(x: content.minX, y: content.minY, width: content.width, height: height))
            fitted.origin.y = frame.maxY - fitted.height
            window.setFrame(fitted, display: true)
        }
    }
}

/// 弹窗底：系统的弹出材质，上面压一层 panel，只透出少量模糊后的桌面。浅色与深色跟随系统。
private struct PanelBackground: View {
    var body: some View {
        ZStack {
            VisualEffectMaterial()
            Theme.Palette.panel
        }
        .ignoresSafeArea()
    }
}

private struct VisualEffectMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
