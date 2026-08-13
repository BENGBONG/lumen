import Foundation
import FileSystemKit

public enum ConflictResolution: Sendable, Equatable {
    case overwrite
    case skip
    case rename(newName: String)
    case merge
    /// 中止当前任务（用户主动停止）。
    case cancel
}

public enum TransferError: Error, Sendable {
    /// 目录合并未实现——resolver 返回 .merge 时任务以该错误失败，避免静默丢数据。
    case mergeUnsupported
}

public protocol ConflictResolver: Sendable {
    func resolve(source: FileItem, destination: FileItem) async -> ConflictResolution
}

public struct AlwaysSkipResolver: ConflictResolver {
    public init() {}
    public func resolve(source: FileItem, destination: FileItem) async -> ConflictResolution { .skip }
}

public struct AlwaysOverwriteResolver: ConflictResolver {
    public init() {}
    public func resolve(source: FileItem, destination: FileItem) async -> ConflictResolution { .overwrite }
}

public struct AutoRenameResolver: ConflictResolver {
    public init() {}

    public func resolve(source: FileItem, destination: FileItem) async -> ConflictResolution {
        let name = source.name
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        let newStem = "\(stem) (副本)"
        let newName = ext.isEmpty ? newStem : "\(newStem).\(ext)"
        return .rename(newName: newName)
    }
}
