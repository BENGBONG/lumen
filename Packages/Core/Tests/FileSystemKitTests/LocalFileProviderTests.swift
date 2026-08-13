import XCTest
@testable import FileSystemKit

final class LocalFileProviderTests: XCTestCase {
    var tempDir: URL!
    var provider: LocalFileProvider!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("forklift-clone-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        provider = LocalFileProvider()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testListEmptyDirectory() async throws {
        let path = provider.providerPath(for: tempDir)
        let items = try await provider.list(path, includeHidden: false)
        XCTAssertEqual(items.count, 0)
    }

    func testListSeesNewFile() async throws {
        let file = tempDir.appendingPathComponent("hello.txt")
        try "hi".write(to: file, atomically: true, encoding: .utf8)
        let path = provider.providerPath(for: tempDir)
        let items = try await provider.list(path, includeHidden: false)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "hello.txt")
        XCTAssertEqual(items.first?.isDirectory, false)
        XCTAssertEqual(items.first?.size, 2)
    }

    func testListSkipsHiddenByDefault() async throws {
        try "x".write(to: tempDir.appendingPathComponent("visible.txt"),
                       atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appendingPathComponent(".hidden"),
                       atomically: true, encoding: .utf8)
        let path = provider.providerPath(for: tempDir)
        let visible = try await provider.list(path, includeHidden: false)
        XCTAssertEqual(visible.map(\.name), ["visible.txt"])
        let all = try await provider.list(path, includeHidden: true)
        XCTAssertEqual(Set(all.map(\.name)), Set(["visible.txt", ".hidden"]))
    }

    func testMkdir() async throws {
        let target = tempDir.appendingPathComponent("subdir")
        try await provider.mkdir(provider.providerPath(for: target))
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testRename() async throws {
        let file = tempDir.appendingPathComponent("a.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        try await provider.rename(provider.providerPath(for: file), to: "b.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("b.txt").path))
    }

    func testCopyAndMove() async throws {
        let src = tempDir.appendingPathComponent("src.txt")
        try "data".write(to: src, atomically: true, encoding: .utf8)
        let copyDst = tempDir.appendingPathComponent("copy.txt")
        let moveDst = tempDir.appendingPathComponent("moved.txt")

        try await provider.copy(
            provider.providerPath(for: src),
            to: provider.providerPath(for: copyDst),
            progress: nil
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyDst.path))

        try await provider.move(
            provider.providerPath(for: src),
            to: provider.providerPath(for: moveDst)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moveDst.path))
    }

    func testProviderPathRoundTrip() {
        let original = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
        let path = provider.providerPath(for: original)
        XCTAssertEqual(provider.url(for: path).standardizedFileURL,
                       original.standardizedFileURL)
    }

    func testProviderPathParentAndAppend() {
        let home = NSHomeDirectory()
        let comps = home.split(separator: "/").map(String.init)
        let p = ProviderPath(providerID: "local", components: comps)
        XCTAssertEqual(p.appending("Documents").components, comps + ["Documents"])
        XCTAssertEqual(p.parent()?.components, Array(comps.dropLast()))
        XCTAssertNil(ProviderPath(providerID: "local", components: []).parent())
    }
}
