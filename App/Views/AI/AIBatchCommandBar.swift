import SwiftUI
import AppearanceKit
import AIKit
import FileSystemKit

/// A floating command bar that lets the user describe a batch operation in
/// natural language.  AI returns a structured plan; the user previews and
/// confirms before anything is executed.
struct AIBatchCommandBar: View {
    @Binding var isPresented: Bool
    let items: [FileItem]
    let currentPath: ProviderPath
    let provider: any FileProvider
    let onReload: () -> Void

    @Environment(\.appearanceTheme) private var theme
    @State private var command   = ""
    @State private var isLoading = false
    @State private var plan: BatchPlan?
    @State private var errorText: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Command input
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.accent)
                    .font(.system(size: 14))

                TextField("描述你想做什么，例如：用拍摄日期重命名这些图片", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(size: theme.bodyFontSize))
                    .focused($focused)
                    .onSubmit { generate() }

                if isLoading {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button("生成方案", action: generate)
                        .buttonStyle(.borderedProminent)
                        .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
                        .controlSize(.small)
                }

                Button {
                    withAnimation { isPresented = false }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(theme.sidebarBackground)

            if let err = errorText {
                Divider()
                Text(err)
                    .font(.system(size: theme.captionFontSize))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }

            if let plan {
                Divider()
                planPreview(plan)
            }
        }
        .background(theme.paneBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 4)
        .onAppear { focused = true }
    }

    // MARK: - Plan preview

    @ViewBuilder
    private func planPreview(_ plan: BatchPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(plan.description)
                    .font(.system(size: theme.captionFontSize, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("\(plan.operations.count) 个操作")
                    .font(.system(size: theme.captionFontSize))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(plan.operations.indices, id: \.self) { i in
                        OperationRow(op: plan.operations[i], theme: theme)
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .frame(maxHeight: 220)

            Divider()

            HStack(spacing: 8) {
                Spacer()
                Button("取消") {
                    self.plan = nil
                    command   = ""
                }
                .keyboardShortcut(.cancelAction)

                Button("执行全部") { execute(plan) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - AI generation

    private func generate() {
        let cmd = command.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        guard let client = AIClient.fromCurrentSettings() else {
            errorText = "请先在设置中配置 AI Key"
            return
        }

        isLoading = true
        errorText = nil
        plan      = nil

        let fileList = items.prefix(200).map { item -> String in
            let t = item.isDirectory ? "dir" : "file"
            return "\(t): \(item.name)"
        }.joined(separator: "\n")

        let prompt = """
            用户对文件管理器中的文件执行批量操作，指令如下：
            "\(cmd)"

            当前目录文件列表（最多200条）：
            \(fileList)

            请返回一个 JSON 对象，格式如下，不要包含任何其他文字：
            {
              "description": "简短描述这次操作",
              "operations": [
                {"type": "rename", "source": "原文件名", "destination": "新文件名"},
                {"type": "delete", "source": "文件名"}
              ]
            }

            规则：
            - type 只能是 "rename" 或 "delete"
            - source 和 destination 只能是文件名，不能包含路径
            - destination 不需要路径，只要新文件名
            - 如果无法理解指令或无法操作，返回 {"description": "无法执行", "operations": []}
            - 最多返回 50 个操作
            """

        Task {
            do {
                let reply = try await client.chat(
                    messages: [ClaudeMessage(role: .user, text: prompt)],
                    maxTokens: 2048
                )
                let parsed = parsePlan(reply)
                await MainActor.run {
                    isLoading = false
                    if parsed.operations.isEmpty {
                        errorText = "AI 无法生成操作方案，请换一种描述方式"
                    } else {
                        plan = parsed
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorText = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Execution

    private func execute(_ plan: BatchPlan) {
        withAnimation { isPresented = false }
        Task {
            for op in plan.operations {
                switch op.type {
                case "rename":
                    guard let dest = op.destination, !dest.isEmpty else { continue }
                    let src = currentPath.appending(op.source)
                    try? await provider.rename(src, to: dest)
                case "delete":
                    let src = currentPath.appending(op.source)
                    try? await provider.delete(src, toTrash: true)
                default:
                    break
                }
            }
            await MainActor.run { onReload() }
        }
    }

    // MARK: - JSON parsing

    private func parsePlan(_ text: String) -> BatchPlan {
        // Find the outermost { } block
        guard let start = text.firstIndex(of: "{"),
              let end   = text.lastIndex(of: "}") else {
            return BatchPlan(description: "", operations: [])
        }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let plan = try? JSONDecoder().decode(BatchPlan.self, from: data) else {
            return BatchPlan(description: "", operations: [])
        }
        return plan
    }
}

// MARK: - Data models

struct BatchPlan: Decodable {
    let description: String
    let operations: [BatchOperation]
}

struct BatchOperation: Decodable {
    let type: String
    let source: String
    let destination: String?
}

// MARK: - Operation row

private struct OperationRow: View {
    let op: BatchOperation
    let theme: any AppearanceTheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: op.type == "rename" ? "pencil" : "trash")
                .font(.system(size: 11))
                .foregroundStyle(op.type == "delete" ? .red : theme.accent)
                .frame(width: 16)

            if op.type == "rename", let dest = op.destination {
                Text(op.source)
                    .font(.system(size: theme.captionFontSize, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondaryText)
                Text(dest)
                    .font(.system(size: theme.captionFontSize, design: .monospaced))
                    .foregroundStyle(theme.primaryText)
            } else {
                Text(op.source)
                    .font(.system(size: theme.captionFontSize, design: .monospaced))
                    .foregroundStyle(op.type == "delete" ? .red : theme.primaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
