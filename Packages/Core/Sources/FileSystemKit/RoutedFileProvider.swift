import Foundation
import CryptoKit

public enum RoutedProviderError: Error, LocalizedError, Equatable {
    case archiveReadOnly

    public var errorDescription: String? {
        "归档内部是只读的——请先把文件复制出来再修改"
    }
}

/// 路由型 FileProvider：对外表现为一棵统一的本地文件树，
/// 当路径穿过归档文件（zip / tar / tgz / tar.gz）时自动切换为
/// 「归档虚拟目录」语义——可以像浏览普通文件夹一样浏览归档内部，无需解压到用户目录。
///
/// 路径编码：与普通本地路径完全一致（providerID = "local"），
/// 例如 /Users/x/报告.zip/数据/表格.xlsx。路由规则 = 路径的某个前缀
/// 是磁盘上真实存在的 zip 文件时，该前缀指向归档，其余部分是归档内部路径。
///
/// 实现说明：列目录走中央目录（快）；条目一旦被交互（预览/拖出/复制），
/// 其内容来自会话级临时缓存（首次 list 时全量解压到 NSTemporaryDirectory）。
/// 缓存不落用户目录，重启自动清理。
public final class RoutedFileProvider: FileProvider, @unchecked Sendable {
    public let id = "local"          // 与 LocalFileProvider 一致：路径编码完全兼容
    public let displayName = "本地"
    public var supportsObservation: Bool { true }

    /// 解压总量上限，超出拒绝浏览（防 4GB 归档撑爆临时盘）。
    public static let maxArchiveBytes: Int64 = 1_000_000_000

    private let local = LocalFileProvider()
    private let fm = FileManager.default
    private let lock = NSLock()
    /// key = archivePath|mtime → 解析器（zip / tar 各自实现 ArchiveReader）
    private var archives: [String: any ArchiveReader] = [:]
    /// key 同上 → 解压缓存根目录
    private var extracted: [String: URL] = [:]

    public init() {
        // 会话级缓存：启动时清掉上次遗留
        try? fm.removeItem(at: Self.cacheRoot)
    }

    /// 缓存目录名：SHA256 前 16 字节 hex（hashValue 有碰撞风险且每次启动随机化）。
    static func cacheKey(for raw: String) -> String {
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static var cacheRoot: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("LumenZipCache")
    }

    /// 该文件名是否是可虚拟浏览的归档（UI 双击中转也用它判断）。
    public static func isBrowsableArchive(name: String) -> Bool {
        let lower = name.lowercased()
        if lower.hasSuffix(".tar.gz") { return true }
        let ext = (lower as NSString).pathExtension
        return ["zip", "tar", "tgz"].contains(ext)
    }

    // MARK: - 路由解析

    /// 把路径拆成 (归档文件 URL, 归档内部组件)。路径不穿过任何支持的归档时返回 nil。
    private func resolve(_ path: ProviderPath) -> (archive: URL, inner: [String])? {
        let components = path.components
        // 从长到短找第一个「存在且是普通文件且是可浏览归档」的前缀
        for end in stride(from: components.count, through: 1, by: -1) {
            let prefix = components[..<end]
            let url = URL(fileURLWithPath: "/" + prefix.joined(separator: "/"))
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            guard Self.isBrowsableArchive(name: url.lastPathComponent) else { continue }
            return (url, Array(components[end...]))
        }
        return nil
    }

    /// 路径是否严格位于某个归档内部（归档文件本身不算）。
    public func isInsideArchive(_ path: ProviderPath) -> Bool {
        guard let (_, inner) = resolve(path) else { return false }
        return !inner.isEmpty
    }

