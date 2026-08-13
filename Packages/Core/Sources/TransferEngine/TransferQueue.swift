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
            case .completed, .cancelled: return true
            default: return false
            }
        }
    }

    private func drain() async {
        guard !processing else { return }
        processing = true
        defer { processing = false }

        while let idx = nextPendingIndex() {
            tasks[idx].status = .running(progress: 0)
            let task = tasks[idx]
            do {
                switch task.kind {
                case .copy:
                    try await provider.copy(task.source, to: task.destination) { [weak self] p in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  let i = self.tasks.firstIndex(where: { $0.id == task.id })
                            else { return }
                            self.tasks[i].status = .running(progress: p)
                        }
                    }
                case .move:
                    try await provider.move(task.source, to: task.destination)
                }
                if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[i].status = .completed
                }
            } catch {
                if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[i].status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func nextPendingIndex() -> Int? {
        tasks.firstIndex {
            if case .pending = $0.status { return true } else { return false }
        }
    }
}
