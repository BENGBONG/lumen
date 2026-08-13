import XCTest
import FileSystemKit
@testable import TransferEngine

final class TransferQueueUndoTests: XCTestCase {
    var tempDir: URL!
    var provider: LocalFileProvider!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("transfer-undo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        provider = LocalFileProvider()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func path(_ url: URL) -> ProviderPath { provider.providerPath(for: url) }

    private func makeFile(_ name: String, _ contents: String = "x") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    private func waitForTerminal(_ queue: TransferQueue, count: Int) async {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let batch = queue.tasks.suffix(count)
            if batch.count == count && batch.allSatisfy({
                switch $0.status {
                case .completed, .failed, .cancelled, .skipped: return true
                default: return false
                }
            }) { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - 复制撤回

    @MainActor
    func testUndoCopyBatchTrashesAllCopies() async throws {
        let queue = TransferQueue(provider: provider)
        let srcA = makeFile("a.txt", "aaa")
        let srcB = makeFile("b.txt", "bbb")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        queue.enqueue([
            TransferTask(kind: .copy, source: path(srcA), destination: path(destDir.appendingPathComponent("a.txt"))),
            TransferTask(kind: .copy, source: path(srcB), destination: path(destDir.appendingPathComponent("b.txt"))),
        ])
        await waitForTerminal(queue, count: 2)

        XCTAssertTrue(queue.canUndo)
        XCTAssertEqual(queue.undoLabel, "复制 2 个项目到 dest")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("a.txt").path))

        let result = await queue.undoLast()
        XCTAssertEqual(result?.label, "复制 2 个项目到 dest")
        XCTAssertFalse(queue.canUndo)
        // 两个副本都被送入废纸篓，源文件不受影响
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("a.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("b.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: srcA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: srcB.path))
    }

    // MARK: - 移动撤回

    @MainActor
    func testUndoMovePutsBack() async throws {
        let queue = TransferQueue(provider: provider)
        let src = makeFile("m.txt", "move-me")
        let destDir = tempDir.appendingPathComponent("dest2")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dst = destDir.appendingPathComponent("m.txt")

        queue.enqueue(TransferTask(kind: .move, source: path(src), destination: path(dst)))
        await waitForTerminal(queue, count: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.path))

        let result = await queue.undoLast()
        XCTAssertEqual(result?.label, "移动 m.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst.path))
        XCTAssertEqual(try String(contentsOf: src, encoding: .utf8), "move-me")
    }

    // MARK: - 失败任务不进撤回栈

    @MainActor
    func testFailedTaskNotUndoable() async {
        let queue = TransferQueue(provider: provider)
        let bogus = ProviderPath(providerID: "local", components: ["nope-\(UUID().uuidString)"])
        let dst = path(tempDir.appendingPathComponent("x.txt"))
        queue.enqueue(TransferTask(kind: .copy, source: bogus, destination: dst))
        await waitForTerminal(queue, count: 1)
        XCTAssertFalse(queue.canUndo)
        let result = await queue.undoLast()
        XCTAssertNil(result)
    }

    // MARK: - 冲突重命名后撤回的是实际产物

    @MainActor
    func testUndoAfterConflictRenameTrashesRenamedCopy() async throws {
        let queue = TransferQueue(provider: provider)  // 默认 AutoRenameResolver
        let dst = makeFile("same.txt", "old")
        let srcDir = tempDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let src = srcDir.appendingPathComponent("same.txt")
        try "new".write(to: src, atomically: true, encoding: .utf8)

        queue.enqueue(TransferTask(kind: .copy, source: path(src), destination: path(dst)))
        await waitForTerminal(queue, count: 1)

        // 冲突自动重命名为「same (副本).txt」
        let copyURL = tempDir.appendingPathComponent("same (副本).txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyURL.path))

        _ = await queue.undoLast()
        XCTAssertFalse(FileManager.default.fileExists(atPath: copyURL.path))
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "old")  // 原文件不动
    }
}
