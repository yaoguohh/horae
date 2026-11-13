import AppKit
import SwiftUI

// 弹窗共用的控件：按钮、开关、下拉、品牌图标、行的悬停底、次级页的标题栏与页脚、随内容伸缩的滚动区、弹出菜单。
// 外观全部取自 Theme。

// MARK: - 按钮

/// 灰色按钮：高 22、control 底，悬停或按下时整体压暗。selected 是打开着的切换（淡蓝底、蓝字），
/// square 是 22 见方的图标按钮。
struct ControlButtonStyle: ButtonStyle {
    var selected = false
    var square = false

    func makeBody(configuration: Configuration) -> some View {
        ControlButton(configuration: configuration, style: self)
    }
}

private struct ControlButton: View {
    let configuration: ButtonStyleConfiguration
    let style: ControlButtonStyle
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        let dimmed = isEnabled && (hovered || configuration.isPressed)
        configuration.label
            .font(Theme.Typeface.control)
            .lineLimit(1)
            .foregroundStyle(style.selected ? Theme.Palette.accent : Theme.Palette.ink)
            .padding(.horizontal, style.square ? 0 : Theme.Space.buttonPadH)
            .frame(width: style.square ? Theme.Metric.button : nil, height: Theme.Metric.button)
            .background(shape.fill(style.selected ? Theme.Palette.accentTint : Theme.Palette.control))
            .contentShape(shape)
            .colorMultiply(Color(white: dimmed ? Theme.Opacity.hoverDim : 1))
            .opacity(isEnabled ? 1 : Theme.Opacity.disabled)
            .onHover { hovered = $0 }
    }
}

/// 只有图标的按钮：平时透明，悬停时出现 hover 底。底栏的日志与设置、次级页的返回。
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = Theme.Metric.toolbarButton
    var radius: CGFloat = Theme.Radius.row
    var idle: Color = Theme.Palette.dim

    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration, style: self)
    }
}

private struct IconButton: View {
    let configuration: ButtonStyleConfiguration
    let style: IconButtonStyle
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.radius, style: .continuous)
        configuration.label
            .foregroundStyle(hovered ? Theme.Palette.ink : style.idle)
            .frame(width: style.size, height: style.size)
            .background(shape.fill(hovered || configuration.isPressed ? Theme.Palette.hover : .clear))
            .contentShape(shape)
            .onHover { hovered = $0 }
    }
}

/// 底栏左侧带图标的文字按钮：平时透明，悬停时出现 hover 底。
struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolbarButton(configuration: configuration)
    }
}

private struct ToolbarButton: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        configuration.label
            .font(Theme.Typeface.callout)
            .foregroundStyle(Theme.Palette.ink)
            .lineLimit(1)
            .padding(.leading, Theme.Space.toolbarLeading)
            .padding(.trailing, Theme.Space.toolbarTrailing)
            .frame(height: Theme.Metric.toolbarButton)
            .background(shape.fill(hovered || configuration.isPressed ? Theme.Palette.hover : .clear))
            .contentShape(shape)
            .onHover { hovered = $0 }
    }
}

/// 底栏文字按钮的内容：图标占一个图标列，文字落在名称的左缘上，可带一个下拉箭头。
struct ToolbarLabel: View {
    let icon: Icon
    let text: String
    var iconColor: Color = Theme.Palette.dim
    var chevron = false

    var body: some View {
        HStack(spacing: Theme.Space.toolbarGap) {
            icon.view(size: Theme.Metric.buttonIcon)
                .foregroundStyle(iconColor)
                .padding(.horizontal, Theme.Space.toolbarIconMargin)
            HStack(spacing: Theme.Space.toolbarChevronGap) {
                Text(text)
                if chevron {
                    Icon.chevronDown.view(size: Theme.Metric.smallChevron).foregroundStyle(Theme.Palette.dim)
                }
            }
        }
    }
}

/// 整行可点的按钮：设置页的“管理来源”、日志里未成功的条目。悬停时出现行的 hover 底。
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowButton(configuration: configuration)
    }
}

private struct RowButton: View {
    let configuration: ButtonStyleConfiguration

    var body: some View {
        configuration.label.hoverHighlight(pressed: configuration.isPressed)
    }
}

/// 悬停时出现行的 hover 底。
private struct HoverHighlight: ViewModifier {
    let pressed: Bool
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .rowBackground(hovered || pressed)
            .onHover { hovered = $0 }
    }
}

extension View {
    /// 悬停时出现行的 hover 底：不可点的行也有，和可点的行一致。
    func hoverHighlight(pressed: Bool = false) -> some View {
        modifier(HoverHighlight(pressed: pressed))
    }

    /// 行的悬停底。
    func rowBackground(_ active: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(active ? Theme.Palette.hover : .clear)
        )
    }
}

// MARK: - 开关与下拉

