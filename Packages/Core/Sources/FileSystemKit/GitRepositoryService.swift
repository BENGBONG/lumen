import Foundation

/// 当前目录所属 git 仓库的快照信息。
public struct GitRepoInfo: Sendable, Equatable {
    /// 仓库根目录（.git 所在目录）的绝对路径。
    public let rootPath: String
    /// 当前分支短名；detached HEAD 时为短 SHA；空仓库时为占位文本。
    public let branch: String
    public let isDetached: Bool
    /// 工作区是否有未提交改动（含未跟踪文件）。
    public let isDirty: Bool
    /// 本地分支名列表（按 git 默认字母序，含当前分支）。
    public let branches: [String]

    public init(rootPath: String, branch: String, isDetached: Bool, isDirty: Bool, branches: [String]) {
        self.rootPath = rootPath
        self.branch = branch
        self.isDetached = isDetached
        self.isDirty = isDirty
        self.branches = branches
    }
}

public enum GitRepositoryError: LocalizedError {
    case gitFailed(String)

    public var errorDescription: String? {
        switch self {
        case .gitFailed(let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "git 命令执行失败" : trimmed
        }
    }
}

/// 本地 git 仓库探测与分支切换（基于 /usr/bin/git 子进程，不引入 libgit2）。
public enum GitRepositoryService {

    /// 从 `directory` 开始逐级向上查找 .git，找到则返回仓库信息，否则返回 nil。
    /// 任何 git 子命令失败都按"非仓库/不可用"优雅降级，不抛错。
    public static func probe(directory: String) async -> GitRepoInfo? {
        guard let root = findRepoRoot(from: directory) else { return nil }
        // 子进程操作移出调用者上下文（通常是 MainActor）。
        return await Task.detached(priority: .utility) {
            buildInfo(rootPath: root)
        }.value
    }

    /// 切换分支。git checkout 失败（如未提交改动冲突）时抛出携带 stderr 的错误。
    public static func checkout(rootPath: String, branch: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            _ = try runGit(["-C", rootPath, "checkout", branch])
        }.value
    }

    // MARK: - Internals

    private static func buildInfo(rootPath: String) -> GitRepoInfo? {
        // 1. 当前分支（unborn 分支如刚 init 的 main 也能读出名字）
        let showCurrent = try? runGit(["-C", rootPath, "branch", "--show-current"])
        let current = showCurrent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var branch = current
        var isDetached = false
        if branch.isEmpty {
            // detached HEAD → 短 SHA；再失败说明是空仓库（无任何提交）
            if let sha = try? runGit(["-C", rootPath, "rev-parse", "--short", "HEAD"]) {
                branch = sha.trimmingCharacters(in: .whitespacesAndNewlines)
                isDetached = true
            } else {
                branch = "(空仓库)"
            }
        }

        // 2. dirty（含未跟踪文件）
        let dirty: Bool
        if let status = try? runGit(["-C", rootPath, "status", "--porcelain"]) {
            dirty = !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            dirty = false
        }

        // 3. 本地分支列表
        let branches: [String]
        if let out = try? runGit(["-C", rootPath, "branch", "--format=%(refname:short)"]) {
            branches = out
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else {
            branches = []
        }

        return GitRepoInfo(
            rootPath: rootPath,
            branch: branch,
            isDetached: isDetached,
            isDirty: dirty,
            branches: branches
        )
    }

    /// 逐级向上找 .git（目录或 worktree/submodule 的 .git 文件都算），到根为止。
    private static func findRepoRoot(from directory: String) -> String? {
        let fm = FileManager.default
        var url = URL(fileURLWithPath: directory)
        // 防御：限制最多 64 级，避免符号链接构造的环
        for _ in 0..<64 {
            let gitURL = url.appendingPathComponent(".git")
            if fm.fileExists(atPath: gitURL.path) {
                return url.path
            }
            guard let parent = url.pathComponents.count > 1 ? url.deletingLastPathComponent() : nil,
                  parent.path != url.path else { return nil }
            url = parent
        }
        return nil
    }

    private static func runGit(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw GitRepositoryError.gitFailed("无法启动 git：\(error.localizedDescription)")
        }
        // 输出体量小（分支列表/状态），64KB pipe 缓冲足够，直接等待退出即可。
        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw GitRepositoryError.gitFailed(String(data: errData, encoding: .utf8) ?? "")
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }
}
