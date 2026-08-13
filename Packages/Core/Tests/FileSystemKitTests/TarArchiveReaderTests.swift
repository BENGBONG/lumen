import XCTest
#if canImport(zlib)
import zlib
#endif
@testable import FileSystemKit

final class TarArchiveReaderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tar-reader-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - 基础解析

    func testParsesPlainTar() throws {
        let url = tempDir.appendingPathComponent("plain.tar")
        try Self.buildTar(entries: [
            ("readme.md", Data("# hi".utf8), false),
            ("src/", Data(), true),
            ("src/main.py", Data("print(1)".utf8), false),
        ]).write(to: url)

        let reader = try TarArchiveReader(url: url)
        XCTAssertEqual(reader.entries.count, 3)
        XCTAssertEqual(reader.entries.first { $0.path == "src/" }?.isDirectory, true)
        XCTAssertEqual(reader.entries.first { $0.path == "readme.md" }?.uncompressedSize, 4)
        XCTAssertNotNil(reader.entries.first?.modifiedAt)

        let content = try reader.data(for: "src/main.py")
        XCTAssertEqual(String(decoding: content, as: UTF8.self), "print(1)")
    }

    func testStripsDotSlashPrefix() throws {
        let url = tempDir.appendingPathComponent("dotslash.tar")
        try Self.buildTar(entries: [("./a.txt", Data("x".utf8), false)]).write(to: url)
        let reader = try TarArchiveReader(url: url)
        XCTAssertEqual(reader.entries.first?.path, "a.txt")
    }

    func testUstarPrefix() throws {
        // 名字 >100 字符时 ustar 拆 prefix + name
        let deep = String(repeating: "d", count: 80) + "/" + String(repeating: "e", count: 40) + ".txt"
        let split = deep.index(deep.startIndex, offsetBy: 80)
        let prefix = String(deep[..<split])
        let name = String(deep[split...]).dropFirst()  // 去掉 "/"
        let url = tempDir.appendingPathComponent("ustar.tar")
        try Self.buildTar(entries: [], rawBlocks: [
            Self.header(name: String(name), size: 2, typeflag: UInt8(ascii: "0"), prefix: prefix),
            Self.dataBlock(Data("ok".utf8)),
        ]).write(to: url)
        let reader = try TarArchiveReader(url: url)
        XCTAssertEqual(reader.entries.first?.path, deep)
        XCTAssertEqual(String(decoding: try reader.data(for: deep), as: UTF8.self), "ok")
    }

    // MARK: - 长文件名

    func testPaxLongPath() throws {
        let longName = "很长的目录/" + String(repeating: "档", count: 60) + ".txt"
        let record = "path=\(longName)\n"
        let recordData = Data(record.utf8)
        // pax 记录格式："len key=value\n"，len 含自身
        var len = recordData.count + 4   // 预留 "xxx " 长度
        len = ("\(len) ".count + recordData.count)
        let paxData = Data("\(len) \(record)".utf8)

        let url = tempDir.appendingPathComponent("pax.tar")
        try Self.buildTar(entries: [], rawBlocks: [
            Self.header(name: "PaxHeader/x", size: paxData.count, typeflag: UInt8(ascii: "x")),
            Self.dataBlock(paxData),
            Self.header(name: "short", size: 2, typeflag: UInt8(ascii: "0")),
            Self.dataBlock(Data("ok".utf8)),
        ]).write(to: url)
        let reader = try TarArchiveReader(url: url)
        XCTAssertEqual(reader.entries.first?.path, longName)
        XCTAssertEqual(String(decoding: try reader.data(for: longName), as: UTF8.self), "ok")
    }

    func testGnuLongName() throws {
        let longName = String(repeating: "long-dir/", count: 15) + "file.txt"  // >100 字符
        let nameData = Data((longName + "\0").utf8)
        let url = tempDir.appendingPathComponent("gnu.tar")
        try Self.buildTar(entries: [], rawBlocks: [
            Self.header(name: "././@LongLink", size: nameData.count, typeflag: UInt8(ascii: "L")),
            Self.dataBlock(nameData),
            Self.header(name: "truncated", size: 2, typeflag: UInt8(ascii: "0")),
            Self.dataBlock(Data("ok".utf8)),
        ]).write(to: url)
        let reader = try TarArchiveReader(url: url)
        XCTAssertEqual(reader.entries.first?.path, longName)
    }

    // MARK: - gzip

    #if canImport(zlib)
    func testTarGzRoundTrip() throws {
        let tarBytes = Self.buildTar(entries: [
            ("docs/", Data(), true),
            ("docs/报告.txt", Data("中文内容".utf8), false),
        ])
        let url = tempDir.appendingPathComponent("bundle.tar.gz")
        try Self.gzip(tarBytes).write(to: url)

        let reader = try TarArchiveReader(url: url)
        XCTAssertEqual(Set(reader.entries.map(\.path)), ["docs/", "docs/报告.txt"])
        let content = try reader.data(for: "docs/报告.txt")
        XCTAssertEqual(String(decoding: content, as: UTF8.self), "中文内容")
    }
    #endif

    // MARK: - 与 RoutedFileProvider 集成

    #if canImport(zlib)
    func testRoutedProviderBrowsesTgz() async throws {
        let tarBytes = Self.buildTar(entries: [
            ("a.txt", Data("aaa".utf8), false),
            ("sub/", Data(), true),
            ("sub/b.txt", Data("bbb".utf8), false),
        ])
        let url = tempDir.appendingPathComponent("pack.tgz")
        try Self.gzip(tarBytes).write(to: url)

        let provider = RoutedFileProvider()
        let root = provider.providerPath(for: url)
        let items = try await provider.list(root, includeHidden: false)
        XCTAssertEqual(Set(items.map(\.name)), ["a.txt", "sub"])

        let sub = try await provider.list(root.appending("sub"), includeHidden: false)
        XCTAssertEqual(sub.map(\.name), ["b.txt"])

        // 拷出
        let dst = provider.providerPath(for: tempDir).appending("out.txt")
        try await provider.copy(root.appending("sub").appending("b.txt"), to: dst, progress: nil)
        XCTAssertEqual(try String(contentsOf: tempDir.appendingPathComponent("out.txt"),
                                  encoding: .utf8), "bbb")
    }
    #endif

    func testRejectsGarbage() throws {
        let url = tempDir.appendingPathComponent("junk.tar")
        try Data(repeating: 7, count: 2048).write(to: url)
        XCTAssertThrowsError(try TarArchiveReader(url: url))
    }

    // MARK: - 系统 bsdtar 交叉验证（pax 格式 + ./ 前缀的真实产物）

    func testReadsSystemBsdtarProduct() throws {
        // 造真实目录树
        let src = tempDir.appendingPathComponent("src")
        try FileManager.default.createDirectory(
            at: src.appendingPathComponent("嵌套/深层"), withIntermediateDirectories: true)
        try "根文件".write(to: src.appendingPathComponent("根.txt"),
                          atomically: true, encoding: .utf8)
        try String(repeating: "深", count: 200).write(
            to: src.appendingPathComponent("嵌套/深层/内容.txt"),
            atomically: true, encoding: .utf8)
        // 超长文件名触发 pax path= 扩展头
        let longName = String(repeating: "长", count: 120) + ".txt"
        try "长名文件".write(to: src.appendingPathComponent(longName),
                            atomically: true, encoding: .utf8)

        let tgz = tempDir.appendingPathComponent("system.tar.gz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["czf", tgz.path, "-C", src.path, "."]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let reader = try TarArchiveReader(url: tgz)
        let paths = Set(reader.entries.map(\.path))
        XCTAssertTrue(paths.contains("根.txt"), "实际条目: \(paths)")
        XCTAssertTrue(paths.contains("嵌套/深层/内容.txt"), "实际条目: \(paths)")
        XCTAssertTrue(paths.contains(longName), "pax 长文件名未解析: \(paths)")
        XCTAssertEqual(String(decoding: try reader.data(for: "根.txt"), as: UTF8.self), "根文件")
    }

    // MARK: - 测试夹具：tar 构造器

    struct TarEntry { let name: String; let data: Data; let isDir: Bool }

    /// 由 (名字, 内容, 是否目录) 列表构造 tar 字节流。
    static func buildTar(entries: [(String, Data, Bool)], rawBlocks: [Data] = []) -> Data {
        var out = Data()
        for (name, data, isDir) in entries {
            out.append(header(name: name, size: isDir ? 0 : data.count,
                              typeflag: isDir ? UInt8(ascii: "5") : UInt8(ascii: "0")))
            if !isDir { out.append(dataBlock(data)) }
        }
        for block in rawBlocks { out.append(block) }
        out.append(Data(count: 1024))   // 结束：两个零块
        return out
    }

    static func header(name: String, size: Int, typeflag: UInt8,
                       mtime: Int64 = 1_700_000_000, prefix: String = "") -> Data {
        var block = [UInt8](repeating: 0, count: 512)
        write(name, into: &block, at: 0, max: 100)
        write("0000644\0", into: &block, at: 100, max: 8)
        write("0000000\0", into: &block, at: 108, max: 8)
        write("0000000\0", into: &block, at: 116, max: 8)
        writeOctal(Int64(size), into: &block, at: 124, width: 11)
        writeOctal(mtime, into: &block, at: 136, width: 11)
        for i in 148..<156 { block[i] = 0x20 }   // checksum 先填空格
        block[156] = typeflag
        write("ustar\0" + "00", into: &block, at: 257, max: 8)
        write(prefix, into: &block, at: 345, max: 155)

        let sum = block.reduce(Int64(0)) { $0 + Int64($1) }
        let checksum = String(sum, radix: 8)
        let padded = String(repeating: "0", count: max(0, 6 - checksum.count)) + checksum + "\0 "
        write(padded, into: &block, at: 148, max: 8)
        return Data(block)
    }

    static func dataBlock(_ data: Data) -> Data {
        var out = data
        let remainder = out.count % 512
        if remainder != 0 { out.append(Data(count: 512 - remainder)) }
        return out
    }

    private static func write(_ string: String, into block: inout [UInt8], at offset: Int, max: Int) {
        let bytes = Array(string.utf8.prefix(max))
        block.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }

    private static func writeOctal(_ value: Int64, into block: inout [UInt8], at offset: Int, width: Int) {
        let digits = String(value, radix: 8)
        let padded = String(repeating: "0", count: max(0, width - digits.count)) + digits + "\0"
        write(padded, into: &block, at: offset, max: width + 1)
    }

    #if canImport(zlib)
    /// gzip 压缩（windowBits = 31，带 gzip 头）。
    static func gzip(_ data: Data) -> Data {
        var stream = z_stream()
        deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8,
                      Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        defer { deflateEnd(&stream) }
        var out = Data()
        var chunk = [UInt8](repeating: 0, count: 64 << 10)
        data.withUnsafeBytes { inPtr in
            stream.next_in = UnsafeMutablePointer(mutating: inPtr.baseAddress!.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(data.count)
            repeat {
                let produced = chunk.withUnsafeMutableBytes { outPtr -> Int in
                    stream.next_out = outPtr.baseAddress!.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(outPtr.count)
                    deflate(&stream, Z_FINISH)
                    return outPtr.count - Int(stream.avail_out)
                }
                out.append(contentsOf: chunk[0..<produced])
            } while stream.avail_out == 0
        }
        return out
    }
    #endif
}
