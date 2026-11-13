import SwiftUI

/// 主弹窗：头部一句总述，来源表（图标、名称、上次、下次最早），底栏是暂停或恢复、日志、设置。
struct MainPage: View {
    @EnvironmentObject var store: Store
    let navigate: (Page) -> Void
    /// 进行中那一行的输出是否展开成最近几行。
    @State private var liveOpen = false

    var body: some View {
        let board = store.board()
        // 运行时每秒重算一次，已用时间跟着走；其余时候不刷新。
        if board.running != nil {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in page(store.board(now: ctx.date)) }
        } else {
            page(board)
        }
    }

    private func page(_ board: Board) -> some View {
        VStack(spacing: 0) {
            header(board)
            columns
            FittedScroll(maxHeight: Theme.Metric.listMaxHeight) {
                VStack(spacing: 0) {
                    ForEach(board.sources) { source in
                        SourceRow(board: board, source: source, liveOpen: $liveOpen, navigate: navigate)
                    }
                }
                .padding(.vertical, Theme.Space.listVertical)
                .padding(.horizontal, Theme.Space.listInset)
            }
            MainFooter(board: board, navigate: navigate)
        }
    }

    private func header(_ board: Board) -> some View {
        let verdict = board.verdict(at: board.now)
        return HStack(spacing: Theme.Space.column) {
            BrandTile()
            VStack(alignment: .leading, spacing: Theme.Space.subline) {
                Text(verdict.title)
                    .font(Theme.Typeface.title)
                    .foregroundStyle(Theme.Palette.ink)
                Text(verdict.subtitle)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.dim)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("\(verdict.title)\n\(verdict.subtitle)")
            Button("全部更新") { store.runAll() }
                .buttonStyle(ControlButtonStyle())
        }
        .padding(.top, Theme.Space.headerTop)
        .padding(.bottom, Theme.Space.headerBottom)
        .padding(.horizontal, Theme.Space.edge)
    }

    /// 表头与行共用同一组列宽。
    private var columns: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.column) {
                Text("来源")
                    .padding(.leading, Theme.Metric.iconColumn + Theme.Space.column)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("上次").frame(width: Theme.Metric.lastColumn, alignment: .trailing)
                Text("下次最早").frame(width: Theme.Metric.nextColumn, alignment: .trailing)
            }
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Palette.dim)
            .lineLimit(1)
            .padding(.horizontal, Theme.Space.edge)
            .padding(.bottom, Theme.Space.columnsBottom)
            Hairline()
        }
    }
}

// MARK: - 来源行

/// 一个来源一行。成功、尚未运行、停用的行右侧是两列时间；进行中、排队、未成功的行右侧是带图形的状态，
/// 进行中和未成功多一行说明。悬停时两列时间的位置换成“更新”（未成功是“重试”，停用是“启用”）和“更多”。
private struct SourceRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var flyouts: FlyoutModel
    let board: Board
    let source: Source
    @Binding var liveOpen: Bool
    let navigate: (Page) -> Void
    @State private var hovered = false

    private var kind: SourceKind { board.kind(of: source) }
    private var menuOwner: String { "row:\(source.id)" }
    /// 进行中与排队没有行内操作：引擎不能取消命令，重复点更新也只会再排一次。
    private var hasActions: Bool { kind != .running && kind != .queued }
    private var twoLine: Bool { kind == .running || kind == .unsuccessful }

    var body: some View {
        // “更多”菜单开着时，这一行保持悬停的样子。
        let active = hovered || flyouts.isOpen(menuOwner)
        HStack(alignment: twoLine ? .top : .center, spacing: Theme.Space.column) {
            SourceIconView(id: source.id, active: source.enabled)
            VStack(alignment: .leading, spacing: Theme.Space.detailLine) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.column) {
                    Text(source.label)
                        .font(Theme.Typeface.body)
                        .foregroundStyle(source.enabled ? Theme.Palette.ink : Theme.Palette.dim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(source.label)
                    trailing
                        .opacity(hasActions && active ? 0 : 1)
                }
                detail
            }
        }
        .padding(.horizontal, Theme.Space.rowInset)
        .padding(.vertical, Theme.Space.rowVertical)
        .rowBackground(active)
        .overlay(alignment: .topTrailing) {
            if hasActions, active {
                actions
                    .padding(.top, Theme.Space.actionsTop)
                    .padding(.trailing, Theme.Space.rowInset)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    // MARK: 右侧

    @ViewBuilder private var trailing: some View {
        switch kind {
        case .running:
            HStack(spacing: Theme.Space.statusGap) {
                RunningGlyph()
                Text("正在更新\u{3000}\(elapsed)")
            }
            .font(Theme.Typeface.captionMedium)
            .foregroundStyle(Theme.Palette.accent)
            .monospacedDigit()
            .fixedSize()
        case .queued:
            HStack(spacing: Theme.Space.statusGap) {
                QueuedGlyph()
                Text("排队中")
            }
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Palette.dim)
            .fixedSize()
        case .unsuccessful:
            HStack(spacing: Theme.Space.statusGap) {
                BadDot()
                Text(source.outcomeWord)
            }
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Palette.bad)
            .fixedSize()
        case .success, .never, .disabled:
            times
        }
    }

    private var times: some View {
        let earliest = board.earliest(of: source)
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Space.column) {
            Text(board.lastText(of: source))
                .frame(width: Theme.Metric.lastColumn, alignment: .trailing)
            Text(board.nextText(of: source))
                // 到期了还没跑，用正文色提醒；暂停期间不算。
                .foregroundStyle(earliest == .due ? Theme.Palette.ink : Theme.Palette.dim)
                .frame(width: Theme.Metric.nextColumn, alignment: .trailing)
                .help(isShifted(earliest) ? "因暂停顺延" : "")
        }
        .font(Theme.Typeface.caption)
        .foregroundStyle(Theme.Palette.dim)
        .monospacedDigit()
        .lineLimit(1)
    }

    private func isShifted(_ earliest: Earliest) -> Bool {
        if case .at(_, true) = earliest { return true }
        return false
    }

    private var elapsed: String {
        guard let start = board.running?.startedAt else { return "" }
        return Format.elapsed(from: start, to: board.now)
    }

    // MARK: 第二行

    @ViewBuilder private var detail: some View {
        switch kind {
        case .running:
            let lines = board.running?.lastLines ?? []
            Button { liveOpen.toggle() } label: {
                DetailLine(
                    text: liveOpen ? lines.joined(separator: "\n") : lines.last ?? "",
                    open: liveOpen, mono: true
                )
            }
            .buttonStyle(.plain)
            .help(liveOpen ? "收起实时输出" : "展开实时输出")
        case .unsuccessful:
            Button {
                navigate(.log(focus: board.failedEntry(of: source.id)?.id))
            } label: {
                DetailLine(text: board.failureLine(of: source), open: false, mono: false)
            }
            .buttonStyle(.plain)
            .help("查看输出")
        default:
            EmptyView()
        }
    }

    // MARK: 悬停操作

    private var actions: some View {
        HStack(spacing: Theme.Space.actionsGap) {
            if kind == .disabled {
                Button("启用") { store.setEnabled(source.id, true) }
            } else {
                Button(kind == .unsuccessful ? "重试" : "更新") { store.run(source.id) }
                FlyoutButton(owner: menuOwner, items: menuItems) {
                    Icon.more.view(size: Theme.Metric.buttonIcon)
                }
                .buttonStyle(ControlButtonStyle(square: true))
                .help("更多")
            }
        }
        .buttonStyle(ControlButtonStyle())
    }

    private func menuItems() -> [FlyoutItem] {
        let id = source.id
        let entry = board.latestEntry(of: id)?.id
        return [
            FlyoutItem(title: "查看日志") { navigate(.log(focus: entry)) },
            FlyoutItem(title: "修改周期") { navigate(.sources(focus: id)) },
            FlyoutItem(title: "停用") { store.setEnabled(id, false) },
        ]
    }
}

