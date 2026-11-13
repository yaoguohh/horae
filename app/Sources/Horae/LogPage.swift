import AppKit
import SwiftUI

/// 运行日志：近 14 天的执行按天分组，每条是品牌图标、时刻、名称、时长。未成功的条目可以展开看输出，
/// 带“重试”和“拷贝输出”；右上角可以只看未成功、打开日志文件夹。
struct LogPage: View {
    @EnvironmentObject var store: Store
    /// 打开时滚到并展开的记录；没有时展开最新一条未成功的。
    let focus: String?
    let navigate: (Page) -> Void
    @State private var onlyUnsuccessful = false
    /// 点过任一条以后，展开哪一条由 expanded 决定（nil 是全部收起）。
    @State private var expandedByUser = false
    @State private var expanded: String?

    var body: some View {
        let board = store.board()
        let entries = board.log.filter { !onlyUnsuccessful || $0.isUnsuccessful }
        let open = expandedByUser ? expanded : focus ?? board.log.first(where: \.isUnsuccessful)?.id
        VStack(spacing: 0) {
            SubpageHeader(title: "运行日志", back: { navigate(.main) }) {
                Button("只看未成功") { onlyUnsuccessful.toggle() }
                    .buttonStyle(ControlButtonStyle(selected: onlyUnsuccessful))
                    .accessibilityAddTraits(onlyUnsuccessful ? .isSelected : [])
                Button { NSWorkspace.shared.open(Engine.logDir) } label: {
                    Icon.folder.view(size: Theme.Metric.buttonIcon)
                }
                .buttonStyle(ControlButtonStyle(square: true))
                .help("打开日志文件夹")
            }
            ScrollViewReader { proxy in
                FittedScroll(maxHeight: Theme.Metric.pageMaxHeight) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if entries.isEmpty {
                            SectionLabel(text: onlyUnsuccessful ? "近 14 天没有未成功的记录" : "近 14 天没有运行记录")
                        }
                        ForEach(Self.days(entries, now: board.now), id: \.title) { day in
                            SectionLabel(text: day.title)
                            ForEach(day.entries) { entry in
                                LogRow(entry: entry, label: board.label(for: entry.source), open: entry.id == open) {
                                    expandedByUser = true
                                    expanded = entry.id == open ? nil : entry.id
                                }
                                .id(entry.id)
                                if entry.id == open, entry.isUnsuccessful {
                                    LogDetail(entry: entry, board: board).id(LogDetail.scrollID(entry.id))
                                }
                            }
                        }
                    }
                    .padding(.top, Theme.Space.scrollTop)
                    .padding(.horizontal, Theme.Space.listInset)
                    .padding(.bottom, Theme.Space.scrollBottom)
                }
                .onAppear {
                    guard let focus else { return }
                    // 只滚到刚好看得见：展开的输出整段露出来，上面同一轮的记录尽量留在视野里。
                    // 等第一次布局完成再滚，否则目标还没有位置。
                    let target = board.log.first { $0.id == focus }?.isUnsuccessful == true ? LogDetail.scrollID(focus) : focus
                    DispatchQueue.main.async { proxy.scrollTo(target) }
                }
            }
        }
    }

    private struct Day {
        let title: String
        var entries: [LogEntry]
    }

    /// 按天分组；日志本身是新的在前，同一天的记录相邻。
    private static func days(_ entries: [LogEntry], now: Date) -> [Day] {
        var days: [Day] = []
        for entry in entries {
            let title = Format.day(entry.time, now: now)
            if days.last?.title == title {
                days[days.count - 1].entries.append(entry)
            } else {
                days.append(Day(title: title, entries: [entry]))
            }
        }
        return days
    }
}

/// 一条记录：品牌图标、时刻、名称，右侧是时长；未成功的右侧是小红点、“失败”或“超时”和时长，整行可点开。
private struct LogRow: View {
    let entry: LogEntry
    let label: String
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        if entry.isUnsuccessful {
            Button(action: toggle) { content }
                .buttonStyle(RowButtonStyle())
                .accessibilityHint(open ? "收起输出" : "展开输出")
        } else {
            content.hoverHighlight()
        }
    }

    private var content: some View {
        HStack(spacing: Theme.Space.column) {
            SourceIconView(id: entry.source, size: Theme.Metric.logIcon)
                .padding(.horizontal, Theme.Space.smallIconMargin)
            Text(Format.clock(entry.time))
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.dim)
                .monospacedDigit()
                .frame(width: Theme.Metric.logTimeColumn, alignment: .leading)
            Text(label)
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(label)
            outcome
                .font(Theme.Typeface.caption)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.horizontal, Theme.Space.rowInset)
        .padding(.vertical, Theme.Space.logRowVertical)
    }

    @ViewBuilder private var outcome: some View {
        let duration = Format.duration(entry.duration)
        if entry.isUnsuccessful {
            HStack(spacing: Theme.Space.statusGap) {
                BadDot()
                Text("\(entry.outcomeWord)\u{3000}\(duration)")
            }
            .foregroundStyle(Theme.Palette.bad)
        } else {
            Text(duration).foregroundStyle(Theme.Palette.dim)
        }
    }
}

/// 展开的失败输出：一句原因与用时，输出全文（可选中），“重试”与“拷贝输出”。
private struct LogDetail: View {
    @EnvironmentObject var store: Store
    let entry: LogEntry
    let board: Board
    @State private var copied = false

    static func scrollID(_ entryID: String) -> String { "detail:\(entryID)" }

    var body: some View {
        let output = entry.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 0) {
            // 时长已写在这一行右边，这里只写原因。
            Text(entry.reasonText)
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.dim)
                .monospacedDigit()
            Text(output.isEmpty ? "这次没有捕获到输出" : output)
                .font(output.isEmpty ? Theme.Typeface.caption : Theme.Typeface.mono)
                .lineSpacing(Theme.Typeface.monoLineSpacing)
                .foregroundStyle(output.isEmpty ? Theme.Palette.dim : Theme.Palette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.Space.detailOutputTop)
                .padding(.bottom, Theme.Space.detailOutputBottom)
            HStack(spacing: Theme.Space.detailActionsGap) {
                Button("重试") { store.run(entry.source) }
                    .disabled(!canRetry)
                    .help(retryHelp)
                Button(copied ? "已拷贝" : "拷贝输出") { copy(output) }
                    .disabled(output.isEmpty)
            }
            .buttonStyle(ControlButtonStyle())
        }
        .padding(.vertical, Theme.Space.detailPadV)
        .padding(.horizontal, Theme.Space.detailPadH)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.detail, style: .continuous).fill(Theme.Palette.badTint)
        )
        .padding(.leading, Theme.Space.textIndent)
        .padding(.trailing, Theme.Space.rowInset)
        .padding(.bottom, Theme.Space.detailBottom)
    }

    /// 来源还在配方里、启用着、没有在跑或排队时才能重试（停用的来源手动更新也会被跳过）。
    private var canRetry: Bool {
        guard let source = board.source(entry.source) else { return false }
        return [.unsuccessful, .success, .never].contains(board.kind(of: source))
    }

    private var retryHelp: String {
        guard let source = board.source(entry.source) else { return "这个来源已移除" }
        switch board.kind(of: source) {
        case .disabled: return "来源已停用，自动和手动都会跳过"
        case .running: return "正在更新"
        case .queued: return "已在排队"
        default: return ""
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(Theme.Motion.Duration.copied))
            copied = false
        }
    }
}
