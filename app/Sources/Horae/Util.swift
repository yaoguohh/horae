import AppKit
import SwiftUI

// SourceIcon：按 step id 关键字映射到打包的品牌图标(Contents/Resources/icons/<key>.png)。
enum SourceIcon {
    static func image(for id: String) -> NSImage? {
        let key = iconKey(for: id)
        guard let url = Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "icons")
            ?? Bundle.main.url(forResource: key, withExtension: "png")
        else { return nil }
        return NSImage(contentsOf: url)
    }

    static func iconKey(for id: String) -> String {
        let s = id.lowercased()
        if s.contains("brew") { return "brew" }
        if s.contains("npm") { return "npm" }
        if s.contains("claude") { return "claude" }
        if s.contains("codex") || s.contains("openai") { return "codex" }
        if s.contains("rust") || s.contains("cargo") { return "rustup" }
        if s.contains("pipx") || s.contains("pip") || s.contains("python") { return "pipx" }
        if s.contains("node") { return "node" }
        return "generic"
    }
}

// Format：时间/时长的人类可读渲染。
enum Format {
    static func clockTime(_ date: Date) -> String {
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(date) {
            day = "今天"
        } else if cal.isDateInYesterday(date) {
            day = "昨天"
        } else {
            let f = DateFormatter()
            f.dateFormat = "MM-dd"
            day = f.string(from: date)
        }
        let t = DateFormatter()
        t.dateFormat = "HH:mm"
        return "\(day) \(t.string(from: date))"
    }

    // countdown：距 due 的短格式(5h12m / 45m / ~8m)；已过则“待更新”(到点, 待下次触发执行)。
    static func countdown(to due: Date, now: Date = Date()) -> String {
        let secs = Int(due.timeIntervalSince(now))
        if secs <= 0 { return "待更新" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)h\(m)m" }
        if m < 10 { return "~\(max(m, 1))m" }
        return "\(m)m"
    }

    // elapsed：正在更新已用时(1m02s / 12s)。
    static func elapsed(since start: Date, now: Date = Date()) -> String {
        let secs = max(0, Int(now.timeIntervalSince(start)))
        let m = secs / 60
        let s = secs % 60
        return m > 0 ? String(format: "%dm%02ds", m, s) : "\(s)s"
    }
}
