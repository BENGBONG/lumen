import SwiftUI
import AppearanceKit

struct CodeBlockView: View {
    let language: String
    let code: String
    @Environment(\.appearanceTheme) private var theme
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                if !language.isEmpty {
                    Text(language)
                        .font(.system(size: theme.captionFontSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                Button(action: copyCode) {
                    Label(copied ? "已复制" : "复制",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: theme.captionFontSize - 1))
                        .foregroundStyle(copied ? .green : theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(theme.separator.opacity(0.5))

            // Code text
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.trimmingCharacters(in: .newlines))
                    .font(.system(size: theme.captionFontSize, design: .monospaced))
                    .foregroundStyle(theme.primaryText)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = false }
        }
    }
}
