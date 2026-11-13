import AppKit
import SwiftUI

/// Horae 外观的唯一来源：视图里的颜色、字号、圆角、间距、尺寸、阴影、透明度和动效都取自这里，视图里不写字面量，
/// 换皮只改这个文件。数值以 docs/ui/ledger.html 的 CSS 变量为准。
/// 外观跟随系统，每个颜色令牌都有浅色和深色两个值。整体是灰白的，彩色只有三处：来源的品牌小图标、进行中的蓝、
/// 未成功的暗红。按钮、开关和菜单都不用实心蓝。
enum Theme {
    enum Palette {
        /// 弹窗底：压在系统材质上，只透出少量模糊后的桌面。
        static let panel = Color(light: .rgb(246, 246, 247, 0.9), dark: .rgb(38, 38, 41, 0.9))
        /// 正文与标题。
        static let ink = Color(light: .black(0.88), dark: .white(0.92))
        /// 次要文字、表头、时间、工具栏图标。
        static let dim = Color(light: .black(0.6), dark: .white(0.64))
        /// 最弱一级：行尾箭头、排队的虚线环、关着的开关轨道。
        static let faint = Color(light: .black(0.38), dark: .white(0.38))
        /// 分隔线，也是运行图形的底环。
        static let line = Color(light: .black(0.09), dark: .white(0.11))
        /// 行、工具栏按钮、返回按钮与菜单项的悬停底。
        static let hover = Color(light: .black(0.055), dark: .white(0.08))
        /// 灰色按钮与下拉的底。
        static let control = Color(light: .black(0.07), dark: .white(0.11))
        /// 进行中的蓝：运行图形、“正在更新”、标志里的 H、暂停时的恢复图标。
        static let accent = Color(light: .hex(0x005FD1), dark: .hex(0x6CB2FF))
        /// 淡蓝底：标志方块、打开着的“只看未成功”。
        static let accentTint = Color(light: .rgb(0, 104, 224, 0.12), dark: .rgb(108, 178, 255, 0.18))
        /// 未成功的暗红：小红点与“失败”“超时”。浅深两种底上的对比度都是 5.4:1。
        static let bad = Color(light: .hex(0xB23A30), dark: .hex(0xE5837A))
        /// 日志里展开的失败输出的底。
        static let badTint = Color(light: .rgb(178, 58, 48, 0.05), dark: .rgb(229, 131, 122, 0.08))
        /// 弹出菜单的底与外沿。
        static let menu = Color(light: .rgb(250, 250, 251, 0.98), dark: .rgb(48, 48, 52, 0.98))
        static let edge = Color(light: .black(0.16), dark: .white(0.18))
        /// 开关打开：浅色下是深灰轨道配白色圆钮，深色下是浅灰轨道配深色圆钮。
        static let switchOn = Color(light: .hex(0x3C3C40), dark: .hex(0xDCDCE0))
        static let switchOnKnob = Color(light: .hex(0xFFFFFF), dark: .hex(0x2A2A2D))
        /// 开关关着：faint 轨道配白色圆钮。
        static let switchOffKnob = Color(light: .hex(0xFFFFFF), dark: .hex(0xFFFFFF))
        static let menuShadow = Color(light: .black(0.24), dark: .black(0.24))
        static let knobShadow = Color(light: .black(0.3), dark: .black(0.3))
    }

    /// 字号只有 13、12、11 三档。数字一律等宽（monospacedDigit），命令与输出用等宽字体。
    enum Typeface {
        /// 来源名称、菜单项、设置项。
        static let body = Font.system(size: 13)
        /// 头部总述、次级页标题。
        static let title = Font.system(size: 13, weight: .semibold)
        /// 灰色按钮。
        static let control = Font.system(size: 12, weight: .medium)
        /// 底部工具栏的文字按钮、下拉里的值。
        static let callout = Font.system(size: 12)
        /// 表头、时间、说明。
        static let caption = Font.system(size: 11)
        /// 进行中的“正在更新”。
        static let captionMedium = Font.system(size: 11, weight: .medium)
        /// 次级页的分组标题。
        static let section = Font.system(size: 11, weight: .semibold)
        /// 命令与输出。
        static let mono = Font.system(size: 11, design: .monospaced)
        /// 多行输出把 11 号字排成 15 的行高。
        static let monoLineSpacing: CGFloat = 2
    }

    enum Radius {
        /// 标志方块。
        static let tile: CGFloat = 5
        /// 灰色按钮与返回按钮。
        static let control: CGFloat = 5.5
        /// 周期与通知的下拉。
        static let pill: CGFloat = 5
        /// 行的悬停底、工具栏按钮、菜单项。
        static let row: CGFloat = 6
        /// 日志里展开的失败输出。
        static let detail: CGFloat = 7
        /// 弹出菜单。
        static let menu: CGFloat = 8

