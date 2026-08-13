import Foundation
#if canImport(zlib)
import zlib
#endif

/// 最小 zip 写入器：只写 stored（不压缩）条目。
/// 用途：生成 OOXML 模板（docx/xlsx/pptx 本质是 zip）、测试夹具。
/// 不支持：压缩、加密、zip64——这些不在它的职责范围内。
public enum StoredZipWriter {

    public struct Entry {
        public let name: String   // 内部路径，"/" 分隔；目录以 "/" 结尾
        public let data: Data
        public init(name: String, data: Data) {
            self.name = name
            self.data = data
        }
    }

    public enum WriterError: Error {
        case invalidName
    }

    /// 把条目写成标准 zip 字节流。
    public static func write(entries: [Entry]) throws -> Data {
        var out = Data()
        var central = Data()

        for entry in entries {
            guard let nameData = entry.name.data(using: .utf8), !entry.name.isEmpty else {
                throw WriterError.invalidName
            }
            let crc = crc32(of: entry.data)
            let offset = UInt32(out.count)
            let size = UInt32(entry.data.count)

            // Local file header
            out.appendUInt32(0x04034b50)   // signature
            out.appendUInt16(20)           // version needed
            out.appendUInt16(0x0800)       // flags: UTF-8 names
            out.appendUInt16(0)            // method: stored
            out.appendUInt16(0)            // mod time
            out.appendUInt16(0x21)         // mod date (1980-01-01)
            out.appendUInt32(crc)
            out.appendUInt32(size)         // compressed = uncompressed (stored)
            out.appendUInt32(size)
            out.appendUInt16(UInt16(nameData.count))
            out.appendUInt16(0)            // extra length
            out.append(nameData)
            out.append(entry.data)

            // Central directory entry
            central.appendUInt32(0x02014b50)
            central.appendUInt16(20)       // version made by
            central.appendUInt16(20)       // version needed
            central.appendUInt16(0x0800)   // flags: UTF-8
            central.appendUInt16(0)        // method
            central.appendUInt16(0)        // mod time
            central.appendUInt16(0x21)     // mod date
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(UInt16(nameData.count))
            central.appendUInt16(0)        // extra
            central.appendUInt16(0)        // comment
            central.appendUInt16(0)        // disk number
            central.appendUInt16(0)        // internal attrs
            central.appendUInt32(entry.name.hasSuffix("/") ? 0x10 : 0)  // external attrs: dir bit
            central.appendUInt32(offset)   // local header offset
            central.append(nameData)
        }

        let centralOffset = UInt32(out.count)
        out.append(central)

        // End of central directory
        out.appendUInt32(0x06054b50)
        out.appendUInt16(0)                // disk
        out.appendUInt16(0)                // central start disk
        out.appendUInt16(UInt16(entries.count))
        out.appendUInt16(UInt16(entries.count))
        out.appendUInt32(UInt32(central.count))
        out.appendUInt32(centralOffset)
        out.appendUInt16(0)                // comment length
        return out
    }

    public static func crc32(of data: Data) -> UInt32 {
        #if canImport(zlib)
        return data.withUnsafeBytes { ptr -> UInt32 in
            guard let base = ptr.baseAddress else { return 0 }
            return UInt32(zlib.crc32(0, base.assumingMemoryBound(to: Bytef.self),
                                     uInt(data.count)))
        }
        #else
        // 无 zlib 时的纯 Swift 回退（建表法）
        return crc32Fallback(data)
        #endif
    }

    #if !canImport(zlib)
    private static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }
    private static func crc32Fallback(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
    #endif
}

private extension Data {
    mutating func appendUInt16(_ v: UInt16) { appendLittleEndian(v) }
    mutating func appendUInt32(_ v: UInt32) { appendLittleEndian(v) }
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ v: T) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
