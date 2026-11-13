import AppKit
import UserNotifications

// Notifier：原生通知。引擎已在 last-run.json 里算好 should_notify，这里只负责发与去重。
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let openLogAction = "OPEN_LOG"

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let openLog = UNNotificationAction(identifier: openLogAction, title: "查看日志", options: [.foreground])
        let cat = UNNotificationCategory(identifier: "HORAE_RUN", actions: [openLog], intentIdentifiers: [])
        center.setNotificationCategories([cat])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ lastRun: LastRun) {
        let content = UNMutableNotificationContent()
        let failed = lastRun.steps.filter(\.isUnsuccessful)
        // 标题与弹窗头部同一套说法；系统会在标题上方写出 app 名，这里不再重复“Horae”。
        content.title = switch failed.count {
        case 0: "更新完成"
        case 1: Format.adjoin(failed[0].label, "更新\(statusWord(failed[0].status))")
        default: "\(failed.count) 项需要处理"
        }
        content.body = body(for: lastRun)
        content.categoryIdentifier = "HORAE_RUN"
        if !failed.isEmpty { content.interruptionLevel = .timeSensitive }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // body：每步一行“源 状态 · 耗时”；有包级变更(二期)则附加。
    private func body(for lastRun: LastRun) -> String {
        lastRun.steps.map { step -> String in
            var line = "\(Format.adjoin(step.label, statusWord(step.status))) · \(Format.duration(step.duration))"
            if let first = step.changes.first {
                let extra = step.changes.count > 1 ? " 等 \(step.changes.count) 项" : ""
                if let from = first.from, let to = first.to {
                    line += "（\(first.name) \(from) → \(to)\(extra)）"
                }
            }
            return line
        }.joined(separator: "\n")
    }

    private func statusWord(_ status: String) -> String {
        switch status {
        case "success": return "成功"
        case "timeout": return "超时"
        default: return "失败"
        }
    }

    // 菜单栏 app 多在后台，仍要弹横幅。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == openLogAction {
            NSWorkspace.shared.open(Engine.logDir)
        }
        completionHandler()
    }
}
