import SwiftUI

struct SourceManageView: View {
    let onClose: () -> Void
    @State private var sources: [ConfigStep] = []
    @State private var presets: [Preset] = []
    @State private var loading = true

    private let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    private var currentIDs: Set<String> { Set(sources.map { $0.id }) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            if loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 36)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        currentSection
                        addSection
                        advancedSection
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                }
                .frame(height: 364)
            }
        }
        .frame(width: 336)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "chevron.left").font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 24, height: 24).background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text("更新源").font(.system(size: 14, weight: .bold))
                Text("\(sources.count) 个 · 勾选添加 / 删除").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
    }

    // MARK: 当前源

    private var currentSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle("当前源")
            if sources.isEmpty {
                Text("还没有更新源，从下面预设里添加。").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            ForEach(sources) { currentRow($0) }
        }
    }

    private func currentRow(_ s: ConfigStep) -> some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(s.label ?? s.id).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(s.cadence).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 0.5)
                        .background(Color.primary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(s.shell ?? (s.command?.joined(separator: " ") ?? ""))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { remove(s.id) } label: {
                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(Color(red: 1, green: 0.42, blue: 0.4))
                    .frame(width: 24, height: 24).background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain).help("删除此源")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 9))
    }

    // MARK: 添加预设

    private var addSection: some View {
        let addable = presets.filter { !currentIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 5) {
            sectionTitle("添加预设源（已装的在前）")
            if addable.isEmpty {
                Text("预设都加完了。").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            ForEach(addable) { presetRow($0) }
        }
    }

    private func presetRow(_ p: Preset) -> some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(p.label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if p.installed {
                        Text("已装").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(green)
                            .padding(.horizontal, 4).padding(.vertical, 0.5)
                            .background(green.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Text("未装").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                }
                Text(p.detail).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { add(p) } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.horaeAccent)
                    .frame(width: 24, height: 24).background(Color.horaeAccent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain).help("添加（\(p.cadence)）\(p.note)")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 9))
        .opacity(p.installed ? 1 : 0.72)
    }

    // MARK: 高级

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle("高级")
            Button { NSWorkspace.shared.open(Engine.recipeURL) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("直接编辑 recipes.toml").font(.system(size: 12, weight: .semibold))
                        Text("专业维护：手编频率 / 命令 / 环境变量").font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary).textCase(.uppercase)
    }

    // MARK: 动作

    private func load() {
        Task.detached(priority: .utility) {
            let ss = Engine.configList()
            let ps = Engine.loadPresets()
            await MainActor.run {
                sources = ss
                presets = ps
                loading = false
            }
        }
    }

    private func add(_ p: Preset) {
        Engine.configAdd(ConfigStep(id: p.id, label: p.label, cadence: p.cadence,
                                    command: nil, shell: p.shell, timeout: nil, env: nil, enabled: nil))
        reload()
    }

    private func remove(_ id: String) {
        Engine.configRemove(id)
        reload()
    }

    private func reload() {
        Task.detached(priority: .utility) {
            let ss = Engine.configList()
            await MainActor.run { sources = ss }
        }
    }
}