    private func archive(for url: URL) throws -> any ArchiveReader {
        let mtime = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(mtime)"
        lock.lock()
        if let cached = archives[key] { lock.unlock(); return cached }
        lock.unlock()

        let lower = url.lastPathComponent.lowercased()
        let reader: any ArchiveReader
        if lower.hasSuffix(".tar") || lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") {
            reader = try TarArchiveReader(url: url)
        } else {
            reader = try ZipArchiveReader(url: url)
        }
        let total = reader.entries.reduce(Int64(0)) { $0 + $1.uncompressedSize }
        guard total <= Self.maxArchiveBytes else {
            throw ZipError.unsupported("归档过大（解压后超过 1GB）")
        }
       lock.lock()
        archives[key] = reader
        lock.unlock()
        return reader
    }

    /// 确保归档已解压到缓存，返回缓存根目录。
    private func ensureExtracted(_ archiveURL: URL) throws -> URL {
        let reader = try archive(for: archiveURL)
        let mtime = (try? fm.attributesOfItem(atPath: archiveURL.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let key = "\(archiveURL.path)|\(mtime)"

        lock.lock()
        if let dir = extracted[key] { lock.unlock(); return dir }
        lock.unlock()

        let dir = Self.cacheRoot
            .appendingPathComponent(Self.cacheKey(for: key))
            .appendingPathComponent(archiveURL.lastPathComponent)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try reader.extractAll(to: dir)
        }
        lock.lock()
        extracted[key] = dir
        lock.unlock()
        return dir
    }

    // MARK: - FileProvider

    public func url(for path: ProviderPath) -> URL {
        guard let (archive, inner) = resolve(path) else {
            return local.url(for: path)
        }
        guard !inner.isEmpty else { return archive }
        guard let cacheDir = try? ensureExtracted(archive) else { return archive }
        return cacheDir.appendingPathComponent(inner.joined(separator: "/"))
    }

    public func providerPath(for url: URL) -> ProviderPath {
        local.providerPath(for: url)
    }

    public func list(_ path: ProviderPath, includeHidden: Bool) async throws -> [FileItem] {
        guard let (archiveURL, inner) = resolve(path) else {
            return try await local.list(path, includeHidden: includeHidden)
        }
        let reader = try archive(for: archiveURL)
        // 首次接触即解压（后续 url(for:) / 拖拽 / QuickLook 才有真实文件可用）
        _ = try ensureExtracted(archiveURL)

        let innerPath = inner.joined(separator: "/")
        let prefix = innerPath.isEmpty ? "" : innerPath + "/"
        var seen = Set<String>()
        var result: [FileItem] = []

        for entry in reader.entries {
            guard entry.path.hasPrefix(prefix) else { continue }
            let rest = String(entry.path.dropFirst(prefix.count))
            guard !rest.isEmpty else { continue }
            // 只取当前层级（rest 不含 "/"，或以 "/" 结尾的目录名）
            let isDirEntry: Bool
            let name: String
            if let slashIdx = rest.firstIndex(of: "/") {
                let dirName = String(rest[..<slashIdx])
                guard seen.insert(dirName).inserted else { continue }
                name = dirName
                isDirEntry = true
            } else {
                guard seen.insert(rest).inserted else { continue }
                name = rest
                isDirEntry = entry.isDirectory
            }
            let childPath = path.appending(name)
            result.append(FileItem(
                id: childPath.displayString,
                url: url(for: childPath),
                name: name,
                isDirectory: isDirEntry,
                isPackage: false,
                isHidden: name.hasPrefix("."),
                isSymlink: false,
                size: isDirEntry ? -1 : entry.uncompressedSize,
                modifiedAt: entry.modifiedAt,
                createdAt: nil,
                typeIdentifier: nil
            ))
        }
        return result
    }

    public func item(at path: ProviderPath) async -> FileItem? {
        guard let (archiveURL, inner) = resolve(path) else {
            return await local.item(at: path)
        }
        // 归档文件本身 → 用本地元数据
        guard !inner.isEmpty else { return await local.item(at: path) }
        guard let reader = try? archive(for: archiveURL) else { return nil }
        let innerPath = inner.joined(separator: "/")
        guard let entry = reader.entries.first(where: {
            $0.path == innerPath || $0.path == innerPath + "/"
        }) else { return nil }
        return FileItem(
            id: path.displayString,
            url: url(for: path),
            name: entry.name,
            isDirectory: entry.isDirectory,
            isPackage: false,
            isHidden: entry.name.hasPrefix("."),
            isSymlink: false,
            size: entry.isDirectory ? -1 : entry.uncompressedSize,
            modifiedAt: entry.modifiedAt,
            createdAt: nil,
            typeIdentifier: nil
        )
    }

    public func copy(_ src: ProviderPath, to dst: ProviderPath, progress: ((Double) -> Void)?) async throws {
        if isInsideArchive(dst) { throw RoutedProviderError.archiveReadOnly }
        if let srcR = resolve(src), !srcR.inner.isEmpty {
            // 从缓存拷出（url(for:) 已确保解压）
            let srcURL = url(for: src)
            let dstURL = local.url(for: dst)
            progress?(0)
            try fm.copyItem(at: srcURL, to: dstURL)
            progress?(1)
            return
        }
        try await local.copy(src, to: dst, progress: progress)
    }

    /// 只有「严格位于归档内部」的路径才只读；归档文件本身仍是普通本地文件，
    /// 移动/覆盖它走正常本地语义（冲突覆盖由队列先删后移，此时目标已不存在）。
    public func move(_ src: ProviderPath, to dst: ProviderPath) async throws {
        if isInsideArchive(src) || isInsideArchive(dst) {
            throw RoutedProviderError.archiveReadOnly
        }
        try await local.move(src, to: dst)
    }

    public func delete(_ path: ProviderPath, toTrash: Bool) async throws {
        if isInsideArchive(path) { throw RoutedProviderError.archiveReadOnly }
        try await local.delete(path, toTrash: toTrash)
    }

    public func rename(_ path: ProviderPath, to newName: String) async throws {
        if isInsideArchive(path) { throw RoutedProviderError.archiveReadOnly }
        try await local.rename(path, to: newName)
    }

    public func mkdir(_ path: ProviderPath) async throws {
        if isInsideArchive(path) { throw RoutedProviderError.archiveReadOnly }
        try await local.mkdir(path)
    }

    public func createFile(_ path: ProviderPath, contents: Data) async throws {
        if isInsideArchive(path) { throw RoutedProviderError.archiveReadOnly }
        try await local.createFile(path, contents: contents)
    }

    public func observe(_ path: ProviderPath) -> AsyncStream<FileSystemEvent> {
        if resolve(path) != nil { return AsyncStream { $0.finish() } }
        return local.observe(path)
    }
}
