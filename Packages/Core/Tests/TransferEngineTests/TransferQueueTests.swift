import XCTest
import FileSystemKit
@testable import TransferEngine

final class TransferQueueTests: XCTestCase {
    var tempDir: URL!
    var provider: LocalFileProvider!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("forklift-clone-queue-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        provider = LocalFileProvider()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func testCopyTaskCompletesAndClearable() async throws {
        let src = tempDir.appendingPathComponent("src.txt")
        try "hi".write(to: src, atomically: true, encoding: .utf8)
        let dst = tempDir.appendingPathComponent("dst.txt")

        let queue = TransferQueue(provider: provider)
        let task = TransferTask(
            kind: .copy,
            source: provider.providerPath(for: src),
            destination: provider.providerPath(for: dst)
        )
        queue.enqueue(task)

        // Spin until task finishes
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if case .completed = queue.tasks.first?.status { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(queue.tasks.first?.status, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.path))

        queue.clearCompleted()
        XCTAssertTrue(queue.tasks.isEmpty)
    }

    @MainActor
    func testFailedTaskMarkedFailed() async throws {
        let queue = TransferQueue(provider: provider)
        let bogus = ProviderPath(providerID: "local", components: ["nope-\(UUID().uuidString)"])
        let dst = ProviderPath(providerID: "local", components: ["tmp", "x"])
        queue.enqueue(TransferTask(kind: .copy, source: bogus, destination: dst))

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if case .failed = queue.tasks.first?.status { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard case .failed = queue.tasks.first?.status else {
            XCTFail("expected failure, got \(String(describing: queue.tasks.first?.status))")
            return
        }
    }
}
