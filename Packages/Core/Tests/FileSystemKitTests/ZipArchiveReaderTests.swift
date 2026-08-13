import XCTest
#if canImport(zlib)
import zlib
#endif
@testable import FileSystemKit

final class ZipArchiveReaderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zip-reader-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeZip(named name: String = "test.zip",
                          entries: [StoredZipWriter.Entry]) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try StoredZipWriter.write(entries: entries).write(to: url)
        return url
    }

    // MARK: - 基础解析

    func testParsesStoredEntries() throws {
        let url = try writeZip(entries: [
            .init(name: "hello.txt", data: Data("你好，世界".utf8)),
            .init(name: "docs/", data: Data()),
            .init(name: "docs/a.md", data: Data("# title".utf8)),
        ])
        let reader = try ZipArchiveReader(url: url)
        XCTAssertEqual(reader.entries.count, 3)

        let hello = reader.entries.first { $0.path == "hello.txt" }
        XCTAssertNotNil(hello)
        XCTAssertEqual(hello?.isDirectory, false)
        XCTAssertEqual(hello?.uncompressedSize, Int64("你好，世界".utf8.count))

        let dir = reader.entries.first { $0.path == "docs/" }
        XCTAssertEqual(dir?.isDirectory, true)
    }

    func testExtractStoredFileContent() throws {
        let content = "line1\nline2\n"
        let url = try writeZip(entries: [.init(name: "a.txt", data: Data(content.utf8))])
        let reader = try ZipArchiveReader(url: url)
        let data = try reader.data(for: "a.txt")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), content)
    }

    // MARK: - deflate 解压

    #if canImport(zlib)
    func testInflateRawDeflate() throws {
        let original = String(repeating: "abc123 ", count: 500)
        let compressed = Self.rawDeflate(Data(original.utf8))
        let out = try ZipArchiveReader.inflate(compressed, expectedSize: original.utf8.count)
        XCTAssertEqual(String(decoding: out, as: UTF8.self), original)
    }

    func testReadsDeflateEntry() throws {
        let original = String(repeating: "deflate-me-", count: 200)
        let zipURL = tempDir.appendingPathComponent("deflate.zip")
        try Self.buildSingleEntryZip(to: zipURL, name: "big.txt",
                                     data: Data(original.utf8), method: 8)
        let reader = try ZipArchiveReader(url: zipURL)
        XCTAssertEqual(reader.entries.first?.method, 8)
        let data = try reader.data(for: "big.txt")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), original)
    }
    #endif

    // MARK: - 中文文件名（GBK，无 UTF-8 标志位）

    func testDecodesGBKFileName() throws {
        let zipURL = tempDir.appendingPathComponent("gbk.zip")
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let nameData = try XCTUnwrap("报告.txt".data(using: gbk))
        try Self.buildRawZip(to: zipURL, nameData: nameData, utf8Flag: false,
                             content: Data("x".utf8))
        let reader = try ZipArchiveReader(url: zipURL)
        XCTAssertEqual(reader.entries.first?.path, "报告.txt")
    }

    // MARK: - 损坏 / 非 zip

    func testRejectsGarbage() throws {
        let url = tempDir.appendingPathComponent("junk.zip")
        try Data("not a zip at all, just some text".utf8).write(to: url)
        XCTAssertThrowsError(try ZipArchiveReader(url: url)) { error in
            XCTAssertEqual(error as? ZipError, .notArchive)
        }
    }

    // MARK: - 测试辅助：构造 deflate / 指定编码的 zip

    /// 用 zlib 以 raw deflate（windowBits=-15）压缩数据。
    #if canImport(zlib)
    static func rawDeflate(_ data: Data) -> Data {
        var stream = z_stream()
        deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8,
                      Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        defer { deflateEnd(&stream) }
        var out = Data(count: data.count + 64)
        let outCount = out.count
        data.withUnsafeBytes { inPtr in
            out.withUnsafeMutableBytes { outPtr in
                stream.next_in = UnsafeMutablePointer(mutating: inPtr.baseAddress!.assumingMemoryBound(to: Bytef.self))
                stream.avail_in = uInt(data.count)
                stream.next_out = outPtr.baseAddress!.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(outCount)
                deflate(&stream, Z_FINISH)
            }
        }
        return out.prefix(Int(stream.total_out)) as Data
    }

    /// 构造单条目 zip（可指定 stored/deflate）。
    static func buildSingleEntryZip(to url: URL, name: String, data: Data, method: UInt16) throws {
        let payload = method == 8 ? rawDeflate(data) : data
        let crc = StoredZipWriter.crc32(of: data)
        var out = Data()
        var le = { (v: UInt32) in withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        var le16 = { (v: UInt16) in withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        let nameData = Data(name.utf8)

        le(0x04034b50); le16(20); le16(0x0800); le16(method); le16(0); le16(0x21)
        le(crc); le(UInt32(payload.count)); le(UInt32(data.count))
        le16(UInt16(nameData.count)); le16(0)
        out.append(nameData); out.append(payload)

        let centralOffset = UInt32(out.count)
        le(0x02014b50); le16(20); le16(20); le16(0x0800); le16(method); le16(0); le16(0x21)
        le(crc); le(UInt32(payload.count)); le(UInt32(data.count))
        le16(UInt16(nameData.count)); le16(0); le16(0); le16(0); le16(0); le(0); le(0)
        out.append(nameData)

        le(0x06054b50); le16(0); le16(0); le16(1); le16(1)
        le(UInt32(out.count) - centralOffset); le(centralOffset); le16(0)
        try out.write(to: url)
    }
    #endif

    /// 构造单条目 zip，文件名用原始字节（测 GBK 解码）。
    static func buildRawZip(to url: URL, nameData: Data, utf8Flag: Bool, content: Data) throws {
        let crc = StoredZipWriter.crc32(of: content)
        var out = Data()
        var le = { (v: UInt32) in withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        var le16 = { (v: UInt16) in withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        let flags: UInt16 = utf8Flag ? 0x0800 : 0

        le(0x04034b50); le16(20); le16(flags); le16(0); le16(0); le16(0x21)
        le(crc); le(UInt32(content.count)); le(UInt32(content.count))
        le16(UInt16(nameData.count)); le16(0)
        out.append(nameData); out.append(content)

        let centralOffset = UInt32(out.count)
        le(0x02014b50); le16(20); le16(20); le16(flags); le16(0); le16(0); le16(0x21)
        le(crc); le(UInt32(content.count)); le(UInt32(content.count))
        le16(UInt16(nameData.count)); le16(0); le16(0); le16(0); le16(0); le(0); le(0)
        out.append(nameData)

        le(0x06054b50); le16(0); le16(0); le16(1); le16(1)
        le(UInt32(out.count) - centralOffset); le(centralOffset); le16(0)
        try out.write(to: url)
    }
}
