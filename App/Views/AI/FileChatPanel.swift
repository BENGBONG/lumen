import SwiftUI
import AppearanceKit
import AIKit
import FileSystemKit

struct FileChatPanel: View {
    @Binding var isPresented: Bool
    let contextFiles: [URL]

    @Environment(\.appearanceTheme) private var theme
    @State private var session    = ChatSession()
    @State private var inputText  = ""
    @State private var hasAPIKey  = KeychainStore.hasKey(for: .current)
    @FocusState private var inputFocused: Bool

    // Client built from currently-selected provider + Keychain key
    private var client: AIClient? { AIClient.fromCurrentSettings() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if contextFiles.isEmpty {
                noFileState
            } else if !hasAPIKey {
                noKeyState
            } else {
                chatArea
                Divider()
                inputBar
            }
        }
        .background(theme.paneBackground)
        .task(id: contextFiles.map(\.path).joined()) {
            // Refresh cached Keychain presence + reset session for new file set
            hasAPIKey = KeychainStore.hasKey(for: .current)
            session.clear()
            session.contextFiles = contextFiles
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
            Text("AI 助手")
                .font(.system(size: theme.bodyFontSize, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Spacer()
            if !session.messages.isEmpty {
                Button { session.clear() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("清空对话")
            }
            Button { withAnimation(.easeInOut(duration: 0.22)) { isPresented = false } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(theme.rowHover))
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(theme.sidebarBackground)
    }

    // MARK: - File chips

    private var fileChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(contextFiles, id: \.path) { url in
                    Label(url.lastPathComponent, systemImage: fileIcon(url))
                        .font(.system(size: theme.captionFontSize))
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(theme.rowHover)
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Chat area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    fileChips
                    Divider().padding(.horizontal, 14)

                    if session.messages.isEmpty {
                        emptyPrompt
                    }

                    ForEach(session.messages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                    }

                    if let err = session.errorText {
                        Text(err)
                            .font(.system(size: theme.captionFontSize))
                            .foregroundStyle(.red)
                            .padding(12)
                    }
                }
            }
            .onChange(of: session.messages.count) { _, _ in
                if let last = session.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundStyle(theme.secondaryText.opacity(0.4))
            Text("问我关于这\(contextFiles.count > 1 ? "些" : "个")文件的任何问题")
                .font(.system(size: theme.captionFontSize))
                .foregroundStyle(theme.secondaryText.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("输入问题…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: theme.bodyFontSize))
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: session.isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend ? theme.accent : theme.secondaryText.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear { inputFocused = true }
    }

    // MARK: - Empty states

    private var noFileState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(theme.secondaryText.opacity(0.4))
            Text("在文件列表选中文件后\n按 ⌘I 开始对话")
                .font(.system(size: theme.captionFontSize))
                .foregroundStyle(theme.secondaryText.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noKeyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 32))
                .foregroundStyle(theme.accent.opacity(0.7))
            Text("需要设置 Claude API Key")
                .font(.system(size: theme.bodyFontSize, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Text("在「设置 → AI」中填写你的 Anthropic API Key")
                .font(.system(size: theme.captionFontSize))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("打开设置") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private var canSend: Bool {
        !session.isLoading && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        guard canSend, let c = client else { return }
        let text = inputText
        inputText = ""
        Task { await session.send(userText: text, client: c) }
    }

    private func fileIcon(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":                        return "doc.richtext"
        case "png","jpg","jpeg","heic","gif","webp": return "photo"
        case "swift","py","js","ts","rb","go","rs": return "chevron.left.forwardslash.chevron.right"
        case "md","txt","rtf":             return "doc.text"
        case "json","yaml","yml","toml":   return "doc.badge.gearshape"
        default:                           return "doc"
        }
    }
}
