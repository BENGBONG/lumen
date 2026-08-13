import Foundation

/// Manages a single chat conversation: message history + streaming state.
@MainActor
@Observable
public final class ChatSession {

    // MARK: - Types

    public struct ChatMessage: Identifiable {
        public let id    = UUID()
        public let role: ClaudeMessage.Role
        public var text: String
        public var isStreaming: Bool = false

        public init(role: ClaudeMessage.Role, text: String, isStreaming: Bool = false) {
            self.role = role; self.text = text; self.isStreaming = isStreaming
        }
    }

    // MARK: - Published state

    public private(set) var messages:   [ChatMessage] = []
    public private(set) var isLoading:  Bool = false
    public private(set) var errorText:  String?

    /// Files whose content has been loaded as context for this session.
    public var contextFiles: [URL] = []

    /// Cached file content blocks — built on the first send, reused in every
    /// subsequent turn so the model never loses file context mid-conversation.
    private var cachedFileBlocks: [ClaudeMessage.ContentBlock]?

    // MARK: - Init

    public init() {}

    // MARK: - Send

    public func send(userText: String, client: AIClient) async {
        guard !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorText  = nil
        isLoading  = true

        // Append user message to visible history
        messages.append(ChatMessage(role: .user, text: userText))

        // Build the messages array for the API call.
        //
        // Strategy: always include file content in the FIRST user message so
        // the model retains context for every subsequent turn.  We cache the
        // blocks after the first load so we don't re-read files on every send.
        var apiMsgs: [ClaudeMessage] = []
        if messages.count == 1 && !contextFiles.isEmpty {
            // First turn: read files, cache the blocks, send everything together.
            let fileBlocks = await FileContextBuilder.blocks(for: contextFiles)
            cachedFileBlocks = fileBlocks
            let combined = fileBlocks + [.text("\n\n---\n\n" + userText)]
            apiMsgs = [ClaudeMessage(role: .user, blocks: combined)]
        } else {
            // Subsequent turns: rebuild full history, restoring file context in
            // the first user message so the model never forgets the files.
            apiMsgs = apiMessagesWithContext()
        }

        do {
            let assistantIdx = messages.count
            messages.append(ChatMessage(role: .assistant, text: "", isStreaming: true))

            try await client.streamChat(
                system: systemPrompt,
                messages: apiMsgs,
                onChunk: { [weak self] chunk in
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.messages[assistantIdx].text += chunk
                    }
                }
            )
            messages[assistantIdx].isStreaming = false
        } catch {
            if messages.last?.role == .assistant, messages.last?.text.isEmpty == true {
                messages.removeLast()
            }
            errorText = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Clear

    public func clear() {
        messages         = []
        errorText        = nil
        contextFiles     = []
        cachedFileBlocks = nil
    }

    // MARK: - Private helpers

    private let systemPrompt = """
        你是用户的文件助手，帮助用户理解和分析他们的文件。
        请用中文回答，除非用户用其他语言提问。
        回答要简洁有用，代码示例请使用 markdown 代码块。
        """

    /// Build the message history for the API, ensuring the first user message
    /// always contains the full file-context blocks (not just display text).
    private func apiMessagesWithContext() -> [ClaudeMessage] {
        var result: [ClaudeMessage] = []
        for (idx, msg) in messages.dropLast().enumerated() {
            if idx == 0, let cached = cachedFileBlocks, msg.role == .user {
                // Restore the original first message with full file content
                let blocks = cached + [.text("\n\n---\n\n" + msg.text)]
                result.append(ClaudeMessage(role: .user, blocks: blocks))
            } else {
                result.append(ClaudeMessage(role: msg.role, text: msg.text))
            }
        }
        return result
    }
}
