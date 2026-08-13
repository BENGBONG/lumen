import Foundation
#if canImport(zlib)
import zlib
#endif

/// 只读 tar 解析器。tar 是顺序流格式：没有中央目录，条目逐个头部块扫出来。
///
/// 支持：
/// - plain `.tar`（直接解析）
/// - `.tar.gz` / `.tgz`（先整流 gunzip 再解析；解压总量超过 1GB 拒绝）
/// - ustar prefix、GNU longname（'L'）、pax 扩展头（'x'，取 path=）
///   —— 覆盖 macOS bsdtar 与 GNU tar 的常见产物
///
/// 不支持：符号链接条目（跳过）、base-256 超大尺寸字段（极少见）。
public final class TarArchiveReader: ArchiveReader {
    public let url: URL
    public private(set) var entries: [ArchiveEntryInfo] = []

    static let maxInflatedBytes: Int64 = 1_000_000_000

    /// 完整解压后的 tar 字节流（plain tar 就是文件本身）。
    private let payload: Data

    private struct RawEntry {
        var path: String
        var isDirectory: Bool
        var size: Int64
        var mtime: Date?
        var dataOffset: Int
    }
    private var raw: [RawEntry] = []

    public init(url: URL) throws {
        self.url = url
        let fileData: Data
        do { fileData = try Data(contentsOf: url, options: .mappedIfSafe) }
        catch { throw ZipError.notArchive }

        let lower = url.lastPathComponent.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") || url.pathExtension.lowercased() == "gz" {
            self.payload = try Self.gunzip(fileData, maxBytes: Self.maxInflatedBytes)
        } else {
            self.payload = fileData
        }
        try parse()
    }

    // MARK: - 解析

    private func parse() throws {
        let data = payload
        guard data.count >= 1024 else { throw ZipError.notArchive }

        var offset = 0
        var pendingLongName: String? = nil     // GNU 'L' 或 pax path= 挂起
        var parsed: [RawEntry] = []

        while offset + 512 <= data.count {
            let block = data.subdata(in: offset..<(offset + 512))
            if block.allSatisfy({ $0 == 0 }) { break }   // 结束块

            let size = Self.octal(block, 124, 12)
            let mtime = Self.octal(block, 136, 12)
            let typeflag = block[156]
            let dataStart = offset + 512
            let dataBlocks = Int((size + 511) / 512)
            let nextOffset = dataStart + dataBlocks * 512
            guard nextOffset <= data.count || size == 0 else { throw ZipError.corrupt }

            switch typeflag {
            case UInt8(ascii: "x"), UInt8(ascii: "g"):
                // pax 扩展头：data 是 "len key=value\n" 记录序列
                let record = data.subdata(in: dataStart..<min(dataStart + Int(size), data.count))
                if typeflag == UInt8(ascii: "x"),
                   let p = Self.paxValue(forKey: "path", in: record) {
                    pendingLongName = p
                }
            case UInt8(ascii: "L"):
                // GNU longname：data 是 NUL 结尾的长文件名，作用于下一条目
                let nameData = data.subdata(in: dataStart..<min(dataStart + Int(size), data.count))
                pendingLongName = Self.cString(nameData, 0, nameData.count)
            case UInt8(ascii: "K"):
                break   // GNU longlink：软链目标，v1 不建链接条目，忽略
            case UInt8(ascii: "0"), UInt8(ascii: "\0"), UInt8(ascii: "5"),
                 UInt8(ascii: "1"), UInt8(ascii: "2"):
                // 普通文件 / 目录；硬链软链按 0 字节文件收录，保证结构可见
                guard var name = pendingLongName ?? Self.cString(block, 0, 100) else {
                    offset = nextOffset
                    continue
                }
                pendingLongName = nil
                // ustar prefix
                if name.count <= 100 {
                    let magic = Self.cString(block, 257, 6)
                    if let magic, magic.hasPrefix("ustar") {
                        if let prefix = Self.cString(block, 345, 155), !prefix.isEmpty {
                            name = prefix + "/" + name
                        }
                    }
                }
                // 去掉 bsdtar 爱加的 "./" 前缀
                while name.hasPrefix("./") { name.removeFirst(2) }
                guard !name.isEmpty else { offset = nextOffset; continue }

                let isDir = (typeflag == UInt8(ascii: "5")) || name.hasSuffix("/")
                let isLink = (typeflag == UInt8(ascii: "1") || typeflag == UInt8(ascii: "2"))
                if isDir && !name.hasSuffix("/") { name += "/" }
                parsed.append(RawEntry(
                    path: name,
                    isDirectory: isDir,
                    size: (isDir || isLink) ? 0 : size,
                    mtime: mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil,
                    dataOffset: dataStart
                ))
            default:
                break   // 其他类型（设备节点等）跳过，但仍要跳过其数据块
            }
            offset = nextOffset
        }

        guard !parsed.isEmpty else { throw ZipError.notArchive }
        raw = parsed
        entries = parsed.map {
            ArchiveEntryInfo(path: $0.path, isDirectory: $0.isDirectory,
                             uncompressedSize: $0.size, compressedSize: $0.size,
                             method: 0, modifiedAt: $0.mtime)
        }
    }

    // MARK: - 解压

    public func data(for entryPath: String) throws -> Data {
        guard let entry = raw.first(where: { $0.path == entryPath }) else {
            throw ZipError.entryNotFound(entryPath)
        }
        guard !entry.isDirectory else { return Data() }
        let end = min(entry.dataOffset + Int(entry.size), payload.count)
        guard entry.dataOffset <= end else { throw ZipError.corrupt }
        return payload.subdata(in: entry.dataOffset..<end)
    }

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
                try data(for: entry.path).write(to: dest, options: .atomic)
                total += entry.size
            }
        }
        return total
    }

    // MARK: - 字段解析辅助

    /// tar 数字字段：八进制 ASCII，NUL/空格结尾。
    static func octal(_ block: Data, _ start: Int, _ len: Int) -> Int64 {
        var value: Int64 = 0
        for i in start..<(start + len) {
            let byte = block[i]
            if byte == 0 || byte == UInt8(ascii: " ") {
                if value > 0 { break } else { continue }
            }
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "7") else { break }
            value = value * 8 + Int64(byte - UInt8(ascii: "0"))
        }
        return value
    }

    /// NUL 结尾的 C 字符串；data 内 start..<start+len 区间。
    static func cString(_ data: Data, _ start: Int, _ len: Int) -> String? {
        guard start < data.count else { return nil }
        let end = min(start + len, data.count)
        var bytes = data.subdata(in: start..<end)
        if let nul = bytes.firstIndex(of: 0) { bytes = bytes[..<nul] }
        guard !bytes.isEmpty else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// pax 记录解析："LEN KEY=VALUE\n"，LEN 含自身长度。
    static func paxValue(forKey key: String, in data: Data) -> String? {
        var i = data.startIndex
        while i < data.endIndex {
            guard let spaceIdx = data[i...].firstIndex(of: UInt8(ascii: " ")) else { break }
            guard let len = Int(String(decoding: data[i..<spaceIdx], as: UTF8.self)), len > 0,
                  i + len <= data.endIndex else { break }
            let record = data[(spaceIdx + 1)..<(i + len - 1)]   // 去掉末尾 \n
            let text = String(decoding: record, as: UTF8.self)
            if text.hasPrefix(key + "=") {
                return String(text.dropFirst(key.count + 1))
            }
            i += len
        }
        return nil
    }

    // MARK: - gzip 解压（windowBits = 31，自动识别 gzip 头）

    static func gunzip(_ data: Data, maxBytes: Int64) throws -> Data {
        #if canImport(zlib)
        var stream = z_stream()
        var status = inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw ZipError.corrupt }
        defer { inflateEnd(&stream) }

        var output = Data()
        output.reserveCapacity(min(data.count * 4, 64 << 20))
        var chunk = [UInt8](repeating: 0, count: 1 << 20)

        return try data.withUnsafeBytes { inPtr -> Data in
            guard let inBase = inPtr.baseAddress else { throw ZipError.corrupt }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inBase.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(data.count)
            while true {
                let produced = try chunk.withUnsafeMutableBytes { outPtr -> Int in
                    stream.next_out = outPtr.baseAddress!.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(outPtr.count)
                    status = zlib.inflate(&stream, Z_NO_FLUSH)
                    guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
                        throw ZipError.corrupt
                    }
                    return outPtr.count - Int(stream.avail_out)
                }
                output.append(contentsOf: chunk[0..<produced])
                if Int64(output.count) > maxBytes {
                    throw ZipError.unsupported("归档过大（解压后超过 1GB）")
                }
                if status == Z_STREAM_END { break }
                if produced == 0 && status == Z_BUF_ERROR { throw ZipError.corrupt }
            }
            return output
        }
        #else
        throw ZipError.unsupported("gzip 解压（zlib 不可用）")
        #endif
    }
}
