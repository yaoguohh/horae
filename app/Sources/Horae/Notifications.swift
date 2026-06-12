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
        let failed = lastRun.summary.failed + lastRun.summary.timeout
        content.title = failed > 0 ? "Horae 更新有失败" : "Horae 更新完成"
        content.body = body(for: lastRun)
        content.categoryIdentifier = "HORAE_RUN"
        if failed > 0 { content.interruptionLevel = .timeSensitive }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // body：每步一行“源 状态 · 耗时”；有包级变更(二期)则附加。
    private func body(for lastRun: LastRun) -> String {
        lastRun.steps.map { step -> String in
            var line = "\(step.label) \(statusWord(step.status)) · \(step.duration)"
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
