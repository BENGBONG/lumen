import Foundation
import AppKit

public final class LocalFileProvider: FileProvider, @unchecked Sendable {
    public let id = "local"
    public let displayName = "本地"
    public var supportsObservation: Bool { true }

    private let fm = FileManager.default

    public init() {}

    public func url(for path: ProviderPath) -> URL {
        URL(fileURLWithPath: "/" + path.components.joined(separator: "/"))
    }

    public func providerPath(for url: URL) -> ProviderPath {
        let components = url.standardizedFileURL.pathComponents.filter { $0 != "/" }
        return ProviderPath(providerID: id, components: components)
    }

    public func list(_ path: ProviderPath, includeHidden: Bool) async throws -> [FileItem] {
        let dir = url(for: path)
        // Run the directory walk + per-URL resource-value lookups off the main
        // actor. URL resource values are roughly one syscall per file; doing
        // them on MainActor stalls Table redraws and makes selection feel laggy.
        return try await Task.detached(priority: .userInitiated) {
            try Self.listSync(dir: dir, includeHidden: includeHidden)
        }.value
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .creationDateKey,
        .typeIdentifierKey, .nameKey
    ]

    private static func listSync(dir: URL, includeHidden: Bool) throws -> [FileItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: Array(resourceKeys),
            options: includeHidden ? [] : [.skipsHiddenFiles]
        )
        return urls.compactMap(makeItem)
    }

    private static func makeItem(_ url: URL) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: resourceKeys) else { return nil }
        return FileItem(
            id: url.path,
            url: url,
            name: values.name ?? url.lastPathComponent,
            isDirectory: values.isDirectory ?? false,
            isPackage: values.isPackage ?? false,
            isHidden: values.isHidden ?? false,
            isSymlink: values.isSymbolicLink ?? false,
            size: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate,
            createdAt: values.creationDate,
            typeIdentifier: values.typeIdentifier
        )
    }

    public func item(at path: ProviderPath) async -> FileItem? {
        let target = url(for: path)
        return await Task.detached(priority: .userInitiated) {
            Self.makeItem(target)
        }.value
    }

    public func move(_ src: ProviderPath, to dst: ProviderPath) async throws {
        try fm.moveItem(at: url(for: src), to: url(for: dst))
    }

    public func copy(_ src: ProviderPath, to dst: ProviderPath, progress: ((Double) -> Void)?) async throws {
        let srcURL = url(for: src)
        let dstURL = url(for: dst)

        // Directories and packages: use atomic copy (no intermediate progress).
        var isDir: ObjCBool = false
        fm.fileExists(atPath: srcURL.path, isDirectory: &isDir)
        if isDir.boolValue {
            progress?(0)
            try fm.copyItem(at: srcURL, to: dstURL)
            progress?(1)
            return
        }

        // Files < 50 MB: atomic copy — fast enough that 0→1 is acceptable.
        let fileSize = (try? fm.attributesOfItem(atPath: srcURL.path)[.size] as? Int64) ?? 0
        guard fileSize >= 50_000_000, let progressCallback = progress else {
            progress?(0)
            try fm.copyItem(at: srcURL, to: dstURL)
            progress?(1)
            return
        }

        // Large files: stream copy with 2-MB chunks to drive real progress updates.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let reader = FileHandle(forReadingAtPath: srcURL.path) else {
                        throw CocoaError(.fileReadNoSuchFile)
                    }
                    defer { try? reader.close() }

                    guard FileManager.default.createFile(atPath: dstURL.path,
                                                        contents: nil, attributes: nil),
                          let writer = FileHandle(forWritingAtPath: dstURL.path) else {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    defer { try? writer.close() }

                    let bufSize = 2 * 1024 * 1024  // 2 MB
                    var written: Int64 = 0
                    while true {
                        let chunk = reader.readData(ofLength: bufSize)
                        guard !chunk.isEmpty else { break }
                        writer.write(chunk)
                        written += Int64(chunk.count)
                        let frac = min(Double(written) / Double(fileSize), 0.99)
                        DispatchQueue.main.async { progressCallback(frac) }
                    }
                    // Preserve modification date and POSIX permissions.
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: srcURL.path) {
                        var keep = [FileAttributeKey: Any]()
                        [FileAttributeKey.posixPermissions, .modificationDate].forEach {
                            if let v = attrs[$0] { keep[$0] = v }
                        }
                        try? FileManager.default.setAttributes(keep, ofItemAtPath: dstURL.path)
                    }
                    DispatchQueue.main.async { progressCallback(1.0) }
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    public func delete(_ path: ProviderPath, toTrash: Bool) async throws {
        let target = url(for: path)
        if toTrash {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.recycle([target]) { _, error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
        } else {
            try fm.removeItem(at: target)
        }
    }

    public func mkdir(_ path: ProviderPath) async throws {
        try fm.createDirectory(at: url(for: path), withIntermediateDirectories: false)
    }

    public func createFile(_ path: ProviderPath, contents: Data) async throws {
        let target = url(for: path)
        guard !fm.fileExists(atPath: target.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try contents.write(to: target, options: .atomic)
    }

    public func rename(_ path: ProviderPath, to newName: String) async throws {
        let src = url(for: path)
        let dst = src.deletingLastPathComponent().appendingPathComponent(newName)
        try fm.moveItem(at: src, to: dst)
    }

    public func observe(_ path: ProviderPath) -> AsyncStream<FileSystemEvent> {
        let target = url(for: path)
        return AsyncStream { continuation in
            let watcher = DirectoryWatcher(url: target) { event in
                continuation.yield(event)
            }
            watcher.start()
            continuation.onTermination = { _ in watcher.stop() }
        }
    }
}
