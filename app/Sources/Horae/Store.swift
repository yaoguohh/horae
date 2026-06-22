import Combine
import Foundation

// DirectoryWatcher：监听 state 目录变更，引擎写 current/last-run 后即时回调。
final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject
    private let fd: Int32

    init?(url: URL, onChange: @escaping @Sendable () -> Void) {
        fd = open(url.path, O_EVTONLY)
        if fd < 0 { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main
        )
        source.setEventHandler(handler: onChange)
        let captured = fd
        source.setCancelHandler { close(captured) }
        source.resume()
    }

    deinit { source.cancel() }
}

// Store：菜单栏 app 的全部可观察状态。
@MainActor
final class Store: ObservableObject {
    @Published var status: StatusView?
    @Published var current: Current?
    @Published var lastRun: LastRun?
    // queued：用户点了刷新但尚未跑完的源(从点击到该步执行结束)。引擎单实例锁串行执行,
    // 这里只为 UI 展示"排队中" + 去重(避免重复 spawn)。正在跑的源由 current 判定显示"正在更新"。
    @Published private(set) var queued: Set<String> = []

    private var watcher: DirectoryWatcher?
    private var timer: Timer?
    private var lastNotifiedFinishedAt: Date?
    // 上一次观察到的"正在运行步"id：用于在该步不再是当前运行步时把它移出 queued。
    private var lastRunningStep: String?
    private let notifier = Notifier()

    init() {
        notifier.setup()
        // 确保目录存在，watcher 才能 attach；同时为契约文件就位。
        try? FileManager.default.createDirectory(at: Engine.stateDir, withIntermediateDirectories: true)
        // 基线：启动时记下当前 last-run，避免对历史结果重发通知。
        if let lr: LastRun = Engine.read(Engine.lastRunURL) {
            lastNotifiedFinishedAt = lr.finishedAt
            lastRun = lr
        }
        current = Engine.read(Engine.currentURL)
        refreshStatus()
        startWatching()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func startWatching() {
        // [weak self] 打破 Store→watcher→DispatchSource→闭包→Store 保留环，
        // 与下方 timer 的弱引用约定一致，确保 Store 释放时 watcher 能正常 cancel/close(fd)。
        watcher = DirectoryWatcher(url: Engine.stateDir) { [weak self] in
            Task { @MainActor in self?.onDirChange() }
        }
    }

    private func onDirChange() {
        current = Engine.read(Engine.currentURL)
        reconcileQueue()
        if let lr: LastRun = Engine.read(Engine.lastRunURL) {
            handleLastRun(lr)
            lastRun = lr
        }
        refreshStatus()
    }

    func tick() {
        current = Engine.read(Engine.currentURL)
        reconcileQueue()
        if let lr: LastRun = Engine.read(Engine.lastRunURL) {
            handleLastRun(lr)
            lastRun = lr
        }
        refreshStatus()
    }

    // reconcileQueue：当某步不再是"当前运行步"(切到下一步或整轮结束)即视为已跑完, 移出 queued。
    // 只认 current 的运行步迁移, 不依赖时间戳, 故旧 last-run 不会误清, 仍在等待的源也保留。
    private func reconcileQueue() {
        let nowStep = current?.running == true ? current?.step : nil
        if let prev = lastRunningStep, prev != nowStep {
            queued.remove(prev)
        }
        lastRunningStep = nowStep
    }

    func refreshStatus() {
        Task.detached(priority: .utility) {
            let s = Engine.runStatus()
            await MainActor.run { self.status = s }
        }
    }

    private func handleLastRun(_ lr: LastRun) {
        guard lr.shouldNotify, lr.finishedAt != lastNotifiedFinishedAt else { return }
        lastNotifiedFinishedAt = lr.finishedAt
        notifier.post(lr)
    }

    // MARK: 用户动作

    func runAll() {
        // --wait: 若有 cadence/手动 run 在跑, 排队等待而非静默丢弃。
        Engine.triggerRun(only: nil, wait: true)
        bumpSoon()
    }

    func run(_ id: String) {
        // 已排队或正在跑该源 → 忽略重复点击, 不重复 spawn(引擎串行执行, 重复 spawn 只会多一个空跑)。
        if queued.contains(id) || (current?.running == true && current?.step == id) { return }
        queued.insert(id)
        // --wait: 撞单实例锁则排队等上一轮结束再跑, 配合 queued 的"排队中"展示。
        Engine.triggerRun(only: id, wait: true)
        bumpSoon()
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        var ov = Engine.loadOverrides()
        if enabled {
            ov.removeValue(forKey: id) // 恢复 = 移除覆盖，回到 recipe 默认
        } else {
            ov[id] = Override(enabled: false)
            // 禁用会让其待执行的 --wait run 被跳过(永不成为 current), 主动清掉排队态以免残留。
            queued.remove(id)
        }
        Engine.writeOverrides(ov)
        refreshStatus()
    }

    func pause(until: Date?) {
        Engine.writePause(Pause(paused: true, until: until))
        tick()
    }

    func resume() {
        Engine.writePause(Pause(paused: false, until: nil))
        tick()
    }

    // 触发后稍候再刷新，吃到 current/last-run 的首个变更。
    private func bumpSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.tick()
        }
    }
}
