import SwiftUI

struct SourceCardView: View {
    @EnvironmentObject var store: Store
    let source: Source
    let current: Current?

    private var isUpdating: Bool { current?.running == true && current?.step == source.id }

    var body: some View {
        HStack(spacing: 9) {
            icon
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text(source.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(source.enabled ? .primary : .secondary)
                        .lineLimit(1)
                    if !isUpdating, let tag = statusTag(for: source) {
                        Text(tag.text)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tag.color)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(tag.color.opacity(0.16))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                if isUpdating { updatingLine } else { metaLine }
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(isUpdating ? Color.horaeAmber.opacity(0.12) : Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.horaeAmber.opacity(isUpdating ? 0.32 : 0), lineWidth: 1)
        )
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

    private var updatingLine: some View {
        VStack(alignment: .leading, spacing: 0.5) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let start = current?.startedAt ?? ctx.date
                Text("正在更新… \(Format.elapsed(since: start, now: ctx.date))")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.horaeAmber)
            }
            // 实时输出行(更新器自己的 Downloading…/changed N packages 等); 缺省回落到提示。
            if let line = current?.lastLine, !line.isEmpty {
                Text(line)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(line)
            } else {
                Text("建议稍候再启动此工具").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    private var metaLine: some View {
        Text(metaText).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
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
