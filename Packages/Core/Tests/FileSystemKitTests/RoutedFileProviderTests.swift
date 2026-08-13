import XCTest
@testable import FileSystemKit

final class RoutedFileProviderTests: XCTestCase {
    var tempDir: URL!
    var provider: RoutedFileProvider!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("routed-provider-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        provider = RoutedFileProvider()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func path(_ url: URL) -> ProviderPath {
        provider.providerPath(for: url)
    }

    private func makeArchive() throws -> URL {
        let url = tempDir.appendingPathComponent("sample.zip")
        try StoredZipWriter.write(entries: [
            .init(name: "readme.md", data: Data("# 你好".utf8)),
            .init(name: "src/", data: Data()),
            .init(name: "src/main.py", data: Data("print(1)".utf8)),
            .init(name: "src/lib/util.py", data: Data("x = 1".utf8)),
        ]).write(to: url)
        return url
    }

    // MARK: - 本地路径透传

    func testLocalPathPassesThrough() async throws {
        let dir = tempDir.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "hi".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let items = try await provider.list(path(dir), includeHidden: false)
        XCTAssertEqual(items.map(\.name), ["a.txt"])
        XCTAssertFalse(provider.isInsideArchive(path(dir)))
    }

    // MARK: - 归档浏览

    func testListArchiveRoot() async throws {
        let zip = try makeArchive()
        let items = try await provider.list(path(zip), includeHidden: false)
        XCTAssertEqual(Set(items.map(\.name)), ["readme.md", "src"])
        XCTAssertEqual(items.first { $0.name == "src" }?.isDirectory, true)
        XCTAssertEqual(items.first { $0.name == "readme.md" }?.size, Int64("# 你好".utf8.count))
    }

    func testListArchiveSubdirectory() async throws {
        let zip = try makeArchive()
        let sub = path(zip).appending("src")
        let items = try await provider.list(sub, includeHidden: false)
        XCTAssertEqual(Set(items.map(\.name)), ["main.py", "lib"])
        XCTAssertTrue(provider.isInsideArchive(sub))
    }

    func testItemAtInnerPath() async throws {
        let zip = try makeArchive()
        let inner = path(zip).appending("src").appending("main.py")
        let item = await provider.item(at: inner)
        XCTAssertEqual(item?.name, "main.py")
        XCTAssertEqual(item?.isDirectory, false)
        XCTAssertEqual(item?.size, Int64("print(1)".utf8.count))
    }

    // MARK: - 拷出 / 只读保护

    func testCopyOutOfArchive() async throws {
        let zip = try makeArchive()
        let src = path(zip).appending("readme.md")
        let dst = path(tempDir).appending("out.md")
        try await provider.copy(src, to: dst, progress: nil)
        let content = try String(contentsOf: tempDir.appendingPathComponent("out.md"), encoding: .utf8)
        XCTAssertEqual(content, "# 你好")
    }

    func testCopyDirectoryOutOfArchive() async throws {
        let zip = try makeArchive()
        let src = path(zip).appending("src")
        let dst = path(tempDir).appending("src-copy")
        try await provider.copy(src, to: dst, progress: nil)
        let util = tempDir.appendingPathComponent("src-copy/lib/util.py")
        XCTAssertEqual(try String(contentsOf: util, encoding: .utf8), "x = 1")
    }

    func testWriteInsideArchiveRejected() async throws {
        let zip = try makeArchive()
        let inner = path(zip).appending("src")
        await XCTAssertThrowsErrorAsync(try await provider.mkdir(inner.appending("new"))) {
            XCTAssertEqual($0 as? RoutedProviderError, .archiveReadOnly)
        }
        await XCTAssertThrowsErrorAsync(
            try await provider.rename(inner.appending("main.py"), to: "x.py")
        ) {
            XCTAssertEqual($0 as? RoutedProviderError, .archiveReadOnly)
        }
        await XCTAssertThrowsErrorAsync(
            try await provider.delete(inner.appending("main.py"), toTrash: false)
        ) {
            XCTAssertEqual($0 as? RoutedProviderError, .archiveReadOnly)
        }
    }

    // MARK: - 归档文件本身仍是本地文件

    func testArchiveFileItselfIsLocal() async throws {
        let zip = try makeArchive()
        let zipPath = path(zip)
        XCTAssertFalse(provider.isInsideArchive(zipPath))
        // 重命名归档本身合法
        try await provider.rename(zipPath, to: "renamed.zip")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("renamed.zip").path))
    }

    // MARK: - url(for:) 提供可预览的真实文件

    func testURLOfInnerEntryPointsToExtractedFile() async throws {
        let zip = try makeArchive()
        _ = try await provider.list(path(zip), includeHidden: false)
        let inner = path(zip).appending("readme.md")
        let url = provider.url(for: inner)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# 你好")
    }
}

// MARK: - async 断言辅助

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected error", file: file, line: line)
    } catch {
        handler(error)
    }
}
