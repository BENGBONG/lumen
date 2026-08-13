import Foundation
#if canImport(zlib)
import zlib
#endif

/// 归档里一个条目的元数据（zip 来自中央目录，tar 来自头部块）。
public struct ArchiveEntryInfo: Sendable, Equatable {
    /// 内部完整路径，"/" 分隔；目录条目以 "/" 结尾。
    public let path: String
    public let isDirectory: Bool
    public let uncompressedSize: Int64
    public let compressedSize: Int64
    /// 0 = stored, 8 = deflate
    public let method: UInt16
    public let modifiedAt: Date?

    public var name: String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return (trimmed as NSString).lastPathComponent
    }

    public init(path: String, isDirectory: Bool, uncompressedSize: Int64,
                compressedSize: Int64, method: UInt16, modifiedAt: Date?) {
        self.path = path
        self.isDirectory = isDirectory
        self.uncompressedSize = uncompressedSize
        self.compressedSize = compressedSize
        self.method = method
        self.modifiedAt = modifiedAt
    }
}

public enum ZipError: Error, LocalizedError, Equatable {
    case notArchive
    case unsupported(String)
    case corrupt
    case entryNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .notArchive: return "不是有效的归档文件"
        case .unsupported(let what): return "暂不支持：\(what)"
        case .corrupt: return "归档已损坏"
        case .entryNotFound(let name): return "归档中找不到 \(name)"
        }
    }
}

/// 归档读取器的统一抽象：zip（随机访问）与 tar（顺序流）各自实现，
/// RoutedFileProvider 只依赖这个协议。
public protocol ArchiveReader {
    var entries: [ArchiveEntryInfo] { get }
    /// 解压单个条目（目录条目返回空 Data）。
    func data(for entryPath: String) throws -> Data
    /// 全部提取到目标目录（保留内部目录结构），返回总解压字节数。
    @discardableResult
    func extractAll(to dir: URL) throws -> Int64
}

/// 只读 zip 解析器：扫描中央目录获取条目列表，按需解压单个条目。
/// 支持 stored / deflate、UTF-8 与 GBK 文件名。不支持加密与 zip64。
public final class ZipArchiveReader: ArchiveReader {
    public let url: URL
    public private(set) var entries: [ArchiveEntryInfo] = []

    /// 中央目录原始记录（含解压所需的本地头偏移）。
    private struct RawEntry {
        var path: String
        var method: UInt16
        var compressedSize: UInt32
        var uncompressedSize: UInt32
        var localHeaderOffset: UInt32
        var modDate: Date?
        var isDirectory: Bool
    }
    private var raw: [RawEntry] = []

    public init(url: URL) throws {
        self.url = url
        try parse()
    }

    // MARK: - 解析中央目录

