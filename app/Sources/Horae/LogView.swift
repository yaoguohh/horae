import SwiftUI

struct LogView: View {
    let onClose: () -> Void
    @State private var entries: [LogEntry] = []
    @State private var loading = true
    @State private var expandedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            content
        }
        .frame(width: 336)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "chevron.left").font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text("运行日志").font(.system(size: 14, weight: .bold))
                Text(loading ? "读取中…" : "近 \(entries.count) 条 · 点击看详情 · 留 14 天").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { NSWorkspace.shared.open(Engine.logDir) } label: {
                Image(systemName: "folder").font(.system(size: 12))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("打开日志文件夹")
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
    }

    @ViewBuilder private var content: some View {
        if loading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 34)
        } else if entries.isEmpty {
            Text("暂无运行记录\n更新跑过之后这里会有时间线").font(.system(size: 10.5))
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.vertical, 30)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { rowGroup($0) }
                }
                .padding(.horizontal, 11).padding(.vertical, 4)
            }
            .frame(height: 320)
        }
    }

    private func rowGroup(_ e: LogEntry) -> some View {
        VStack(spacing: 0) {
            Button { toggle(e) } label: { rowLabel(e) }
                .buttonStyle(.plain)
            if expandedID == e.id { detailView(e) }
        }
        .overlay(Divider().opacity(0.22), alignment: .bottom)
    }

    private func rowLabel(_ e: LogEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: expandedID == e.id ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary).frame(width: 9)
            Text(timeStr(e.time)).font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary).frame(width: 70, alignment: .leading)
            Text(e.source).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
            Spacer(minLength: 6)
            if !e.duration.isEmpty, e.duration != "0s" {
                Text(e.duration).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text(statusText(e.status)).font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(statusColor(e.status))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(statusColor(e.status).opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 5.5)
        .contentShape(Rectangle())
    }

    private func detailView(_ e: LogEntry) -> some View {
        Group {
            if e.detail.isEmpty {
                Text(e.status == "success" ? "本次成功，无错误输出。" : "无更多输出。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    Text(e.detail)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 150)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(.leading, 17).padding(.trailing, 2).padding(.bottom, 7)
    }

    private func toggle(_ e: LogEntry) {
        expandedID = (expandedID == e.id) ? nil : e.id
    }

    private func load() {
        Task.detached(priority: .utility) {
            let es = Engine.recentLogEntries()
            await MainActor.run {
                entries = es
                loading = false
            }
        }
    }

    private func timeStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    private func statusText(_ s: String) -> String {
        switch s {
        case "success": return "成功"
        case "failure": return "失败"
        case "timeout": return "超时"
        default: return s
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "success": return Color(red: 0.20, green: 0.78, blue: 0.35)
        case "failure", "timeout": return Color(red: 1.0, green: 0.27, blue: 0.23)
        default: return .secondary
        }
    }
}
