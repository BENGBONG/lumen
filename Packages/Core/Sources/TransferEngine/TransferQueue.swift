import Foundation
import FileSystemKit

/// 单个可撤回操作（成功执行的传输任务的逆操作）。
public enum UndoOp: Sendable {
    /// 撤销复制：把产物送入废纸篓（可找回，非永久删除）
    case trashCreated(ProviderPath)
    /// 撤销移动：移回原位置
    case moveBack(from: ProviderPath, to: ProviderPath)
}

/// 一次撤回的单位 = 一次拖拽/粘贴批次（可能含多个文件）。
public struct UndoableBatch: Sendable {
    public let label: String
    public let ops: [UndoOp]
}

@MainActor
public final class TransferQueue: ObservableObject {
    @Published public private(set) var tasks: [TransferTask] = []
    @Published public private(set) var undoStack: [UndoableBatch] = []

    private let provider: any FileProvider
    private let resolver: any ConflictResolver
    private var processing = false
    /// batchID → 已成功的逆操作（批次全部终态后出栈为 UndoableBatch）
    private var pendingUndoOps: [UUID: [UndoOp]] = [:]
    private static let maxUndoDepth = 50

    public init(provider: any FileProvider, resolver: any ConflictResolver = AutoRenameResolver()) {
        self.provider = provider
        self.resolver = resolver
    }

    public func enqueue(_ task: TransferTask) {
        enqueue([task])
    }

    /// 批量入队：同批任务共享 batchID，撤回时作为一个整体。
    public func enqueue(_ newTasks: [TransferTask]) {
        guard !newTasks.isEmpty else { return }
        let batchID = UUID()
        let stamped = newTasks.map { task -> TransferTask in
            var t = task
            t.batchID = batchID
            return t
        }
        tasks.append(contentsOf: stamped)
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

    // MARK: - 撤回

    public var canUndo: Bool { !undoStack.isEmpty }
    public var undoLabel: String? { undoStack.last?.label }

    /// 撤回最近一批传输。返回（批次描述, 失败原因列表）；无可撤回时返回 nil。
    /// 个别逆操作失败（如原位置已有同名文件）会跳过并记入 failures，不中断整批。
    @discardableResult
    public func undoLast() async -> (label: String, failures: [String])? {
        guard let batch = undoStack.popLast() else { return nil }
        var failures: [String] = []
        for op in batch.ops.reversed() {
            do {
                switch op {
                case .trashCreated(let path):
                    try await provider.delete(path, toTrash: true)
                case .moveBack(let from, let to):
                    try await provider.move(from, to: to)
                }
            } catch {
                let name: String
                switch op {
                case .trashCreated(let path): name = path.components.last ?? ""
                case .moveBack(let from, _): name = from.components.last ?? ""
                }
                failures.append("\(name): \(error.localizedDescription)")
            }
        }
        return (batch.label, failures)
    }

    /// 任务成功后记录逆操作；批次全部终态时汇总进撤回栈。
    private func recordUndo(_ task: TransferTask) {
        let op: UndoOp
        switch task.kind {
        case .copy: op = .trashCreated(task.destination)
        case .move: op = .moveBack(from: task.destination, to: task.source)
        }
        pendingUndoOps[task.batchID, default: []].append(op)
        finalizeBatchIfNeeded(task.batchID)
    }

    private func finalizeBatchIfNeeded(_ batchID: UUID) {
        let batchTasks = tasks.filter { $0.batchID == batchID }
        guard !batchTasks.isEmpty else { return }
        let allTerminal = batchTasks.allSatisfy {
            switch $0.status {
            case .completed, .failed, .cancelled, .skipped: return true
            case .pending, .running: return false
            }
        }
        guard allTerminal, let ops = pendingUndoOps.removeValue(forKey: batchID),
              !ops.isEmpty else { return }

        let first = batchTasks[0]
        let verb = first.kind == .copy ? "复制" : "移动"
        let destDir = first.destination.parent()?.components.last ?? "/"
        let label = ops.count == 1
            ? "\(verb) \(first.destination.components.last ?? "")"
            : "\(verb) \(ops.count) 个项目到 \(destDir)"
        undoStack.append(UndoableBatch(label: label, ops: ops))
        if undoStack.count > Self.maxUndoDepth { undoStack.removeFirst() }
    }

    // MARK: - 执行

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
                // 用队列里的最新任务状态记录（destination 可能已被冲突重命名改写）
                if let done = tasks.first(where: { $0.id == task.id }) {
                    recordUndo(done)
                }
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
