import SwiftUI

enum NotifyPolicy: String, CaseIterable, Identifiable {
    case always, on_change, on_failure, never
    var id: String { rawValue }
    var label: String {
        switch self {
        case .always: return "总是"
        case .on_change: return "有变更时"
        case .on_failure: return "仅失败时"
        case .never: return "从不"
        }
    }
}

struct SettingsView: View {
    let onClose: () -> Void
    @AppStorage("notifyPolicy") private var notifyPolicy = NotifyPolicy.on_change.rawValue
    @State private var loginOn = LoginItem.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            VStack(spacing: 6) {
                notifyRow
                loginRow
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 9)
            Text("Horae · 单机版").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity).padding(.bottom, 11)
        }
        .frame(width: 336)
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
                Text("设置").font(.system(size: 14, weight: .bold))
                Text("通知 · 启动").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
    }

    private var notifyRow: some View {
        settingRow(symbol: "bell", title: "通知", subtitle: "何时发送系统通知") {
            Menu {
                ForEach(NotifyPolicy.allCases) { p in
                    Button(action: { notifyPolicy = p.rawValue }) {
                        if notifyPolicy == p.rawValue { Label(p.label, systemImage: "checkmark") } else { Text(p.label) }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(NotifyPolicy(rawValue: notifyPolicy)?.label ?? "有变更时").font(.system(size: 11.5, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 9).frame(height: 24)
                .background(Color.primary.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    private var loginRow: some View {
        settingRow(symbol: "power", title: "开机自启", subtitle: "登录后自动在菜单栏常驻") {
            Toggle("", isOn: $loginOn)
                .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(.green)
                .onChange(of: loginOn) { _, on in LoginItem.setEnabled(on) }
        }
    }

    private func settingRow<Trailing: View>(
        symbol: String, title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Color.horaeAccent)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