/// 名称下面那一行说明：灰色小字，右端一个箭头。展开时显示全部行。
private struct DetailLine: View {
    let text: String
    let open: Bool
    let mono: Bool

    var body: some View {
        HStack(alignment: open ? .top : .center, spacing: Theme.Space.detailGap) {
            Text(text)
                .font(mono ? Theme.Typeface.mono : Theme.Typeface.caption)
                .monospacedDigit()
                .lineLimit(open ? nil : 1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: open)
                .frame(maxWidth: .infinity, alignment: .leading)
            (open ? Icon.chevronDown : Icon.chevronRight).view(size: Theme.Metric.smallChevron)
                .foregroundStyle(Theme.Palette.faint)
        }
        .foregroundStyle(Theme.Palette.dim)
        .contentShape(Rectangle())
    }
}

// MARK: - 底栏

/// 底栏：左边暂停自动更新（暂停后变成恢复，并写明暂停到何时），右边日志与设置。
private struct MainFooter: View {
    @EnvironmentObject var store: Store
    let board: Board
    let navigate: (Page) -> Void

    var body: some View {
        ToolbarFooter {
            if board.paused {
                Button { store.resume() } label: {
                    ToolbarLabel(icon: .play, text: "恢复自动更新", iconColor: Theme.Palette.accent)
                }
                .buttonStyle(ToolbarButtonStyle())
                Text(board.pauseNote)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.dim)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                FlyoutButton(owner: "pause", placement: .above, items: pauseItems) {
                    ToolbarLabel(icon: .pause, text: "暂停自动更新", chevron: true)
                }
                .buttonStyle(ToolbarButtonStyle())
            }
            Spacer(minLength: Theme.Space.footerGap)
            Button { navigate(.log(focus: nil)) } label: { Icon.log.view(size: Theme.Metric.toolIcon) }
                .buttonStyle(IconButtonStyle())
                .help("运行日志")
            Button { navigate(.settings) } label: { Icon.gear.view(size: Theme.Metric.toolIcon) }
                .buttonStyle(IconButtonStyle())
                .help("设置")
        }
    }

    /// 暂停只拦自动调度，手动更新照常。时刻在点下菜单项时取。
    private func pauseItems() -> [FlyoutItem] {
        [
            FlyoutItem(title: "暂停 1 小时") { store.pause(until: Date().addingTimeInterval(3600)) },
            FlyoutItem(title: "暂停到今天结束") {
                if let end = Calendar.current.dateInterval(of: .day, for: Date())?.end { store.pause(until: end) }
            },
            FlyoutItem(title: "暂停直到手动恢复") { store.pause(until: nil) },
        ]
    }
}
