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

    private var watcher: DirectoryWatcher?
    private var timer: Timer?
    private var lastNotifiedFinishedAt: Date?
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
        watcher = DirectoryWatcher(url: Engine.stateDir) {
            Task { @MainActor in self.onDirChange() }
        }
    }

    private func onDirChange() {
        current = Engine.read(Engine.currentURL)
        if let lr: LastRun = Engine.read(Engine.lastRunURL) {
            handleLastRun(lr)
            lastRun = lr
        }
        refreshStatus()
    }

    func tick() {
        current = Engine.read(Engine.currentURL)
        if let lr: LastRun = Engine.read(Engine.lastRunURL) {
            handleLastRun(lr)
            lastRun = lr
        }
        refreshStatus()
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
        Engine.triggerRun(only: nil)
        bumpSoon()
    }

    func run(_ id: String) {
        Engine.triggerRun(only: id)
        bumpSoon()
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        var ov = Engine.loadOverrides()
        if enabled {
            ov.removeValue(forKey: id) // 恢复 = 移除覆盖，回到 recipe 默认
        } else {
            ov[id] = Override(enabled: false)
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
