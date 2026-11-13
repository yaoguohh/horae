import Foundation

/// 来源的主状态。优先级：已停用 > 正在更新 > 排队中 > 未成功（失败或超时）> 尚未运行 > 成功。
enum SourceKind {
    case disabled, running, queued, unsuccessful, never, success
}

/// 弹窗整体状态，决定菜单栏图标的形状。优先级：正在更新 > 需要处理 > 已暂停 > 空闲。
enum OverallState {
    case idle, running, attention, paused
}

/// 来源“下次最早”可能自动运行的时刻。
enum Earliest: Equatable {
    case disabled
    /// 已到期，等下一次每小时检查。
    case due
    /// 暂停到手动恢复。
    case pausedIndefinitely
    /// shifted：到期时刻落在暂停期内，顺延到暂停结束。
    case at(Date, shifted: Bool)
    case unknown
}

/// 一轮真正执行过来源的运行。
struct RunRound {
    var finishedAt: Date
    var ok: Int
    var unsuccessful: Int
}

/// 一个来源最近那次未成功运行的时刻与输出。
struct FailedRun {
    var at: Date?
    var output: String
}

struct Verdict {
    var title: String
    var subtitle: String
}

/// 弹窗在某一时刻需要的全部事实。状态判定、优先级和措辞规则都在这里（规格第 5 节），视图只读它。
struct Board {
    let now: Date
    let sources: [Source]
    let current: Current?
    let queued: Set<String>
    let paused: Bool
    let pausedUntil: Date?
    let lastRun: LastRun?
    let steps: [String: ConfigStep]
    /// 运行日志，新的在前。
    let log: [LogEntry]

    /// 同一轮的日志在这一轮结束时一次写出，时间戳相差不到这个间隔。
    static let roundWindow: TimeInterval = 2

    var running: Current? { current?.running == true ? current : nil }

    func source(_ id: String) -> Source? { sources.first { $0.id == id } }

    func label(for id: String) -> String {
        source(id)?.label ?? steps[id]?.label ?? id
    }

    func kind(of s: Source) -> SourceKind {
        if !s.enabled { return .disabled }
        if running?.step == s.id { return .running }
        if queued.contains(s.id) { return .queued }
        if s.isUnsuccessful { return .unsuccessful }
        if s.status == "never" { return .never }
        return .success
    }

    /// 启用中且最近结果未成功的来源，按配方顺序。
    var unsuccessful: [Source] { sources.filter { $0.enabled && $0.isUnsuccessful } }

    var overall: OverallState {
        if running != nil { return .running }
        if !unsuccessful.isEmpty { return .attention }
        if paused { return .paused }
        return .idle
    }

    // MARK: 来源表的两列

    /// 未到期是到期时刻；已到期是“已到期”；未成功时到期时刻就是自动重试的最早时刻；
    /// 暂停期间取到期时刻与暂停结束中较晚的一个，无限期暂停是“已暂停”；已停用是“已停用”。
    func earliest(of s: Source) -> Earliest {
        if !s.enabled { return .disabled }
        let next = s.nextDueAt
        let isDue = s.due || next.map { $0 <= now } ?? false
        if paused {
            guard let until = pausedUntil else { return .pausedIndefinitely }
            if isDue { return .at(until, shifted: true) }
            if let next { return until > next ? .at(until, shifted: true) : .at(next, shifted: false) }
            return .unknown
        }
        if isDue { return .due }
        if let next { return .at(next, shifted: false) }
        return .unknown
    }

    /// “下次最早”一列。
    func nextText(of s: Source) -> String {
        switch earliest(of: s) {
        case .disabled: "已停用"
        case .due: "已到期"
        case .pausedIndefinitely: "已暂停"
        case let .at(date, _): Format.column(date, now: now)
        case .unknown: "—"
        }
    }

    /// 最近一次尝试的时刻：成功是上次成功；未成功是那次运行的时刻，日志里找不到时用下次到期减去周期反推
    /// （失败按周期退避，下次到期 = 上次尝试 + 周期）。
    func lastAttempt(of s: Source) -> Date? {
        guard s.isUnsuccessful else { return s.lastSuccessAt }
        if let at = failedRun(of: s).at { return at }
        guard let next = s.nextDueAt, let cadence = steps[s.id].flatMap({ Cadence($0.cadence) }) else { return nil }
        return next.addingTimeInterval(-cadence.interval)
    }

    /// “上次”一列。
    func lastText(of s: Source) -> String {
        if let at = lastAttempt(of: s) { return Format.column(at, now: now) }
        return s.status == "never" ? "尚未运行" : "—"
    }

    // MARK: 未成功

    /// 失败写退出码，超时写运行了多久后被终止。
    func reason(for s: Source) -> String {
        s.status == "timeout" ? "\(Format.span(s.lastDuration ?? ""))后被终止" : "退出码 \(s.lastExitCode)"
    }

