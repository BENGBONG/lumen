import AppKit
import FileSystemKit
import TransferEngine

/// 传输冲突时弹系统对话框让用户决策：保留两者 / 覆盖 / 跳过 / 停止。
/// 勾选「应用到所有冲突」后记住选择，后续同批冲突不再询问。
@MainActor
final class UserConflictResolver: ConflictResolver {

    private var remembered: ConflictResolution?

    func resolve(source: FileItem, destination: FileItem) async -> ConflictResolution {
        if let remembered {
            // 「保留两者」需要按每个文件重新生成重名
            if case .rename = remembered {
                return .rename(newName: Self.autoCopyName(for: source.name))
            }
            return remembered
        }

        let alert = NSAlert()
        alert.messageText = "目标位置已存在同名\(destination.isDirectory ? "文件夹" : "文件")"
        alert.informativeText = infoText(source: source, destination: destination)
        alert.alertStyle = .warning
        // 第一个按钮是默认项（回车触发）——给最安全的「保留两者」
        alert.addButton(withTitle: "保留两者")
        alert.addButton(withTitle: destination.isDirectory ? "替换" : "覆盖")
        alert.addButton(withTitle: "跳过")
        alert.addButton(withTitle: "停止")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "应用到所有冲突"

        let response = alert.runModal()
        let resolution: ConflictResolution
        switch response {
        case .alertFirstButtonReturn:
            resolution = .rename(newName: Self.autoCopyName(for: source.name))
        case .alertSecondButtonReturn:
            resolution = .overwrite
        case .alertThirdButtonReturn:
            resolution = .skip
        default:
            resolution = .cancel
        }

        if alert.suppressionButton?.state == .on {
            remembered = resolution
        }
        return resolution
    }

    /// 与 AutoRenameResolver 一致的「xxx (副本).ext」命名。
    static func autoCopyName(for name: String) -> String {
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        let newStem = "\(stem) (副本)"
        return ext.isEmpty ? newStem : "\(newStem).\(ext)"
    }

    private func infoText(source: FileItem, destination: FileItem) -> String {
        let srcDesc = describe(source)
        let dstDesc = describe(destination)
        return """
        正在\(source.isDirectory ? "拷贝文件夹" : "拷贝")「\(source.name)」：
        来源：\(srcDesc)
        目标：\(dstDesc)
        """
    }

    private func describe(_ item: FileItem) -> String {
        var parts: [String] = []
        if !item.isDirectory, item.size >= 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
        }
        if let modified = item.modifiedAt {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            parts.append("修改于 \(fmt.string(from: modified))")
        }
        let detail = parts.isEmpty ? "" : "（\(parts.joined(separator: "，"))）"
        return "\(item.url.path)\(detail)"
    }
}
