import AppKit
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

/// 设置：第一行进管理来源；然后是通知、登录时打开、软件更新；底部是版本号和“退出 Horae”。
struct SettingsPage: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject private var updater: Updater
    let navigate: (Page) -> Void
    @AppStorage("notifyPolicy") private var notifyPolicy = NotifyPolicy.on_change.rawValue
    @State private var loginOn = LoginItem.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            SubpageHeader(title: "设置") { navigate(.main) }
            VStack(spacing: 0) {
                Button { navigate(.sources(focus: nil)) } label: {
                    SettingRow(icon: .stack, title: "管理来源", detail: "\(store.board().sources.count) 个来源") {
                        Icon.chevronRight.view(size: Theme.Metric.rowChevron).foregroundStyle(Theme.Palette.faint)
                    }
                }
                .buttonStyle(RowButtonStyle())
                Hairline()
                    .padding(.vertical, Theme.Space.separatorVertical)
                    .padding(.leading, Theme.Space.textIndent)
                    .padding(.trailing, Theme.Space.rowInset)
                SettingRow(icon: .bell, title: "通知", detail: "何时发送系统通知") {
                    FlyoutButton(owner: "notify", items: notifyItems) {
                        PillLabel(text: (NotifyPolicy(rawValue: notifyPolicy) ?? .on_change).label)
                    }
                    .buttonStyle(.plain)
                }
                SettingRow(icon: .power, title: "登录时打开", detail: "在菜单栏常驻") {
                    Toggle("登录时打开", isOn: Binding(get: { loginOn }, set: { on in
                        LoginItem.setEnabled(on)
                        // 注册可能失败（例如没有签名身份），开关以系统里的实际状态为准。
                        loginOn = LoginItem.isEnabled
                    }))
                    .toggleStyle(PaneSwitchStyle())
                    .labelsHidden()
                }
                // 版本号只在页脚写一次；按钮不叫“检查更新”，免得和更新来源混淆。
                SettingRow(icon: .download, title: "软件更新", detail: "后台自动检查") {
                    Button("检查新版本") { updater.checkForUpdates() }
                        .buttonStyle(ControlButtonStyle())
                        .disabled(!updater.canCheck)
                }
            }
            .padding(.top, Theme.Space.settingsTop)
            .padding(.horizontal, Theme.Space.listInset)
            .padding(.bottom, Theme.Space.scrollBottom)
            PageFooter {
                Text("Horae \(updater.version)").monospacedDigit()
                Spacer(minLength: 0)
                Button("退出 Horae") { NSApp.terminate(nil) }
                    .buttonStyle(ControlButtonStyle())
            }
        }
    }

    private func notifyItems() -> [FlyoutItem] {
        NotifyPolicy.allCases.map { policy in
            FlyoutItem(title: policy.label, checked: policy.rawValue == notifyPolicy) { notifyPolicy = policy.rawValue }
        }
    }
}

/// 设置的一行：图标列里一个线条图标，名称与一行说明，右侧一个控件。
private struct SettingRow<Trailing: View>: View {
    let icon: Icon
    let title: String
    let detail: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Space.column) {
            icon.view(size: Theme.Metric.settingIcon)
                .foregroundStyle(Theme.Palette.dim)
                .padding(.horizontal, Theme.Space.settingIconMargin)
            VStack(alignment: .leading, spacing: Theme.Space.subline) {
                Text(title)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Palette.ink)
                Text(detail)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.dim)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, Theme.Space.rowInset)
        .padding(.vertical, Theme.Space.settingVertical)
    }
}