    /// 最近那次未成功运行：last-run.json 里有这一步就取它，否则取运行日志里最新的一条未成功记录。
    func failedRun(of s: Source) -> FailedRun {
        if let lr = lastRun, let step = lr.steps.first(where: { $0.id == s.id && $0.isUnsuccessful }) {
            return FailedRun(at: lr.finishedAt, output: step.outputTail ?? "")
        }
        if let entry = failedEntry(of: s.id) {
            return FailedRun(at: entry.time, output: entry.detail)
        }
        return FailedRun(at: nil, output: "")
    }

    /// 未成功的行下面那一行：原因、时刻、自动重试的最早时刻。失败按周期退避，所以重试时刻必须写出来。
    func failureLine(of s: Source) -> String {
        var parts = [reason(for: s)]
        if let at = failedRun(of: s).at { parts.append(Format.prose(at, now: now)) }
        switch earliest(of: s) {
        case .due: parts.append("下次检查时自动重试")
        case .pausedIndefinitely: parts.append("恢复自动更新后重试")
        case let .at(date, _): parts.append("最早 \(Format.column(date, now: now)) 自动重试")
        case .disabled, .unknown: break
        }
        return parts.joined(separator: " · ")
    }

    // MARK: 最近一轮

    /// 最近一轮真正执行过来源的运行。last-run.json 在每小时检查时也会写，检查时没有到期来源就是 0 项，
    /// 这时从运行日志取最近一轮。
    var lastRound: RunRound? {
        if let lr = lastRun, lr.summary.ran > 0 {
            return RunRound(finishedAt: lr.finishedAt, ok: lr.summary.ok, unsuccessful: lr.summary.failed + lr.summary.timeout)
        }
        guard let newest = log.first else { return nil }
        let round = log.prefix { newest.time.timeIntervalSince($0.time) < Self.roundWindow }
        let bad = round.filter(\.isUnsuccessful).count
        return RunRound(finishedAt: newest.time, ok: round.count - bad, unsuccessful: bad)
    }

    // MARK: 总述

    /// 头部一句总述：正在更新 > 有未成功 > 已暂停 > 全部正常。
    func verdict(at time: Date) -> Verdict {
        let bad = unsuccessful
        if let cur = running {
            var parts: [String] = []
            if let i = cur.index, let n = cur.total { parts.append("第 \(i)/\(n) 项") }
            if let start = cur.startedAt { parts.append("已用 \(Format.elapsed(from: start, to: time))") }
            if !bad.isEmpty { parts.append("\(bad.count) 项未成功") }
            let name = cur.label ?? label(for: cur.step ?? "")
            return Verdict(title: Format.adjoin("正在更新", name), subtitle: parts.joined(separator: "，"))
        }
        if bad.count == 1, let s = bad.first {
            let at = failedRun(of: s).at.map { "，" + Format.prose($0, now: now) } ?? ""
            return Verdict(title: Format.adjoin(s.label, "更新\(s.outcomeWord)"), subtitle: reason(for: s) + at)
        }
        if bad.count > 1 {
            return Verdict(title: "\(bad.count) 项需要处理", subtitle: bad.map { Format.adjoin($0.label, $0.outcomeWord) }.joined(separator: "、"))
        }
        if paused {
            let resume = pausedUntil.map { "\(Format.prose($0, now: now)) 恢复" } ?? "不会自动恢复"
            return Verdict(title: "自动更新已暂停", subtitle: "\(resume)，手动更新不受影响")
        }
        if sources.isEmpty {
            return Verdict(title: "还没有来源", subtitle: "在设置的“管理来源”里添加")
        }
        guard let round = lastRound else {
            return Verdict(title: "全部正常", subtitle: "还没有运行记录")
        }
        let summary = "\(round.ok) 项成功" + (round.unsuccessful > 0 ? "、\(round.unsuccessful) 项未成功" : "")
        return Verdict(title: "全部正常", subtitle: "最近一次运行 \(Format.column(round.finishedAt, now: now))，\(summary)")
    }

    /// 底栏左侧在暂停时写明暂停到何时。
    var pauseNote: String {
        pausedUntil.map { "已暂停至\(Format.prose($0, now: now))" } ?? "已暂停"
    }

    // MARK: 日志

    /// 这个来源最近一条未成功的记录。
    func failedEntry(of id: String) -> LogEntry? { log.first { $0.source == id && $0.isUnsuccessful } }

    /// 这个来源最近一条记录。
    func latestEntry(of id: String) -> LogEntry? { log.first { $0.source == id } }
}

extension Source {
    var isUnsuccessful: Bool { status == "failure" || status == "timeout" }
    /// “失败”或“超时”。
    var outcomeWord: String { status == "timeout" ? "超时" : "失败" }
}

extension StepReport {
    var isUnsuccessful: Bool { status == "failure" || status == "timeout" }
}

extension LogEntry {
    var isUnsuccessful: Bool { status == "failure" || status == "timeout" }
    var outcomeWord: String { status == "timeout" ? "超时" : "失败" }

    /// 展开的输出上方那一句：失败写退出码，超时写运行了多久后被终止。
    var reasonText: String {
        status == "timeout" ? "\(Format.span(duration))后被终止" : "退出码 \(exitCode)"
    }
}
