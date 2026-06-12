import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var store: Store
    @State private var showSettings = false
    @State private var showLog = false
    @State private var showSources = false
    @AppStorage("notifyPolicy") private var notifyPolicy = "on_change"

    private let accent = Color.horaeAccent
    private var sources: [Source] { store.status?.sources ?? [] }
    private let red = Color(red: 1.0, green: 0.27, blue: 0.23)

    var body: some View {
        Group {
            if showSettings {
                SettingsView(onClose: { showSettings = false })
            } else if showLog {
                LogView(onClose: { showLog = false })
            } else if showSources {
                SourceManageView(onClose: { showSources = false })
            } else {
                main
            }
        }
        .frame(width: 336)
    }

    private var main: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            actionRow
            summaryRow
            cards
            footer
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(accent)
                .frame(width: 23, height: 23)
                .overlay(Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text("Horae").font(.system(size: 13.5, weight: .bold))
                Text("更新编排 · \(sources.count) 源").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if let lr = store.lastRun, lr.finishedAt > .distantPast + 1 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("上次同步").font(.system(size: 8.5)).foregroundStyle(.tertiary)
                    Text(timeOnly(lr.finishedAt)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            iconButton("list.bullet") { showSources = true }
            iconButton("gearshape") { showSettings = true }
        }
        .padding(.horizontal, 12).padding(.top, 11).padding(.bottom, 9)
    }

    // MARK: 操作行（全部更新克制为淡色按钮，不占满整行）

    private var actionRow: some View {
        HStack(spacing: 7) {
            Button(action: { store.runAll() }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11.5, weight: .semibold))
                    Text("全部更新").font(.system(size: 11.5, weight: .semibold))
                }
                .frame(height: 27).padding(.horizontal, 11)
                .foregroundStyle(accent)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(accent.opacity(0.22), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            pausePill
            Spacer()
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var paused: Bool { store.status?.paused == true }

    private var pausePill: some View {
        Menu {
            if paused {
                Button("恢复自动更新") { store.resume() }
            } else {
                Button("暂停 1 小时") { store.pause(until: Date().addingTimeInterval(3600)) }
                Button("暂停到今天结束") { store.pause(until: endOfToday()) }
                Button("暂停直到手动恢复") { store.pause(until: nil) }
            }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(paused ? Color.secondary : Color.green).frame(width: 5, height: 5)
                Text(paused ? "已暂停" : "运行中").font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.tertiary)
            }
            .frame(height: 27).padding(.horizontal, 10)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: 汇总

    private var summaryRow: some View {
        let ok = sources.filter { $0.enabled && $0.status == "success" }.count
        let updating = store.current?.running == true ? 1 : 0
        let failed = sources.filter { $0.enabled && ($0.status == "failure" || $0.status == "timeout") }.count
        let due = sources.filter { $0.enabled && $0.due && $0.status != "failure" && $0.status != "timeout" }.count
        let off = sources.filter { !$0.enabled }.count
        return HStack(spacing: 10) {
            summaryItem(ok, "正常", .primary)
            if updating > 0 { summaryItem(updating, "更新中", .horaeAmber) }
            if failed > 0 { summaryItem(failed, "失败", red) }
            if due > 0 { summaryItem(due, "即将到期", .primary) }
            if off > 0 { summaryItem(off, "已关闭", .secondary) }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.bottom, 7)
    }

    private func summaryItem(_ n: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(n)").font(.system(size: 10.5, weight: .semibold, design: .monospaced)).foregroundStyle(color)
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    // MARK: 卡片（少量源直接 VStack，避免 ScrollView 在自适应弹窗里塌成 0 高）

    private var cards: some View {
        Group {
            if sources.isEmpty {
                Text("未发现更新源\n确认 ~/.config/horae/recipes.toml 已配置")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.vertical, 22)
            } else if sources.count <= 7 {
                cardList
            } else {
                ScrollView { cardList }.frame(height: 340)
            }
        }
    }

    private var cardList: some View {
        VStack(spacing: 4) {
            ForEach(sources) { source in
                SourceCardView(source: source, current: store.current)
                    .environmentObject(store)
            }
        }
        .padding(.horizontal, 9).padding(.bottom, 7)
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 13) {
            footerButton("doc.text", "日志") { showLog = true }
            notifyMenu
            Spacer()
            footerButton("power", "退出") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .overlay(Divider().opacity(0.35), alignment: .top)
    }

    private var notifyMenu: some View {
        Menu {
            ForEach(NotifyPolicy.allCases) { p in
                Button(action: { notifyPolicy = p.rawValue }) {
                    if notifyPolicy == p.rawValue { Label(p.label, systemImage: "checkmark") } else { Text(p.label) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bell").font(.system(size: 11))
                Text("通知 ").font(.system(size: 10.5)) + Text(NotifyPolicy(rawValue: notifyPolicy)?.label ?? "有变更时").font(.system(size: 10.5, weight: .semibold)).foregroundColor(accent)
                Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: 小部件

    private func iconButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12))
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func footerButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(label).font(.system(size: 10.5))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func timeOnly(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    private func endOfToday() -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return cal.date(byAdding: .day, value: 1, to: start) ?? Date().addingTimeInterval(3600)
    }
}
