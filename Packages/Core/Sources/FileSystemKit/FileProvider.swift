import Foundation

public struct ProviderPath: Hashable, Sendable {
    public let providerID: String
    public let components: [String]

    public init(providerID: String, components: [String]) {
        self.providerID = providerID
        self.components = components
    }

    public var displayString: String {
        "/" + components.joined(separator: "/")
    }

    public func appending(_ component: String) -> ProviderPath {
        ProviderPath(providerID: providerID, components: components + [component])
    }

    public func parent() -> ProviderPath? {
        guard !components.isEmpty else { return nil }
        return ProviderPath(providerID: providerID, components: Array(components.dropLast()))
    }
}

public enum FileSystemEvent: Sendable {
    case changed(ProviderPath)
    case removed(ProviderPath)
    case renamed(ProviderPath, ProviderPath)
}

public protocol FileProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var supportsObservation: Bool { get }

    func list(_ path: ProviderPath, includeHidden: Bool) async throws -> [FileItem]
    func move(_ src: ProviderPath, to dst: ProviderPath) async throws
    func copy(_ src: ProviderPath, to dst: ProviderPath, progress: ((Double) -> Void)?) async throws
    func delete(_ path: ProviderPath, toTrash: Bool) async throws
    func mkdir(_ path: ProviderPath) async throws
    func rename(_ path: ProviderPath, to newName: String) async throws
    func observe(_ path: ProviderPath) -> AsyncStream<FileSystemEvent>
}

public extension FileProvider {
    var supportsObservation: Bool { false }
    func observe(_ path: ProviderPath) -> AsyncStream<FileSystemEvent> {
        AsyncStream { $0.finish() }
    }
}
