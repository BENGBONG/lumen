import XCTest
@testable import FileSystemKit

/// GitRepositoryService 单测：在系统临时目录里用真实 /usr/bin/git 建仓库交叉验证。
final class GitRepositoryServiceTests: XCTestCase {

    private var repoDir: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lumen-git-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        repoDir = base
        try runTool("/usr/bin/git", ["init", "-b", "main"], in: base)
        try runTool("/usr/bin/git", ["config", "user.email", "test@lumen.local"], in: base)
        try runTool("/usr/bin/git", ["config", "user.name", "Lumen Test"], in: base)
        try "hello\n".write(to: base.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runTool("/usr/bin/git", ["add", "."], in: base)
        try runTool("/usr/bin/git", ["commit", "-m", "init"], in: base)
    }

    override func tearDownWithError() throws {
        if let repoDir { try? FileManager.default.removeItem(at: repoDir) }
    }

    func testProbeNonGitDirectoryReturnsNil() async {
        // 必须放在仓库外面——仓库内的任何子目录向上查找都会命中 .git
        let plain = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lumen-git-tests-plain-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plain) }
        let info = await GitRepositoryService.probe(directory: plain.path)
        XCTAssertNil(info)
    }

    func testProbeFindsRepoFromSubdirectory() async throws {
        let nested = repoDir.appendingPathComponent("deep/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let info = await GitRepositoryService.probe(directory: nested.path)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.rootPath, repoDir.path)
        XCTAssertEqual(info?.branch, "main")
        XCTAssertEqual(info?.isDetached, false)
        XCTAssertEqual(info?.branches, ["main"])
    }

    func testCleanVsDirty() async throws {
        let clean = await GitRepositoryService.probe(directory: repoDir.path)
        XCTAssertEqual(clean?.isDirty, false)

        try "more\n".write(to: repoDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let dirty = await GitRepositoryService.probe(directory: repoDir.path)
        XCTAssertEqual(dirty?.isDirty, true)
    }

    func testBranchListAndCheckoutRoundtrip() async throws {
        try runTool("/usr/bin/git", ["branch", "feature-x"], in: repoDir)
        try runTool("/usr/bin/git", ["branch", "feature-a"], in: repoDir)

        let before = await GitRepositoryService.probe(directory: repoDir.path)
        XCTAssertEqual(before?.branches, ["feature-a", "feature-x", "main"])

        try await GitRepositoryService.checkout(rootPath: repoDir.path, branch: "feature-x")
        let after = await GitRepositoryService.probe(directory: repoDir.path)
        XCTAssertEqual(after?.branch, "feature-x")

        // 切回 main
        try await GitRepositoryService.checkout(rootPath: repoDir.path, branch: "main")
        let back = await GitRepositoryService.probe(directory: repoDir.path)
        XCTAssertEqual(back?.branch, "main")
    }

    func testCheckoutConflictThrowsWithStderr() async throws {
        try runTool("/usr/bin/git", ["checkout", "-b", "other"], in: repoDir)
        // 两边各自改同一文件制造不可携带的冲突
        try "main version\n".write(to: repoDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runTool("/usr/bin/git", ["add", "."], in: repoDir)
        try runTool("/usr/bin/git", ["commit", "-m", "change on other"], in: repoDir)
        try runTool("/usr/bin/git", ["checkout", "main"], in: repoDir)
        try "main version 2\n".write(to: repoDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runTool("/usr/bin/git", ["add", "."], in: repoDir)
        try runTool("/usr/bin/git", ["commit", "-m", "change on main"], in: repoDir)

        // 未提交改动与目标分支冲突 → 抛错且带可读信息
        try "dirty conflicting\n".write(to: repoDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        do {
            try await GitRepositoryService.checkout(rootPath: repoDir.path, branch: "other")
            XCTFail("应当抛出冲突错误")
        } catch let error as GitRepositoryError {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertTrue(error.errorDescription?.isEmpty == false)
        }
    }

    func testDetachedHead() async throws {
        let sha = try runTool("/usr/bin/git", ["rev-parse", "HEAD"], in: repoDir)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try runTool("/usr/bin/git", ["checkout", "--detach", "HEAD"], in: repoDir)
        let info = await GitRepositoryService.probe(directory: repoDir.path)
        XCTAssertEqual(info?.isDetached, true)
        XCTAssertTrue(sha.hasPrefix(info?.branch ?? ""))
    }

    func testEmptyRepoShowsUnbornBranchName() async throws {
        let empty = repoDir.appendingPathComponent("empty-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try runTool("/usr/bin/git", ["init", "-b", "main"], in: empty)
        let info = await GitRepositoryService.probe(directory: empty.path)
        XCTAssertNotNil(info)
        // unborn 分支：git --show-current 仍给出分支名，但分支列表为空
        XCTAssertEqual(info?.branch, "main")
        XCTAssertEqual(info?.branches, [])
    }

    // MARK: - Helpers

    private func runTool(_ path: String, _ args: [String], in dir: URL) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.currentDirectoryURL = dir
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(
                domain: "GitTestHelper", code: Int(p.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""]
            )
        }
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
