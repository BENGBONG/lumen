import Foundation
import FileSystemKit

public enum ConflictResolution: Sendable, Equatable {
    case overwrite
    case skip
    case rename(newName: String)
    case merge
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
