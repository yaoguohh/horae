import Foundation

// 与 Go 引擎 internal/report + internal/control 的 JSON 契约一一对应。
// 键为 snake_case，解码用 .convertFromSnakeCase(见 Engine)。

struct StatusView: Codable {
    var generatedAt: Date
    var paused: Bool
    var pausedUntil: Date?
    var sources: [Source]
}

struct Source: Codable, Identifiable {
    var id: String
    var label: String
    var enabled: Bool
    var status: String
    var lastSuccessAt: Date?
    var lastDuration: String?
    var lastExitCode: Int
    var nextDueAt: Date?
    var due: Bool
}

struct Current: Codable {
    var running: Bool
    var step: String?
    var label: String?
    var index: Int?
    var total: Int?
    var startedAt: Date?
}

struct LastRun: Codable {
    var finishedAt: Date
    var notifyPolicy: String
    var shouldNotify: Bool
    var summary: RunSummary
    var steps: [StepReport]
}

struct RunSummary: Codable {
    var ran: Int
    var ok: Int
    var failed: Int
    var timeout: Int
    var skipped: Int
}

struct StepReport: Codable, Identifiable {
    var id: String
    var label: String
    var status: String
    var exitCode: Int
    var duration: String
    var changes: [Change]
    var outputTail: String?
}

struct Change: Codable {
    var name: String
    var from: String?
    var to: String?
}

// app 写、引擎读。
struct Pause: Codable {
    var paused: Bool
    var until: Date?
}

struct Override: Codable {
    var enabled: Bool?
}