/// 开关：打开是 switchOn 轨道，关着是 faint 轨道配白色圆钮。没有实心蓝。
struct PaneSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(on ? Theme.Palette.switchOn : Theme.Palette.faint)
                .frame(width: Theme.Metric.switchSize.width, height: Theme.Metric.switchSize.height)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle()
                        .fill(on ? Theme.Palette.switchOnKnob : Theme.Palette.switchOffKnob)
                        .frame(width: Theme.Metric.knob, height: Theme.Metric.knob)
                        .shadow(Theme.Shadow.knob)
                        .padding(Theme.Metric.knobInset)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// 下拉的外观：control 底上一个值，右侧上下箭头。不可选时（例如组合周期）不画箭头。
struct PillLabel: View {
    let text: String
    var choosable = true

    var body: some View {
        HStack(spacing: Theme.Space.pillGap) {
            Text(text)
            if choosable {
                Icon.updown.view(size: Theme.Metric.pillIcon).foregroundStyle(Theme.Palette.dim)
            }
        }
        .font(Theme.Typeface.callout)
        .foregroundStyle(Theme.Palette.ink)
        .monospacedDigit()
        .lineLimit(1)
        .padding(.leading, Theme.Space.pillLeading)
        .padding(.trailing, choosable ? Theme.Space.pillTrailing : Theme.Space.pillLeading)
        .frame(height: Theme.Metric.pill)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous).fill(Theme.Palette.control))
        .fixedSize()
    }
}

// MARK: - 来源品牌图标

/// 来源的品牌小图标（SourceIcon，按 id 关键字映射）。已停用的来源与未安装的预设去色并压淡。
struct SourceIconView: View {
    let id: String
    var size: CGFloat = Theme.Metric.sourceIcon
    var active = true

    var body: some View {
        Group {
            if let image = SourceIcon.image(for: id) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sourceIcon(size), style: .continuous))
        .saturation(active ? 1 : 0)
        .opacity(active ? 1 : Theme.Opacity.inactiveIcon)
        .accessibilityHidden(true)
    }
}

// MARK: - 页面骨架

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.Palette.line).frame(height: Theme.Metric.hairline)
    }
}

/// 次级页的标题栏：返回按钮占图标列，标题落在名称的左缘上，右侧可放按钮。下方一条分隔线。
struct SubpageHeader<Extra: View>: View {
    let title: String
    let back: () -> Void
    @ViewBuilder let extra: Extra

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.column) {
                Button(action: back) { Icon.chevronLeft.view(size: Theme.Metric.buttonIcon) }
                    .buttonStyle(IconButtonStyle(size: Theme.Metric.button, radius: Theme.Radius.control, idle: Theme.Palette.ink))
                    .padding(.horizontal, -Theme.Space.backOutset)
                    .help("返回")
                Text(title)
                    .font(Theme.Typeface.title)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                extra
            }
            .padding(.top, Theme.Space.subheaderTop)
            .padding(.bottom, Theme.Space.subheaderBottom)
            .padding(.horizontal, Theme.Space.edge)
            Hairline()
        }
    }
}

extension SubpageHeader where Extra == EmptyView {
    init(title: String, back: @escaping () -> Void) {
        self.init(title: title, back: back) { EmptyView() }
    }
}

/// 次级页里的分组标题，落在名称的左缘上。
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typeface.section)
            .foregroundStyle(Theme.Palette.dim)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Space.sectionTop)
            .padding(.bottom, Theme.Space.sectionBottom)
            .padding(.leading, Theme.Space.textIndent)
            .padding(.trailing, Theme.Space.rowInset)
    }
}

/// 底栏：分隔线下一排按钮。主弹窗与管理来源页共用。
struct ToolbarFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: Theme.Space.footerGap) { content }
                .padding(.top, Theme.Space.footerPadTop)
                .padding(.leading, Theme.Space.footerLeading)
                .padding(.trailing, Theme.Space.footerTrailing)
        }
        .padding(.top, Theme.Space.footerTop)
    }
}

/// 次级页的页脚：分隔线下一行小字，文字落在名称的左缘上，右侧可放按钮。
struct PageFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: Theme.Space.column) { content }
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.dim)
                .padding(.top, Theme.Space.pageFooterPadTop)
                .padding(.bottom, Theme.Space.pageFooterPadBottom)
                .padding(.leading, Theme.Space.listInset + Theme.Space.textIndent)
                .padding(.trailing, Theme.Space.edge)
        }
        .padding(.top, Theme.Space.pageFooterTop)
    }
}

