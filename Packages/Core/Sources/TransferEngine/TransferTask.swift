import Foundation
import FileSystemKit

public enum TransferKind: Sendable {
    case copy
    case move
}

public enum TransferStatus: Sendable, Equatable {
    case pending
    case running(progress: Double)
    case completed
    case failed(String)
    case cancelled
    /// 冲突时用户/resolver 选择跳过，任务未执行。
    case skipped
}

public struct TransferTask: Identifiable, Sendable {
    public let id: UUID
    /// 同一次拖拽/粘贴入队的任务共享 batchID，撤回时按批次整体撤销。
    public var batchID: UUID
    public let kind: TransferKind
    public let source: ProviderPath
    /// 冲突重命名后目的地会变，所以是 var。
    public var destination: ProviderPath
    public var status: TransferStatus
    public var bytesTotal: Int64
    public var bytesTransferred: Int64

    public init(
        kind: TransferKind,
        source: ProviderPath,
        destination: ProviderPath,
        bytesTotal: Int64 = -1
    ) {
        self.id = UUID()
        self.batchID = UUID()
        self.kind = kind
        self.source = source
        self.destination = destination
        self.status = .pending
        self.bytesTotal = bytesTotal
        self.bytesTransferred = 0
    }
}
