import SwiftUI

extension Color {
    // 固定深色玻璃风：强调色锁为一档蓝，不再可自定义。
    static let horaeAccent = Color(red: 0.27, green: 0.61, blue: 1.0)
    // 正在更新固定用暖橙(纯"进行中"语义)。
    static let horaeAmber = Color(red: 1.0, green: 0.62, blue: 0.20)
}

// statusColor：源状态点/标签颜色。
func statusColor(for source: Source) -> Color {
    if !source.enabled { return .secondary }
    switch source.status {
    case "success": return Color(red: 0.20, green: 0.78, blue: 0.35)
    case "failure", "timeout": return Color(red: 1.0, green: 0.27, blue: 0.23)
    default: return source.due ? .horaeAccent : .secondary
    }
}

func statusTag(for source: Source) -> (text: String, color: Color)? {
    if !source.enabled { return ("已关闭", .secondary) }
    switch source.status {
    case "success": return ("成功", statusColor(for: source))
    case "failure": return ("失败 · 码 \(source.lastExitCode)", statusColor(for: source))
    case "timeout": return ("超时", statusColor(for: source))
    case "never": return source.due ? ("即将", .horaeAccent) : ("待跑", .secondary)
    default: return nil
    }
}