        /// 来源品牌图标模仿 macOS 应用图标，圆角随尺寸等比：18 → 5。
        static func sourceIcon(_ size: CGFloat) -> CGFloat { size * 5 / 18 }
    }

    /// 间距。所有文字的左缘都落在 x = 40：listInset + rowInset + 图标列 + column。
    enum Space {
        /// 弹窗内容的左右缘：头部、表头、次级页标题从这里起。
        static let edge: CGFloat = 14
        /// 列表、滚动区和底栏的左右内边距；行的悬停底从这里起。
        static let listInset: CGFloat = 6
        /// 行内的左右边距。
        static let rowInset: CGFloat = 8
        /// 列与列之间、图标与文字之间。
        static let column: CGFloat = 8
        /// 图标列之后的文字缩进：分组标题、分隔线和日志里的输出都从名称的左缘起。
        static var textIndent: CGFloat { rowInset + Metric.iconColumn + column }
        /// 标题与下面一行补充之间。
        static let subline: CGFloat = 1
        /// 名称行与第二行说明之间。
        static let detailLine: CGFloat = 2
        /// 弹窗底边留白。
        static let panelBottom: CGFloat = 6

        /// 主弹窗头部。
        static let headerTop: CGFloat = 12
        static let headerBottom: CGFloat = 10
        /// 表头与分隔线之间。
        static let columnsBottom: CGFloat = 4
        /// 来源表上下。
        static let listVertical: CGFloat = 4
        /// 来源行与管理来源的行上下。
        static let rowVertical: CGFloat = 6
        /// 日志行上下。
        static let logRowVertical: CGFloat = 5
        /// 设置行上下。
        static let settingVertical: CGFloat = 7
        /// 行尾状态里图形与文字之间。
        static let statusGap: CGFloat = 5
        /// 第二行说明与行尾箭头之间。
        static let detailGap: CGFloat = 6
        /// 悬停时出现的操作按钮：距行顶，以及按钮之间。
        static let actionsTop: CGFloat = 4
        static let actionsGap: CGFloat = 4
        /// 小红点左右各留一点，和 14 宽的图形占位接近。
        static let dotMargin: CGFloat = 1

        /// 底栏：上方留白，分隔线以下的上、左、右内边距，按钮之间。
        static let footerTop: CGFloat = 2
        static let footerPadTop: CGFloat = 5
        static let footerLeading: CGFloat = 8
        static let footerTrailing: CGFloat = 9
        static let footerGap: CGFloat = 2
        /// 底栏文字按钮：左右内边距、图标与文字之间、文字与下拉箭头之间。
        static let toolbarLeading: CGFloat = 6
        static let toolbarTrailing: CGFloat = 8
        static let toolbarGap: CGFloat = 8
        static let toolbarChevronGap: CGFloat = 4
        /// 底栏文字按钮的图标左右各留 2，图标列与名称的图标列对齐。
        static let toolbarIconMargin: CGFloat = 2

        /// 次级页标题栏。
        static let subheaderTop: CGFloat = 11
        static let subheaderBottom: CGFloat = 9
        /// 返回按钮比图标列宽 4，左右各伸出 2。
        static let backOutset: CGFloat = 2
        /// 次级页滚动区上下（设置页顶部多留一点）。
        static let scrollTop: CGFloat = 4
        static let settingsTop: CGFloat = 6
        static let scrollBottom: CGFloat = 2
        /// 分组标题上下。
        static let sectionTop: CGFloat = 8
        static let sectionBottom: CGFloat = 3
        /// 设置页的分隔线上下。
        static let separatorVertical: CGFloat = 4
        /// 次级页的页脚：上方留白与内边距。
        static let pageFooterTop: CGFloat = 2
        static let pageFooterPadTop: CGFloat = 7
        static let pageFooterPadBottom: CGFloat = 2
        /// 小图标在 18 宽的图标列里居中时左右各留的空。
        static let smallIconMargin: CGFloat = 1
        static let settingIconMargin: CGFloat = 1.5

        /// 日志里展开的失败输出：下方留白、内边距、说明与输出之间、输出与按钮之间、按钮之间。
        static let detailBottom: CGFloat = 6
        static let detailPadV: CGFloat = 8
        static let detailPadH: CGFloat = 10
        static let detailOutputTop: CGFloat = 6
        static let detailOutputBottom: CGFloat = 8
        static let detailActionsGap: CGFloat = 6

        /// 灰色按钮的左右内边距。
        static let buttonPadH: CGFloat = 9
        /// 下拉：左、右内边距，值与上下箭头之间。
        static let pillLeading: CGFloat = 7
        static let pillTrailing: CGFloat = 4
        static let pillGap: CGFloat = 2

