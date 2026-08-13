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
}

public struct TransferTask: Identifiable, Sendable {
    public let id: UUID
    public let kind: TransferKind
    public let source: ProviderPath
    public let destination: ProviderPath
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
        self.kind = kind
        self.source = source
        self.destination = destination
        self.status = .pending
        self.bytesTotal = bytesTotal
        self.bytesTransferred = 0
    }
}
