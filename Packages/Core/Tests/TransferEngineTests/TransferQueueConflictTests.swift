import XCTest
import FileSystemKit
@testable import TransferEngine

/// 脚本化 resolver：返回固定决策，记录被调用次数。
final class ScriptedResolver: ConflictResolver, @unchecked Sendable {
    var resolution: ConflictResolution
    private(set) var callCount = 0

    init(_ resolution: ConflictResolution) {
        self.resolution = resolution
    }

    func resolve(source: FileItem, destination: FileItem) async -> ConflictResolution {
        callCount += 1
        // rename 场景模仿 UI resolver 的行为：返回「副本」名
        if case .rename = resolution {
            let ext = (source.name as NSString).pathExtension
            let stem = (source.name as NSString).deletingPathExtension
            let newStem = "\(stem) (副本)"
            return .rename(newName: ext.isEmpty ? newStem : "\(newStem).\(ext)")
        }
        return resolution
    }
}

final class TransferQueueConflictTests: XCTestCase {
    var tempDir: URL!
    var provider: LocalFileProvider!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("forklift-clone-conflict-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        provider = LocalFileProvider()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func makeFile(_ name: String, contents: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    private func runTask(_ queue: TransferQueue, kind: TransferKind = .copy,
                         src: URL, dst: URL) async -> TransferTask {
        let task = TransferTask(kind: kind,
                                source: provider.providerPath(for: src),
                                destination: provider.providerPath(for: dst))
        queue.enqueue(task)
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            let status = queue.tasks.first?.status
            if let status, status != .pending {
                if case .running = status {} else { break }
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return queue.tasks.first!
    }

    // MARK: - Tests

    @MainActor
    func testNoConflictDoesNotInvokeResolver() async throws {
        let resolver = ScriptedResolver(.skip)
        let queue = TransferQueue(provider: provider, resolver: resolver)
        let src = makeFile("src.txt", contents: "hello")
        let dst = tempDir.appendingPathComponent("dst.txt")

        let task = await runTask(queue, src: src, dst: dst)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(resolver.callCount, 0)
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "hello")
    }

    @MainActor
    func testConflictSkipKeepsDestinationAndMarksSkipped() async throws {
        let resolver = ScriptedResolver(.skip)
        let queue = TransferQueue(provider: provider, resolver: resolver)
        let src = makeFile("new.txt", contents: "new-content")
        let dst = makeFile("same.txt", contents: "old-content")
        // 让源与目标同名冲突：把 src 改名后与 dst 同名
        let srcSame = tempDir.appendingPathComponent("sub/same.txt")
        try FileManager.default.createDirectory(at: srcSame.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: src, to: srcSame)

        let task = await runTask(queue, src: srcSame, dst: dst)
        XCTAssertEqual(task.status, .skipped)
        XCTAssertEqual(resolver.callCount, 1)
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "old-content")
    }

    @MainActor
    func testConflictOverwriteReplacesDestination() async throws {
        let resolver = ScriptedResolver(.overwrite)
        let queue = TransferQueue(provider: provider, resolver: resolver)
        let srcSame = tempDir.appendingPathComponent("sub/same.txt")
        try FileManager.default.createDirectory(at: srcSame.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "new-content".write(to: srcSame, atomically: true, encoding: .utf8)
        let dst = makeFile("same.txt", contents: "old-content")

        let task = await runTask(queue, src: srcSame, dst: dst)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "new-content")
    }

    @MainActor
    func testConflictRenameKeepsBoth() async throws {
        let resolver = ScriptedResolver(.rename(newName: ""))  // 具体名字由 resolver 生成
        let queue = TransferQueue(provider: provider, resolver: resolver)
        let srcSame = tempDir.appendingPathComponent("sub/same.txt")
        try FileManager.default.createDirectory(at: srcSame.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "new-content".write(to: srcSame, atomically: true, encoding: .utf8)
        let dst = makeFile("same.txt", contents: "old-content")

        let task = await runTask(queue, src: srcSame, dst: dst)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "old-content")
        let copy = tempDir.appendingPathComponent("same (副本).txt")
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "new-content")
        XCTAssertEqual(task.destination.components.last, "same (副本).txt")
    }

    @MainActor
    func testConflictRenameNumberingWhenCopyExists() async throws {
        let resolver = ScriptedResolver(.rename(newName: ""))
        let queue = TransferQueue(provider: provider, resolver: resolver)
        let srcSame = tempDir.appendingPathComponent("sub/same.txt")
        try FileManager.default.createDirectory(at: srcSame.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "new-content".write(to: srcSame, atomically: true, encoding: .utf8)
        _ = makeFile("same.txt", contents: "old-content")
        _ = makeFile("same (副本).txt", contents: "existing-copy")

        let task = await runTask(queue, src: srcSame, dst: tempDir.appendingPathComponent("same.txt"))
        XCTAssertEqual(task.status, .completed)
        let numbered = tempDir.appendingPathComponent("same (副本) 2.txt")
        XCTAssertEqual(try String(contentsOf: numbered, encoding: .utf8), "new-content")
    }

    @MainActor
    func testConflictCancelMarksCancelled() async throws {
        let resolver = ScriptedResolver(.cancel)
        let queue = TransferQueue(provider: provider, resolver: resolver)
        let srcSame = tempDir.appendingPathComponent("sub/same.txt")
        try FileManager.default.createDirectory(at: srcSame.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "new-content".write(to: srcSame, atomically: true, encoding: .utf8)
        let dst = makeFile("same.txt", contents: "old-content")

        let task = await runTask(queue, src: srcSame, dst: dst)
        XCTAssertEqual(task.status, .cancelled)
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "old-content")
    }

    @MainActor
    func testMoveConflictOverwriteReplacesAndRemovesSource() async throws {
        let resolver = ScriptedResolver(.overwrite)
        let queue = TransferQueue(provider: provider, resolver: resolver)
        let srcSame = tempDir.appendingPathComponent("sub/same.txt")
        try FileManager.default.createDirectory(at: srcSame.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "new-content".write(to: srcSame, atomically: true, encoding: .utf8)
        let dst = makeFile("same.txt", contents: "old-content")

        let task = await runTask(queue, kind: .move, src: srcSame, dst: dst)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "new-content")
        XCTAssertFalse(FileManager.default.fileExists(atPath: srcSame.path))
    }
}
