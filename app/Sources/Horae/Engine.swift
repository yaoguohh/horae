import Foundation

// LogEntry 是一条运行日志记录(供前台日志查看器)。
struct LogEntry: Identifiable {
    let id = UUID()
    var time: Date
    var source: String
    var status: String
    var duration: String
    var reason: String
    var detail: String // 失败/超时的子进程输出尾部，点击展开
}

// ConfigStep 对应 `horae config list/add` 的 step JSON。
struct ConfigStep: Codable, Identifiable {
    var id: String
    var label: String?
    var cadence: String
    var command: [String]?
    var shell: String?
    var timeout: String?
    var env: [String: String]?
    var enabled: Bool?
}

// Preset 是 app 内置的预设源(由 Mac 扫描产出)，供"添加源"勾选。
struct Preset: Codable, Identifiable {
    var id: String
    var label: String
    var manager: String
    var installed: Bool
    var detail: String
    var shell: String
    var cadence: String
    var note: String
}

// Engine 是与 Go 引擎(horae CLI + state 目录契约文件)的全部接口。
// 读契约文件 / 跑 status --json / shell out 手动触发 / 写 pause+overrides。
enum Engine {
    // MARK: 路径(与引擎 paths 包一致)

    static var stateDir: URL {
        let base = ProcessInfo.processInfo.environment["XDG_STATE_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/state")
        return base.appending(path: "horae")
    }

    static var currentURL: URL { stateDir.appending(path: "current.json") }
    static var lastRunURL: URL { stateDir.appending(path: "last-run.json") }
    static var pauseURL: URL { stateDir.appending(path: "pause.json") }
    static var overridesURL: URL { stateDir.appending(path: "overrides.json") }

    static var logDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/horae")
    }

    // MARK: JSON 编解码(snake_case + 宽松 ISO 日期)

    // ISO8601DateFormatter 非 Sendable 且非线程安全，按调用就地创建，避免静态共享态。
    private static func parseISO(_ s: String) -> Date {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s) ?? .distantPast
    }

    private static func formatISO(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        // 宽松解析：解析不出(如清空后的零值时间)回落到 distantPast，避免整个对象解码失败。
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            return parseISO(s)
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(formatISO(date))
        }
        e.outputFormatting = [.prettyPrinted]
        return e
    }()

    static func read<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    // MARK: CLI

    // makeProcess 优先用 ~/.local/bin/horae；否则经 /usr/bin/env 走 PATH。
    private static func makeProcess(_ args: [String]) -> Process {
        let p = Process()
        let local = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/horae")
        if FileManager.default.isExecutableFile(atPath: local.path) {
            p.executableURL = local
            p.arguments = args
        } else {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["horae"] + args
        }
        return p
    }

    // runStatus 同步跑 horae status --json(请在后台线程调用)。
    static func runStatus() -> StatusView? {
        let p = makeProcess(["status", "--json"])
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return try? decoder.decode(StatusView.self, from: data)
    }

    // triggerRun 异步触发一次更新(only 为某源 id 时只跑该源)。
    // wait=true 时带 --wait: 撞单实例锁则排队等待上一轮结束再跑, 而非静默丢弃(手动触发用)。
    static func triggerRun(only: String?, wait: Bool = false) {
        var args = ["run", "--force"]
        if let only { args = ["run", "--only", only, "--force"] }
        if wait { args.append("--wait") }
        let p = makeProcess(args)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    // MARK: 写控制文件(原子)

    static func writePause(_ pause: Pause) {
        writeJSON(pause, to: pauseURL)
    }

    static func writeOverrides(_ overrides: [String: Override]) {
        writeJSON(overrides, to: overridesURL)
    }

    static func loadOverrides() -> [String: Override] {
        read(overridesURL) ?? [:]
    }

    static func loadPause() -> Pause {
        read(pauseURL) ?? Pause(paused: false, until: nil)
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        let tmp = url.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: 运行日志(供前台日志查看器)

    static func recentLogEntries(limit: Int = 250) -> [LogEntry] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: logDir.path) else { return [] }
        let logFiles = files.filter { $0.hasPrefix("run-") && $0.hasSuffix(".log") }.sorted(by: >)
        var entries: [LogEntry] = []
        for name in logFiles.prefix(4) {
            guard let text = try? String(contentsOf: logDir.appending(path: name), encoding: .utf8) else { continue }
            for raw in text.split(separator: "\n") {
                let kv = parseSlogLine(String(raw))
                // 只看真正执行过的(成功/失败/超时)，滤掉每小时 not-due 的"跳过"噪声。
                guard kv["msg"] == "step", kv["status"] != "skipped" else { continue }
                entries.append(LogEntry(
                    time: parseISO(kv["time"] ?? ""),
                    source: kv["id"] ?? "?",
                    status: kv["status"] ?? "",
                    duration: kv["duration"] ?? "",
                    reason: kv["reason"] ?? "",
                    detail: kv["stderr_tail"] ?? ""
                ))
            }
            if entries.count >= limit { break }
        }
        return Array(entries.sorted { $0.time > $1.time }.prefix(limit))
    }

    // parseSlogLine 解析 slog text handler 的 key=value 行(值可带引号转义)。
    private static func parseSlogLine(_ line: String) -> [String: String] {
        var dict: [String: String] = [:]
        let chars = Array(line)
        let n = chars.count
        var i = 0
        while i < n {
            while i < n, chars[i] == " " { i += 1 }
            var key = ""
            while i < n, chars[i] != "=", chars[i] != " " { key.append(chars[i]); i += 1 }
            guard i < n, chars[i] == "=" else { break }
            i += 1
            var val = ""
            if i < n, chars[i] == "\"" {
                i += 1
                while i < n, chars[i] != "\"" {
                    if chars[i] == "\\", i + 1 < n { i += 1 }
                    val.append(chars[i]); i += 1
                }
                if i < n { i += 1 }
            } else {
                while i < n, chars[i] != " " { val.append(chars[i]); i += 1 }
            }
            if !key.isEmpty { dict[key] = val }
        }
        return dict
    }

    // MARK: 源管理(config 命令读写 recipe.toml；方案甲)

    static func configList() -> [ConfigStep] {
        let p = makeProcess(["config", "list"])
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (try? decoder.decode([ConfigStep].self, from: data)) ?? []
    }

    static func configAdd(_ step: ConfigStep) {
        guard let data = try? encoder.encode(step) else { return }
        let p = makeProcess(["config", "add"])
        let inPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        // 用可抛 Swift error 的现代 API：子进程提前退出时 EPIPE 是可捕获的 error，
        // 而非弃用 write(_:)/closeFile() 抛出的、try? 接不住的 ObjC NSException(会崩溃整个 app)。
        let handle = inPipe.fileHandleForWriting
        do {
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // 子进程在读完 stdin 前已退出，放弃写入即可。
        }
        p.waitUntilExit()
    }

    static func configRemove(_ id: String) {
        let p = makeProcess(["config", "remove", id])
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        p.waitUntilExit()
    }

    static func loadPresets() -> [Preset] {
        guard let url = Bundle.main.url(forResource: "presets", withExtension: "json")
            ?? Bundle.main.url(forResource: "presets", withExtension: "json", subdirectory: "Resources"),
            let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Preset].self, from: data)) ?? []
    }

    static var recipeURL: URL {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config")
        return base.appending(path: "horae/recipes.toml")
    }
}
