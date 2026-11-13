import AppKit
import SwiftUI

/// 管理来源：从设置进，返回回到设置。已添加的来源有命令预览、周期和开关；下面是可添加的预设；
/// 底部可以打开 recipes.toml。移除来源在行的右键菜单里，确认一次后才删。
struct SourcesPage: View {
    @EnvironmentObject var store: Store
    /// 从来源表的“修改周期…”进来时，滚到并标出的来源。
    let focus: String?
    let navigate: (Page) -> Void
    /// 已点过“添加”、配方还没重读完的预设，避免重复点击。
    @State private var adding: Set<String> = []
    /// 正在确认移除的来源。
    @State private var confirming: String?

    var body: some View {
        let board = store.board()
        let presets = available(board)
        VStack(spacing: 0) {
            SubpageHeader(title: "管理来源") { navigate(.settings) }
            ScrollViewReader { proxy in
                FittedScroll(maxHeight: Theme.Metric.pageMaxHeight) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(text: board.sources.isEmpty ? "还没有来源，从下面的预设里添加" : "已添加\u{3000}关掉开关后，自动和手动都会跳过")
                        ForEach(board.sources) { source in
                            // 从“修改周期…”进来时，那一行在这一页上一直标着。
                            ManagedRow(board: board, source: source, highlighted: focus == source.id, confirming: $confirming)
                            .id(source.id)
                        }
                        SectionLabel(text: presets.isEmpty ? "预设都已添加" : "可添加")
                        ForEach(presets) { preset in
                            PresetRow(preset: preset, adding: adding.contains(preset.id)) {
                                adding.insert(preset.id)
                                store.add(preset)
                            }
                        }
                    }
                    .padding(.top, Theme.Space.scrollTop)
                    .padding(.horizontal, Theme.Space.listInset)
                    .padding(.bottom, Theme.Space.scrollBottom)
                }
                .onAppear {
                    guard let focus else { return }
                    DispatchQueue.main.async { proxy.scrollTo(focus, anchor: .center) }
                }
            }
            ToolbarFooter {
                Button { NSWorkspace.shared.open(Engine.recipeURL) } label: {
                    ToolbarLabel(icon: .external, text: "在编辑器中打开 recipes.toml")
                }
                .buttonStyle(ToolbarButtonStyle())
                Spacer(minLength: 0)
            }
        }
    }

    /// 随 app 打包的预设里还没加入配方的那些，已安装的在前。
    private func available(_ board: Board) -> [Preset] {
        let present = Set(board.sources.map(\.id)).union(board.steps.keys)
        let rest = store.presets.filter { !present.contains($0.id) }
        return rest.filter(\.installed) + rest.filter { !$0.installed }
    }
}

/// 已添加的来源：品牌图标、名称与命令预览、周期下拉、开关。停用时图标去色、名称变淡。
private struct ManagedRow: View {
    @EnvironmentObject var store: Store
    let board: Board
    let source: Source
    let highlighted: Bool
    @Binding var confirming: String?
    @State private var hovered = false

    private var step: ConfigStep? { board.steps[source.id] }
    private var command: String { step.map { $0.shell ?? ($0.command ?? []).joined(separator: " ") } ?? "" }

    var body: some View {
        let removing = confirming == source.id
        HStack(spacing: Theme.Space.column) {
            SourceIconView(id: source.id, active: source.enabled)
            VStack(alignment: .leading, spacing: Theme.Space.subline) {
                Text(source.label)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(source.enabled ? Theme.Palette.ink : Theme.Palette.dim)
                    .help(source.label)
                Text(removing ? "命令和周期会从 recipes.toml 里一起删掉" : command)
                    .font(removing ? Theme.Typeface.caption : Theme.Typeface.mono)
                    .foregroundStyle(Theme.Palette.dim)
                    .help(removing ? "" : command)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            if removing {
                HStack(spacing: Theme.Space.actionsGap) {
                    Button("取消") { confirming = nil }
                    Button("移除") {
                        confirming = nil
                        store.remove(source.id)
                    }
                }
                .buttonStyle(ControlButtonStyle())
            } else {
                cadence
                Toggle("启用", isOn: Binding(get: { source.enabled }, set: { store.setEnabled(source.id, $0) }))
                    .toggleStyle(PaneSwitchStyle())
                    .labelsHidden()
                    .help(source.enabled ? "已启用" : "已停用：自动和手动都会跳过")
            }
        }
        .padding(.horizontal, Theme.Space.rowInset)
        .padding(.vertical, Theme.Space.rowVertical)
        .contentShape(Rectangle())
        .rowBackground(hovered || highlighted)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("移除此来源…") { confirming = source.id }
        }
    }

    /// 周期：常用档位里选；组合周期（如 1h30m）只读，改要去 recipes.toml。
    @ViewBuilder private var cadence: some View {
        if let text = step?.cadence {
            if let current = Cadence(text) {
                FlyoutButton(owner: "cadence:\(source.id)", items: { cadenceItems(current) }) {
                    PillLabel(text: current.sentence)
                }
                .buttonStyle(.plain)
                .help("周期")
            } else {
                PillLabel(text: text, choosable: false)
                    .help("组合周期请在 recipes.toml 里修改")
            }
        }
    }

    private func cadenceItems(_ current: Cadence) -> [FlyoutItem] {
        var choices = Cadence.choices
        if !choices.contains(current) {
            choices.append(current)
            choices.sort { $0.interval < $1.interval }
        }
        let id = source.id
        return choices.map { choice in
            FlyoutItem(title: choice.sentence, checked: choice == current) { store.setCadence(id, choice) }
        }
    }
}

/// 可添加的预设：品牌图标（未安装时去色）、名称与“周期 · 说明”、是否安装、添加按钮。
private struct PresetRow: View {
    let preset: Preset
    let adding: Bool
    let add: () -> Void

    var body: some View {
        let cadence = Cadence(preset.cadence)?.sentence ?? preset.cadence
        HStack(spacing: Theme.Space.column) {
            SourceIconView(id: preset.id, active: preset.installed)
            VStack(alignment: .leading, spacing: Theme.Space.subline) {
                Text(preset.label)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Palette.ink)
                Text("\(cadence) · \(preset.detail)")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.dim)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help([preset.label, preset.detail, preset.note].filter { !$0.isEmpty }.joined(separator: "\n\n"))
            if !preset.installed {
                Text("未安装")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.dim)
                    .fixedSize()
            }
            Button(adding ? "添加中" : "添加", action: add)
                .buttonStyle(ControlButtonStyle())
                .disabled(adding)
        }
        .padding(.horizontal, Theme.Space.rowInset)
        .padding(.vertical, Theme.Space.rowVertical)
        .hoverHighlight()
    }
}
