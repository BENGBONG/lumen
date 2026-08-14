import AppKit
import FileSystemKit

/// 状态栏 git 分支切换流程：dirty 防护确认 → checkout → 刷新窗格。
/// 分支切换是低频高危操作（会改动工作区文件），与内联重命名不同，确认弹窗是必要的。
@MainActor
enum GitBranchSwitcher {

    static func switchBranch(vm: PaneViewModel, to branch: String) async {
        guard let info = vm.gitInfo, info.branch != branch else { return }

        // 数据安全底线：未提交改动时先确认（改动可能被带到新分支或导致切换失败）
        if info.isDirty {
            let alert = NSAlert()
            alert.messageText = "当前分支有未提交的改动"
            alert.informativeText =
                "切换到「\(branch)」时，未提交改动会被尝试带到新分支；\n"
                + "若与目标分支冲突，git 会拒绝切换（不会丢数据）。"
            alert.alertStyle = .warning
            // 默认项给取消——高危操作不回车误触
            alert.addButton(withTitle: "取消")
            alert.addButton(withTitle: "仍要切换")
            if alert.runModal() != .alertSecondButtonReturn { return }
        }

        do {
            try await GitRepositoryService.checkout(rootPath: info.rootPath, branch: branch)
            await vm.reload()
            await vm.refreshGitInfo()
        } catch {
            // checkout 被拒（冲突/权限等）：把 git 的原始 stderr 呈现给用户
            let alert = NSAlert()
            alert.messageText = "切换到「\(branch)」失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
            // 失败后状态也可能已变化（如 git 部分完成），刷新一次兜底
            await vm.refreshGitInfo()
        }
    }
}
