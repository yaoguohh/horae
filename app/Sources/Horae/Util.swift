import AppKit
import SwiftUI

// SourceIcon：按 step id 关键字映射到打包的品牌图标(Contents/Resources/icons/<key>.png)。
// 来源表每行都画一次，按 key 缓存，避免每次重绘都读盘。
@MainActor
enum SourceIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for id: String) -> NSImage? {
        let key = iconKey(for: id)
        if let hit = cache[key] { return hit }
        guard let url = Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "icons")
            ?? Bundle.main.url(forResource: key, withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else { return nil }
        cache[key] = image
        return image
    }

    nonisolated static func iconKey(for id: String) -> String {
        let s = id.lowercased()
        if s.contains("hermes") { return "hermes" }
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

// Format：时间与时长的中文写法。列里用绝对时间，今天只写时刻；数字配等宽数字显示。
enum Format {
    private static let clockStyle = Date.VerbatimFormatStyle(
        format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        timeZone: .current, calendar: .current
    )
    private static let monthDayStyle = Date.VerbatimFormatStyle(
        format: "\(month: .twoDigits)-\(day: .twoDigits)", timeZone: .current, calendar: .current
    )

    /// 相对 now 的日子：今天、明天、昨天，其余为 nil。
    private static func relativeDay(_ date: Date, now: Date) -> String? {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return "今天" }
        if let d = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: d) { return "明天" }
        if let d = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: d) { return "昨天" }
        return nil
    }

    /// 时刻：“09:12”。
    static func clock(_ date: Date) -> String { date.formatted(clockStyle) }

    /// 来源表的两列：今天只写“20:04”，明天写“明天 09:12”，其余只写“11-16”，放得进 52 和 76 宽的列。
    static func column(_ date: Date, now: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return date.formatted(clockStyle) }
        if let d = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: d) {
            return "明天 \(date.formatted(clockStyle))"
        }
        return date.formatted(monthDayStyle)
    }

    /// 句子里的时刻：今天也写出“今天 20:04”，更远的只写“11-16”。
    static func prose(_ date: Date, now: Date) -> String {
        relativeDay(date, now: now).map { "\($0) \(date.formatted(clockStyle))" } ?? date.formatted(monthDayStyle)
    }

    /// 日志按天分组的标题：“今天”“昨天”“11-10”。
    static func day(_ date: Date, now: Date) -> String {
        relativeDay(date, now: now) ?? date.formatted(monthDayStyle)
    }

    /// 秒数的中文写法：“48 秒”“1 分 03 秒”“15 分”“1 小时 02 分”。
    static func seconds(_ total: Int) -> String {
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        if h > 0 { return m > 0 ? "\(h) 小时 \(String(format: "%02d", m)) 分" : "\(h) 小时" }
        if m > 0 { return s > 0 ? "\(m) 分 \(String(format: "%02d", s)) 秒" : "\(m) 分" }
        return "\(s) 秒"
    }

    /// 句子里的时长：整分钟写“15 分钟”，整小时写“1 小时”，其余同 duration。用在“15 分钟后被终止”。
    static func span(_ go: String) -> String {
        guard let total = goSeconds(go) else { return go }
        if total > 0, total % 3600 == 0 { return "\(total / 3600) 小时" }
        if total > 0, total < 3600, total % 60 == 0 { return "\(total / 60) 分钟" }
        return seconds(total)
    }

    /// 把两段文字接起来：拉丁字母或数字与汉字相邻时中间留一个空格（“Homebrew 更新失败”），
    /// 两边都是汉字时直接相连（“npm 全局包更新失败”）。
    static func adjoin(_ head: String, _ tail: String) -> String {
        guard let a = head.unicodeScalars.last, let b = tail.unicodeScalars.first else { return head + tail }
        let isHan = { (c: Unicode.Scalar) in c.properties.isIdeographic }
        let isWord = { (c: Unicode.Scalar) in c.isASCII && (c.properties.isAlphabetic || ("0"..."9").contains(c)) }
        return (isHan(a) && isWord(b)) || (isWord(a) && isHan(b)) ? "\(head) \(tail)" : head + tail
    }

    /// 正在更新的已用时间。
    static func elapsed(from start: Date, to now: Date) -> String {
        seconds(max(0, Int(now.timeIntervalSince(start))))
    }

    /// 引擎的 Go 时长（“2m31s”“15m0s”“1h2m3s”）转成中文写法；认不出时原样返回。
    static func duration(_ go: String) -> String {
        goSeconds(go).map(seconds) ?? go
    }

    /// 引擎的 Go 时长换成整秒；认不出时为 nil。
    private static func goSeconds(_ go: String) -> Int? {
        let units: [(String, Double)] = [("h", 3600), ("ms", 0.001), ("m", 60), ("s", 1)]
        var total = 0.0
        var rest = Substring(go)
        while !rest.isEmpty {
            let number = rest.prefix { $0.isNumber || $0 == "." }
            guard let value = Double(number) else { return nil }
            rest = rest.dropFirst(number.count)
            guard let unit = units.first(where: { rest.hasPrefix($0.0) }) else { return nil }
            total += value * unit.1
            rest = rest.dropFirst(unit.0.count)
        }
        return go.isEmpty ? nil : Int(total.rounded())
    }
}

// Cadence：配方里的周期（“8h”“1d”“1w”）。引擎写回时总是化成最简短的单一单位。
struct Cadence: Equatable {
    var count: Int
    var unit: Unit

    enum Unit: String, CaseIterable {
        case minute = "m", hour = "h", day = "d", week = "w"

        var label: String {
            switch self {
            case .minute: "分钟"
            case .hour: "小时"
            case .day: "天"
            case .week: "周"
            }
        }

        var seconds: TimeInterval {
            switch self {
            case .minute: 60
            case .hour: 3600
            case .day: 86400
            case .week: 604_800
            }
        }
    }

    /// 管理来源里周期下拉的常用档位。
    static let choices: [Cadence] = [
        Cadence(count: 1, unit: .hour), Cadence(count: 2, unit: .hour), Cadence(count: 4, unit: .hour),
        Cadence(count: 6, unit: .hour), Cadence(count: 8, unit: .hour), Cadence(count: 12, unit: .hour),
        Cadence(count: 1, unit: .day), Cadence(count: 2, unit: .day), Cadence(count: 3, unit: .day),
        Cadence(count: 1, unit: .week), Cadence(count: 2, unit: .week),
    ]

    init(count: Int, unit: Unit) {
        self.count = count
        self.unit = unit
    }

    /// 只认“正整数 + 单一单位”；“1h30m”这类组合周期返回 nil，界面只读显示原文。
    init?(_ text: String) {
        let digits = text.prefix { $0.isNumber }
        guard let n = Int(digits), n > 0, let u = Unit(rawValue: String(text.dropFirst(digits.count))) else { return nil }
        self.init(count: n, unit: u)
    }

    var text: String { "\(count)\(unit.rawValue)" }

    var interval: TimeInterval { Double(count) * unit.seconds }

    /// “每天”“每周”“每 7 天”“每 6 小时”。下拉、预设和句子里都用这一种写法。
    var sentence: String { count == 1 ? "每\(unit.label)" : "每 \(count) \(unit.label)" }
}
