import SwiftUI
import AppearanceKit
import AIKit

struct ChatBubble: View {
    let message: ChatSession.ChatMessage
    @Environment(\.appearanceTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .assistant {
                assistantBubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                userBubble
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Assistant bubble

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Render message as parsed blocks (code / text)
            ForEach(Array(parsedBlocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let lang, let code):
                    CodeBlockView(language: lang, code: code)
                case .text(let t):
                    Text(t)
                        .font(.system(size: theme.bodyFontSize))
                        .foregroundStyle(theme.primaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if message.isStreaming {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(height: 14)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.rowHover)
        )
    }

    // MARK: - User bubble

    private var userBubble: some View {
        Text(message.text)
            .font(.system(size: theme.bodyFontSize))
            .foregroundStyle(.white)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.accent)
            )
    }

    // MARK: - Markdown-lite block parser

    private enum Block {
        case text(String)
        case code(lang: String, code: String)
    }

    /// Very lightweight parser: splits on ``` fences only.
    private var parsedBlocks: [Block] {
        var result: [Block] = []
        var remaining = message.text
        while let fenceRange = remaining.range(of: "```") {
            let before = String(remaining[remaining.startIndex..<fenceRange.lowerBound])
            if !before.isEmpty { result.append(.text(before)) }
            remaining = String(remaining[fenceRange.upperBound...])

            // Extract optional language hint
            let lang: String
            if let nl = remaining.firstIndex(of: "\n") {
                lang = String(remaining[remaining.startIndex..<nl]).trimmingCharacters(in: .whitespaces)
                remaining = String(remaining[remaining.index(after: nl)...])
            } else { lang = "" }

            // Find closing fence
            if let closeFence = remaining.range(of: "```") {
                let code = String(remaining[remaining.startIndex..<closeFence.lowerBound])
                result.append(.code(lang: lang, code: code))
                remaining = String(remaining[closeFence.upperBound...])
            } else {
                // Unclosed fence — treat as plain text
                result.append(.text("```" + lang + "\n" + remaining))
                remaining = ""
            }
        }
        if !remaining.isEmpty { result.append(.text(remaining)) }
        return result.isEmpty ? [.text(message.text)] : result
    }
}