        /// 弹出菜单：内边距、菜单项左右内边距、勾选标记与文字之间、离开锚点的距离、离开弹窗边缘的最小距离。
        static let menuPad: CGFloat = 4
        static let menuItemPadH: CGFloat = 10
        static let menuCheckGap: CGFloat = 6
        static let menuGapBelow: CGFloat = 2
        static let menuGapAbove: CGFloat = 6
        static let menuMargin: CGFloat = 4
    }

    /// 尺寸。
    enum Metric {
        static let popoverWidth: CGFloat = 344
        /// 来源表的四列：图标、名称（其余宽度）、上次、下次最早。
        static let iconColumn: CGFloat = 18
        static let lastColumn: CGFloat = 52
        static let nextColumn: CGFloat = 76
        /// 日志行的时间列。
        static let logTimeColumn: CGFloat = 38
        /// 来源表最多显示的高度，超出时表内滚动；次级页的滚动区同理。
        static let listMaxHeight: CGFloat = 330
        static let pageMaxHeight: CGFloat = 430

        /// 来源品牌图标：来源表与管理来源 18，日志 16。
        static let sourceIcon: CGFloat = 18
        static let logIcon: CGFloat = 16
        /// 标志方块与里面的 H，H 的线宽按 16 格单位给出。
        static let tile: CGFloat = 18
        static let tileMark: CGFloat = 12
        static let tileMarkWeight: CGFloat = 2.2
        /// 菜单栏标志。
        static let menuBarMark: CGFloat = 16

        /// 行尾的状态图形与未成功的小红点。
        static let glyph: CGFloat = 14
        static let badDot: CGFloat = 6

        /// 灰色按钮与方形图标按钮高 22，底栏按钮高 26，下拉高 20。
        static let button: CGFloat = 22
        static let toolbarButton: CGFloat = 26
        static let pill: CGFloat = 20
        /// 图标：按钮里 14，工具栏 15，设置行 15，下拉 12，设置行尾箭头 12，说明行尾与下拉箭头 10。
        static let buttonIcon: CGFloat = 14
        static let toolIcon: CGFloat = 15
        static let settingIcon: CGFloat = 15
        static let pillIcon: CGFloat = 12
        static let rowChevron: CGFloat = 12
        static let smallChevron: CGFloat = 10

        /// 开关。
        static let switchSize = CGSize(width: 26, height: 15)
        static let knob: CGFloat = 12
        static let knobInset: CGFloat = 1.5

        /// 弹出菜单：菜单项高度、单选项的勾选标记。菜单宽度随内容，不设最小宽度。
        static let menuItemHeight: CGFloat = 24
        static let menuCheck: CGFloat = 12

        /// 发丝线。
        static let hairline: CGFloat = 0.5
    }

    enum Opacity {
        /// 已停用来源与未安装预设的品牌图标：去色后再压淡。
        static let inactiveIcon = 0.5
        /// 暂不可用的按钮。
        static let disabled = 0.4
        /// 灰色按钮悬停时整体压暗到 94%。
        static let hoverDim = 0.94
    }

    enum Shadow {
        static let menu = ShadowStyle(color: Palette.menuShadow, radius: 14, y: 10)
        static let knob = ShadowStyle(color: Palette.knobShadow, radius: 0.75, y: 0.5)
    }

    /// 系统开启“减少动态效果”时，转圈和标志的动画都停下。
    @MainActor
    enum Motion {
        static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

        /// 全部时长，单位秒。
        enum Duration {
            /// 运行图形转一圈。
            static let spin = 0.9
            /// 菜单栏标志横梁上的点走过一格。
            static let bridge = 0.9
            /// 菜单栏标志动画的帧间隔：状态栏图标不需要逐帧刷新。
            static let markFrame = 0.15
            /// “拷贝输出”变成“已拷贝”后停留多久。
            static let copied = 1.5
        }
    }
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}

extension View {
    func shadow(_ style: ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: 0, y: style.y)
    }
}

/// 一种外观下的颜色值：sRGB 分量与不透明度。
struct Tone: Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    static func hex(_ value: UInt32) -> Tone {
        rgb(Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF))
    }

    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ alpha: CGFloat = 1) -> Tone {
        Tone(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: alpha)
    }

    static func black(_ alpha: CGFloat) -> Tone { Tone(red: 0, green: 0, blue: 0, alpha: alpha) }
    static func white(_ alpha: CGFloat) -> Tone { Tone(red: 1, green: 1, blue: 1, alpha: alpha) }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

extension Color {
    /// 随系统外观切换的颜色：浅色外观取 light，深色外观取 dark。
    init(light: Tone, dark: Tone) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark.nsColor : light.nsColor
        })
    }
}