    private func parse() throws {
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
        catch { throw ZipError.notArchive }
        guard data.count >= 22 else { throw ZipError.notArchive }

        // 从尾部向前找 EOCD（签名 0x06054b50），注释最长 64KB
        let maxComment = 65_535 + 22
        let scanStart = max(0, data.count - maxComment)
        var eocdOffset: Int? = nil
        var i = data.count - 22
        while i >= scanStart {
            if data.uint32(at: i) == 0x06054b50 {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard let eocd = eocdOffset else { throw ZipError.notArchive }

        let entryCount = Int(data.uint16(at: eocd + 10))
        let centralOffset = Int(data.uint32(at: eocd + 16))
        guard centralOffset >= 0, centralOffset < data.count else { throw ZipError.corrupt }
        // zip64 检测：count 或 offset 为哨兵值则不支持
        if entryCount == 0xFFFF || centralOffset == 0xFFFFFFFF {
            throw ZipError.unsupported("zip64 归档")
        }

        var offset = centralOffset
        var parsed: [RawEntry] = []
        parsed.reserveCapacity(entryCount)

        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, data.uint32(at: offset) == 0x02014b50 else {
                throw ZipError.corrupt
            }
            let flags = data.uint16(at: offset + 8)
            let method = data.uint16(at: offset + 10)
            let modTime = data.uint16(at: offset + 12)
            let modDate = data.uint16(at: offset + 14)
            let compressed = data.uint32(at: offset + 20)
            let uncompressed = data.uint32(at: offset + 24)
            let nameLen = Int(data.uint16(at: offset + 28))
            let extraLen = Int(data.uint16(at: offset + 30))
            let commentLen = Int(data.uint16(at: offset + 32))
            let externalAttrs = data.uint32(at: offset + 38)
            let localOffset = data.uint32(at: offset + 42)

            let nameStart = offset + 46
            guard nameStart + nameLen <= data.count else { throw ZipError.corrupt }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLen))
            let isUTF8 = (flags & 0x0800) != 0
            let name = Self.decodeName(nameData, utf8: isUTF8)
            let isDir = name.hasSuffix("/") || (externalAttrs & 0x10) != 0

            parsed.append(RawEntry(
                path: name,
                method: method,
                compressedSize: compressed,
                uncompressedSize: uncompressed,
                localHeaderOffset: localOffset,
                modDate: Self.dosDate(time: modTime, date: modDate),
                isDirectory: isDir
            ))
            offset = nameStart + nameLen + extraLen + commentLen
        }
        raw = parsed
        entries = parsed.map {
            ArchiveEntryInfo(path: $0.path, isDirectory: $0.isDirectory,
                         uncompressedSize: Int64($0.uncompressedSize),
                         compressedSize: Int64($0.compressedSize),
                         method: $0.method, modifiedAt: $0.modDate)
        }
    }

    /// 文件名解码：UTF-8 优先；非 UTF-8 标志时先按 UTF-8 试（很多工具不设标志位），
    /// 失败按 GB18030（Windows 中文 zip 的常见编码）。
    static func decodeName(_ data: Data, utf8: Bool) -> String {
        if utf8 { return String(decoding: data, as: UTF8.self) }
        if let s = String(data: data, encoding: .utf8) { return s }
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(data: data, encoding: gbk) ?? String(decoding: data, as: UTF8.self)
    }

    static func dosDate(time: UInt16, date: UInt16) -> Date? {
        var comps = DateComponents()
        comps.year   = Int((date >> 9) & 0x7F) + 1980
        comps.month  = Int((date >> 5) & 0x0F)
        comps.day    = Int(date & 0x1F)
        comps.hour   = Int((time >> 11) & 0x1F)
        comps.minute = Int((time >> 5) & 0x3F)
        comps.second = Int(time & 0x1F) * 2
        return Calendar.current.date(from: comps)
    }

    // MARK: - 解压

    /// 解压单个条目（目录条目返回空 Data）。
    public func data(for entryPath: String) throws -> Data {
        guard let entry = raw.first(where: { $0.path == entryPath }) else {
            throw ZipError.entryNotFound(entryPath)
        }
        guard !entry.isDirectory else { return Data() }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let local = Int(entry.localHeaderOffset)
        try handle.seek(toOffset: UInt64(local))
        let header = try handle.read(upToCount: 30) ?? Data()
        guard header.count == 30, header.uint32(at: 0) == 0x04034b50 else {
            throw ZipError.corrupt
        }
        let nameLen = Int(header.uint16(at: 26))
        let extraLen = Int(header.uint16(at: 28))
        try handle.seek(toOffset: UInt64(local + 30 + nameLen + extraLen))
        let compressed = try handle.read(upToCount: Int(entry.compressedSize)) ?? Data()
        guard compressed.count == Int(entry.compressedSize) else { throw ZipError.corrupt }

        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try Self.inflate(compressed, expectedSize: Int(entry.uncompressedSize))
        default:
            throw ZipError.unsupported("压缩方式 \(entry.method)")
        }
    }

    /// 全部提取到目标目录（保留内部目录结构）。返回总解压字节数。
    @discardableResult
    public func extractAll(to dir: URL) throws -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        for entry in raw {
            let dest = dir.appendingPathComponent(entry.path)
            if entry.isDirectory {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: dest.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                let content = try data(for: entry.path)
                try content.write(to: dest, options: .atomic)
                total += Int64(content.count)
            }
        }
        return total
    }

    /// raw deflate 解压（windowBits = -15）。
    static func inflate(_ data: Data, expectedSize: Int) throws -> Data {
        #if canImport(zlib)
        var stream = z_stream()
        var status = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw ZipError.corrupt }
        defer { inflateEnd(&stream) }

        var output = Data(count: max(expectedSize, 1))
        let inCount = data.count
        let produced: Int = try data.withUnsafeBytes { inPtr -> Int in
            guard let inBase = inPtr.baseAddress else { throw ZipError.corrupt }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inBase.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(inCount)
            return try output.withUnsafeMutableBytes { outPtr -> Int in
                guard let outBase = outPtr.baseAddress else { throw ZipError.corrupt }
                stream.next_out = outBase.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(outPtr.count)
                status = zlib.inflate(&stream, Z_FINISH)
                guard status == Z_STREAM_END || status == Z_OK else { throw ZipError.corrupt }
                return Int(stream.total_out)
            }
        }
        return output.prefix(produced) as Data
        #else
        throw ZipError.unsupported("deflate 解压（zlib 不可用）")
        #endif
    }
}

// MARK: - Data 小端读取辅助

extension Data {
    func uint16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    func uint32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }
}
