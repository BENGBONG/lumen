import SwiftUI
import AppearanceKit
import FileSystemKit

struct StatusBarView: View {
    @Bindable var vm: PaneViewModel
    @Environment(\.appearanceTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            // 归档浏览时给出明确的只读提示
            if (vm.provider as? RoutedFileProvider)?.isInsideArchive(vm.currentPath) == true {
                Label("归档 · 只读", systemImage: "archivebox")
                    .foregroundStyle(theme.accent.opacity(0.9))
                bullet
            } else if let git = vm.gitInfo {
                gitBadge(git)
                bullet
            }
            countLabel
            if !vm.selection.isEmpty {
                bullet
                Text("已选 \(vm.selection.count)")
                    .monospacedDigit()
                bullet
                Text(formatSelectedSize())
                    .monospacedDigit()
            }
            if !vm.searchQuery.isEmpty {
                bullet
                Label("搜索：\(vm.searchQuery)", systemImage: "magnifyingglass")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if vm.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            }
            if let err = vm.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: theme.captionFontSize))
        .foregroundStyle(theme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(height: 22)
        .glassChrome(theme)
    }

    private var countLabel: some View {
        let parts: [String] = {
            var out: [String] = []
            if vm.dirCount > 0 { out.append("\(vm.dirCount) 个文件夹") }
            if vm.fileCount > 0 { out.append("\(vm.fileCount) 个文件") }
            if out.isEmpty { return ["空目录"] }
            return out
        }()
        return Text(parts.joined(separator: " · "))
            .monospacedDigit()
    }

    private var bullet: some View {
        Text("·").foregroundStyle(theme.secondaryText.opacity(0.5))
    }

    /// git 分支徽标：显示当前分支 + dirty 指示点，点击弹出本地分支列表切换。
    @ViewBuilder
    private func gitBadge(_ git: GitRepoInfo) -> some View {
        Menu {
            if git.branches.isEmpty {
                // 空仓库 / unborn 分支：无可切项，仅展示
                Text("暂无本地分支")
            } else {
                ForEach(git.branches, id: \.self) { branch in
                    Button {
                        Task { await GitBranchSwitcher.switchBranch(vm: vm, to: branch) }
                    } label: {
                        if branch == git.branch {
                            Label(branch, systemImage: "checkmark")
                        } else {
                            Text(branch)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: git.isDetached ? "arrow.triangle.branch.circle" : "arrow.triangle.branch")
                Text(git.branch)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if git.isDirty {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 5, height: 5)
                        .help("有未提交的改动")
                }
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(theme.secondaryText)
        .help(git.isDetached ? "detached HEAD · 点击切换分支" : "git 仓库 · 点击切换分支")
    }

    private func formatSelectedSize() -> String {
        let total = vm.items
            .filter { vm.selection.contains($0.id) }
            .reduce(Int64(0)) { $0 + max(0, $1.size) }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
