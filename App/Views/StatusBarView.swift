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

    private func formatSelectedSize() -> String {
        let total = vm.items
            .filter { vm.selection.contains($0.id) }
            .reduce(Int64(0)) { $0 + max(0, $1.size) }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