/// 高度随内容、到 maxHeight 为止的滚动区：内容不满时弹窗跟着变矮，超出时区内滚动。
struct FittedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical) { content }
            .scrollIndicators(.automatic)
            .frame(maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 弹出菜单

/// 弹出菜单的一项。checked 不为 nil 时是单选项，前面留出勾选标记的位置。
struct FlyoutItem {
    let title: String
    var checked: Bool?
    let action: () -> Void
}

enum FlyoutPlacement {
    /// 在锚点下方，右缘对齐锚点（行的“更多”、下拉）。
    case below
    /// 在锚点上方，左缘对齐锚点（底栏的暂停）。
    case above
}

/// 弹窗里的弹出菜单画在弹窗内部，悬停底是灰色。系统菜单的高亮色跟随系统强调色（默认是实心蓝），所以不用系统菜单。
/// 同一时刻最多开一个；点菜单外、按 Esc、换页都会关掉。
@MainActor
final class FlyoutModel: ObservableObject {
    struct Open {
        let owner: String
        let items: [FlyoutItem]
        /// 锚点在弹窗坐标里的位置。
        let anchor: CGRect
        let placement: FlyoutPlacement
    }

    @Published private(set) var open: Open?

    func isOpen(_ owner: String) -> Bool { open?.owner == owner }

    func toggle(_ owner: String, items: [FlyoutItem], anchor: CGRect, placement: FlyoutPlacement) {
        open = open?.owner == owner ? nil : Open(owner: owner, items: items, anchor: anchor, placement: placement)
    }

    func close() { open = nil }
}

/// 点开一个弹出菜单的按钮。按钮外观由调用方的 buttonStyle 决定。
struct FlyoutButton<Label: View>: View {
    @EnvironmentObject private var flyouts: FlyoutModel
    let owner: String
    var placement: FlyoutPlacement = .below
    let items: () -> [FlyoutItem]
    @ViewBuilder let label: Label
    @State private var frame: CGRect = .zero

    var body: some View {
        Button {
            flyouts.toggle(owner, items: items(), anchor: frame, placement: placement)
        } label: {
            label
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FlyoutLayer.space)) } action: { frame = $0 }
    }
}

/// 画在弹窗最上层的弹出菜单，连同接住“点菜单外”的透明层。放不下时翻到锚点的另一侧。
struct FlyoutLayer: View {
    nonisolated static let space = "popover"
    @EnvironmentObject private var flyouts: FlyoutModel

    var body: some View {
        if let open = flyouts.open {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { flyouts.close() }
                    // 对齐参考线的闭包不在主线程隔离里，只捕获值类型。
                    let anchor = open.anchor, placement = open.placement, size = geo.size
                    FlyoutMenu(items: open.items) { flyouts.close() }
                        .alignmentGuide(.leading) { d in -Self.x(anchor, placement, width: d.width, in: size) }
                        .alignmentGuide(.top) { d in -Self.y(anchor, placement, height: d.height, in: size) }
                }
            }
        }
    }

    private nonisolated static func x(_ anchor: CGRect, _ placement: FlyoutPlacement, width: CGFloat, in size: CGSize) -> CGFloat {
        let wanted = placement == .below ? anchor.maxX - width : anchor.minX
        return min(max(wanted, Theme.Space.menuMargin), size.width - Theme.Space.menuMargin - width)
    }

    private nonisolated static func y(_ anchor: CGRect, _ placement: FlyoutPlacement, height: CGFloat, in size: CGSize) -> CGFloat {
        let below = anchor.maxY + Theme.Space.menuGapBelow
        let above = anchor.minY - Theme.Space.menuGapAbove - height
        let fitsBelow = below + height <= size.height - Theme.Space.menuMargin
        let fitsAbove = above >= Theme.Space.menuMargin
        let wanted = switch placement {
        case .below: fitsBelow || !fitsAbove ? below : above
        case .above: fitsAbove || !fitsBelow ? above : below
        }
        return min(max(wanted, Theme.Space.menuMargin), size.height - Theme.Space.menuMargin - height)
    }
}

private struct FlyoutMenu: View {
    let items: [FlyoutItem]
    let close: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        let checkable = items.contains { $0.checked != nil }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                FlyoutRow(item: items[i], checkable: checkable) {
                    close()
                    items[i].action()
                }
            }
        }
        .padding(Theme.Space.menuPad)
        .fixedSize()
        .background(shape.fill(Theme.Palette.menu))
        .overlay(shape.stroke(Theme.Palette.edge, lineWidth: Theme.Metric.hairline))
        .shadow(Theme.Shadow.menu)
    }
}

private struct FlyoutRow: View {
    let item: FlyoutItem
    let checkable: Bool
    let choose: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: choose) {
            HStack(spacing: Theme.Space.menuCheckGap) {
                if checkable {
                    Icon.check.view(size: Theme.Metric.menuCheck).opacity(item.checked == true ? 1 : 0)
                }
                Text(item.title).lineLimit(1)
            }
            .font(Theme.Typeface.body)
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, Theme.Space.menuItemPadH)
            // 菜单宽度随最长的一项，各项铺满这个宽度，悬停底一样宽。
            .frame(maxWidth: .infinity, minHeight: Theme.Metric.menuItemHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(hovered ? Theme.Palette.hover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(item.checked == true ? .isSelected : [])
    }
}
