import SwiftUI
import AppearanceKit
import AIKit
import FileSystemKit

struct PaneToolbarView: View {
    @Bindable var vm: PaneViewModel
    let isActive: Bool
    @Environment(\.appearanceTheme) private var theme

    @State private var localQuery:  String = ""
    @State private var isAISearch:  Bool   = false
    @State private var isSearching: Bool   = false   // AI search in-progress
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Nav buttons
            Button { Task { await vm.goBack() } } label: {
                Image(systemName: "chevron.left").opacity(vm.canGoBack ? 1 : 0.3)
            }
            .disabled(!vm.canGoBack).buttonStyle(.borderless).help("后退")

            Button { Task { await vm.goForward() } } label: {
                Image(systemName: "chevron.right").opacity(vm.canGoForward ? 1 : 0.3)
            }
            .disabled(!vm.canGoForward).buttonStyle(.borderless).help("前进")

            Button { Task { await vm.goUp() } } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless).help("上级目录")

            Button { Task { await vm.reload() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless).help("刷新")

            Toggle(isOn: Binding(
                get: { vm.includeHidden },
                set: { _ in Task { await vm.toggleHidden() } }
            )) {
                Image(systemName: "eye")
            }
            .toggleStyle(.button).buttonStyle(.borderless).help("显示隐藏文件")

            // Search bar
            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: theme.captionFontSize))
                    .foregroundStyle(theme.secondaryText)

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                }

                TextField(
                    isAISearch ? "用自然语言描述，按回车搜索…" : "搜索当前目录",
                    text: $localQuery
                )
                .textFieldStyle(.plain)
                .font(.system(size: theme.captionFontSize))
                .focused($searchFocused)
                .onChange(of: localQuery) { _, new in
                    if !isAISearch { vm.setSearch(new) }
                }
                .onSubmit {
                    if isAISearch { runAISearch() } else { searchFocused = false }
                }

                if !localQuery.isEmpty {
                    Button {
                        localQuery = ""
                        vm.setSearch("")
                        isSearching = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.rowHover))
            .frame(maxWidth: .infinity)

            // AI search toggle button — clearly separate from the search field
            Button {
                isAISearch.toggle()
                localQuery = ""
                vm.setSearch("")
                if isAISearch { searchFocused = true }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: theme.captionFontSize, weight: .medium))
                    Text("AI")
                        .font(.system(size: theme.captionFontSize, weight: .semibold))
                }
                .foregroundStyle(isAISearch ? .white : theme.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isAISearch ? theme.accent : theme.rowHover)
                )
            }
            .buttonStyle(.plain)
            .help(isAISearch ? "关闭 AI 搜索（回到普通搜索）" : "开启 AI 自然语言搜索")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(theme.sidebarBackground)
        .background(isActive ? theme.accent.opacity(0.07) : Color.clear)
        .onAppear { localQuery = vm.searchQuery }
        .onChange(of: vm.id) { _, _ in
            localQuery  = vm.searchQuery
            isAISearch  = false
            isSearching = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .flFocusSearch)) { _ in
            if isActive { searchFocused = true }
        }
    }

    // MARK: - AI Search

    private func runAISearch() {
        guard !localQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let client = AIClient.fromCurrentSettings() else {
            // Fall back to plain search if no AI key configured
            vm.setSearch(localQuery)
            return
        }

        isSearching = true
        let query   = localQuery
        let items   = vm.items   // snapshot current file list

        Task {
            do {
                // Build a compact file list to send: name + type + size
                let fileList = items.map { item -> String in
                    let type = item.isDirectory ? "[文件夹]" : "[文件]"
                    let size = item.isDirectory ? "" : " (\(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)))"
                    return "\(type) \(item.name)\(size)"
                }.joined(separator: "\n")

                let prompt = """
                    用户在文件管理器里输入了以下搜索词：
                    "\(query)"

                    当前目录中的文件列表如下（每行一个）：
                    \(fileList)

                    请从上面的文件列表中，找出所有与用户搜索意图相关的文件。
                    只返回一个 JSON 数组，包含匹配的文件名（完整名称，区分大小写）。
                    格式例子：["文件A.pdf", "文件B.xlsx"]
                    如果没有匹配项，返回空数组：[]
                    不要包含任何解释文字，只返回 JSON 数组。
                    """

                let reply = try await client.chat(
                    messages: [ClaudeMessage(role: .user, text: prompt)],
                    maxTokens: 512
                )

                // Parse JSON array of matched filenames
                let matched = parseJSONStringArray(reply)
                await MainActor.run {
                    isSearching = false
                    if matched.isEmpty {
                        vm.setSearch("__NO_AI_MATCH__")  // show empty
                    } else {
                        // Use a special filter: match any file in the matched set
                        vm.setAISearchResults(matched)
                    }
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    // Fall back to plain text search on error
                    vm.setSearch(query)
                }
            }
        }
    }

    private func parseJSONStringArray(_ text: String) -> Set<String> {
        // Find the first [...] block in the response
        guard let start = text.firstIndex(of: "["),
              let end   = text.lastIndex(of: "]") else { return [] }
        let json = String(text[start...end])
        guard let data  = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(array)
    }
}
