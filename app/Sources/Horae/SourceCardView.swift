import SwiftUI

struct SourceCardView: View {
    @EnvironmentObject var store: Store
    let source: Source
    let current: Current?
    @State private var expanded = false

    private var isUpdating: Bool { current?.running == true && current?.step == source.id }
    // 已点刷新、在排队等待执行(尚未轮到)。正在跑的源由 isUpdating 判定, 优先于排队态。
    private var isQueued: Bool { store.queued.contains(source.id) && !isUpdating }
    private var liveLines: [String] { current?.lastLines ?? [] }

    var body: some View {
        cardRow
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(isUpdating ? Color.horaeAmber.opacity(0.12)
                : isQueued ? Color.horaeAmber.opacity(0.06)
                : Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.horaeAmber.opacity(isUpdating ? 0.32 : isQueued ? 0.18 : 0), lineWidth: 1)
            )
            // step 结束(不再更新)时自动收起, 下次更新仍默认折叠。
            .onChange(of: isUpdating) { _, now in if !now { expanded = false } }
    }

    // 顶对齐：展开后中列变高时, 图标与右侧保持在顶部, 不随高度漂移到垂直居中。
    private var cardRow: some View {
        HStack(alignment: .top, spacing: 9) {
            icon
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text(source.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(source.enabled ? .primary : .secondary)
                        .lineLimit(1)
                    if !isUpdating, !isQueued, let tag = statusTag(for: source) {
                        Text(tag.text)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tag.color)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(tag.color.opacity(0.16))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                if isUpdating { updatingLine } else if isQueued { queuedLine } else { metaLine }
            }
            Spacer(minLength: 6)
            trailing
        }
    }

    // MARK: 图标

    private var icon: some View {
        Group {
            if let nsimg = SourceIcon.image(for: source.id) {
                Image(nsImage: nsimg).resizable().interpolation(.high)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(Color.gray)
                    Image(systemName: "shippingbox.fill").font(.system(size: 13)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .saturation(source.enabled ? 1 : 0)
        .opacity(source.enabled ? 1 : 0.55)
        .overlay {
            if isUpdating {
                RoundedRectangle(cornerRadius: 9).stroke(Color.horaeAmber, lineWidth: 2).padding(-2.5)
            }
        }
    }

    // MARK: 正在更新 / 元信息

    // 展开态用的行集合：折叠只给最后一行，展开给全部(同一个输出区，不另起带底色的模块)。
    private var shownLines: [String] {
        guard let last = liveLines.last else { return [] }
        return expanded ? liveLines : [last]
    }

    private var updatingLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let start = current?.startedAt ?? ctx.date
                Text("正在更新… \(Format.elapsed(since: start, now: ctx.date))")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.horaeAmber)
            }
            // 同一个输出区：折叠显示最新一行(截断)，点开就把这若干行用同一种等宽次要色文字直接铺开
            // (无底色/无边框)，展开时整行不截断、自动换行。缺省回落到提示。
            if shownLines.isEmpty {
                // 引擎会在 step 开始即 seed "$ <命令>" 首行, 正常跑动期间这里不会空;
                // 仅读到旧引擎写的无命令进度时作中性兜底。
                Text("准备执行…").font(.system(size: 9)).foregroundStyle(.tertiary)
            } else {
                Button { expanded.toggle() } label: {
                    HStack(alignment: .top, spacing: 4) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(shownLines.enumerated()), id: \.offset) { _, ln in
                                Text(ln)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(expanded ? nil : 1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "收起实时输出" : "展开实时输出")
            }
        }
    }

    private var metaLine: some View {
        Text(metaText).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
    }

    private var queuedLine: some View {
        Text("排队中… 等待当前更新完成")
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.horaeAmber.opacity(0.85))
            .lineLimit(1)
    }

    private var metaText: String {
        if !source.enabled { return "不自动更新" }
        if let t = source.lastSuccessAt, t > .distantPast + 1 {
            let dur = source.lastDuration.map { " · \($0)" } ?? ""
            return "\(Format.clockTime(t))\(dur)"
        }
        if source.status == "failure" || source.status == "timeout" {
            return "上次未成功，下次重试"
        }
        return "尚未运行"
    }

    // 未到期显示下次更新时刻; 已到期显示"待更新"(anacron 下精确触发时刻不可知, 不编造)。
    // trailing 区窄, 用紧凑格式避免截断: 今天的源只给时刻(14:00), 跨天的给日期(06-16)。
    private func nextText(_ due: Date) -> String {
        guard due > Date() else { return "待更新" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(due) ? "HH:mm" : "MM-dd"
        return f.string(from: due)
    }

    // MARK: 右侧

    private var trailing: some View {
        HStack(spacing: 8) {
            if isUpdating {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("运行中").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                    ProgressView().controlSize(.small)
                }
            } else if isQueued {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("排队中").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                    Image(systemName: "hourglass").font(.system(size: 11))
                        .foregroundStyle(Color.horaeAmber.opacity(0.8))
                }
            } else {
                if source.enabled, let due = source.nextDueAt {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("下次").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                        Text(nextText(due))
                            .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                if source.enabled {
                    Button { store.run(source.id) } label: {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11.5))
                            .frame(width: 23, height: 23)
                            .background(Color.primary.opacity(0.045))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("立即更新此源")
                }
                Toggle("", isOn: Binding(
                    get: { source.enabled },
                    set: { store.setEnabled(source.id, $0) }
                ))
                .toggleStyle(.switch).labelsHidden().controlSize(.mini).tint(.green)
            }
        }
    }
}
