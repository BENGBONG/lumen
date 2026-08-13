import Foundation
import FileSystemKit

@MainActor
public final class TransferQueue: ObservableObject {
    @Published public private(set) var tasks: [TransferTask] = []

    private let provider: any FileProvider
    private let resolver: any ConflictResolver
    private var processing = false

    public init(provider: any FileProvider, resolver: any ConflictResolver = AutoRenameResolver()) {
        self.provider = provider
        self.resolver = resolver
    }

    public func enqueue(_ task: TransferTask) {
        tasks.append(task)
        Task { await drain() }
    }

    public func cancel(_ id: TransferTask.ID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        if case .pending = tasks[i].status {
            tasks[i].status = .cancelled
        }
    }

    public func clearCompleted() {
        tasks.removeAll { task in
            switch task.status {
            case .completed, .cancelled, .skipped: return true
            default: return false
            }
        }
    }

    private func drain() async {
        guard !processing else { return }
        processing = true
        defer { processing = false }

        while let idx = nextPendingIndex() {
            var task = tasks[idx]
            tasks[idx].status = .running(progress: 0)
            do {
                // 冲突检测：目标已存在时先问 resolver 再执行
                switch try await resolveConflictIfNeeded(task) {
                case .skip:
                    update(task.id) { $0.status = .skipped }
                    continue
                case .cancel:
                    update(task.id) { $0.status = .cancelled }
                    continue
                case .proceed(let newDestination):
                    if newDestination != task.destination {
                        task.destination = newDestination
                        update(task.id) { $0.destination = newDestination }
                    }
                }

                switch task.kind {
                case .copy:
                    try await provider.copy(task.source, to: task.destination) { [weak self] p in
                        Task { @MainActor [weak self] in
                            self?.update(task.id) { $0.status = .running(progress: p) }
                        }
                    }
                case .move:
                    try await provider.move(task.source, to: task.destination)
                }
                update(task.id) { $0.status = .completed }
            } catch {
                update(task.id) { $0.status = .failed(error.localizedDescription) }
            }
        }
    }

    private enum ConflictAction {
        case proceed(ProviderPath)
        case skip
        case cancel
    }

    /// 目标已存在时调用 resolver 决定如何处理；无冲突返回 .proceed(原目标)。
    private func resolveConflictIfNeeded(_ task: TransferTask) async throws -> ConflictAction {
        guard let existing = await provider.item(at: task.destination) else {
            return .proceed(task.destination)
        }
        // 源 stat 失败时跳过冲突处理，让 copy/move 按原路径报错
        guard let source = await provider.item(at: task.source) else {
            return .proceed(task.destination)
        }

        switch await resolver.resolve(source: source, destination: existing) {
        case .overwrite:
            try await provider.delete(task.destination, toTrash: false)
            return .proceed(task.destination)
        case .skip:
            return .skip
        case .cancel:
            return .cancel
        case .rename(let baseName):
            let unique = try await uniqueDestination(named: baseName, in: task.destination.parent())
            return .proceed(unique ?? task.destination)
        case .merge:
            throw TransferError.mergeUnsupported
        }
    }

    /// 在父目录内基于期望名字找不冲突的目标：被占用时按 "name 2"、"name 3" 递增。
    private func uniqueDestination(named name: String, in parent: ProviderPath?) async throws -> ProviderPath? {
        guard let parent else { return nil }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var candidate = parent.appending(name)
        var n = 2
        while await provider.item(at: candidate) != nil {
            let numbered = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            candidate = parent.appending(numbered)
            n += 1
        }
        return candidate
    }

    private func update(_ id: TransferTask.ID, _ mutate: (inout TransferTask) -> Void) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tasks[i])
    }

    private func nextPendingIndex() -> Int? {
        tasks.firstIndex {
            if case .pending = $0.status { return true } else { return false }
        }
    }
}
