import SwiftUI
import FileSystemKit
import AppearanceKit

struct PathBarView: View {
    let path: ProviderPath
    let isFocused: Bool
    let onJump: (ProviderPath) -> Void
    @Environment(\.appearanceTheme) private var theme

    @State private var isEditing = false
    @State private var editText  = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                editField
            } else {
                breadcrumb
            }
        }
        .frame(height: 28)
        .glassChrome(theme)
        .background(isFocused ? theme.accent.opacity(0.10) : Color.clear)
        // Sync edit text whenever the actual path changes externally.
        .onChange(of: path) { _, newPath in
            if isEditing { editText = newPath.displayString }
        }
    }

    // MARK: - Breadcrumb view

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                PathSegment(
                    label: "/",
                    icon: "internaldrive",
                    isLast: path.components.isEmpty,
                    onTap: {
                        onJump(ProviderPath(providerID: path.providerID, components: []))
                    }
                )
                ForEach(Array(path.components.enumerated()), id: \.offset) { idx, comp in
                    Image(systemName: "chevron.right")
                        .font(.system(size: theme.captionFontSize - 2, weight: .medium))
                        .foregroundStyle(theme.secondaryText.opacity(0.5))
                    PathSegment(
                        label: comp,
                        icon: nil,
                        isLast: idx == path.components.count - 1,
                        onTap: {
                            let newComponents = Array(path.components.prefix(idx + 1))
                            onJump(ProviderPath(providerID: path.providerID,
                                               components: newComponents))
                        }
                    )
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
        }
        // Double-click anywhere on the path bar to enter edit mode.
        .onTapGesture(count: 2) { enterEditMode() }
    }

    // MARK: - Edit field

    private var editField: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: theme.captionFontSize))
                .foregroundStyle(theme.accent)
            TextField("输入路径", text: $editText)
                .textFieldStyle(.plain)
                .font(.system(size: theme.bodyFontSize, design: .monospaced))
                .focused($editFocused)
                .onSubmit { commitEdit() }
                .onKeyPress(.escape) { cancelEdit(); return .handled }
        }
        .padding(.horizontal, 10)
        .onAppear {
            // Focus the field on the next tick so the view is fully installed.
            DispatchQueue.main.async { editFocused = true }
        }
    }

    // MARK: - Helpers

    private func enterEditMode() {
        editText  = path.displayString
        isEditing = true
    }

    private func commitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing   = false
        guard !trimmed.isEmpty else { return }
        let components = trimmed
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        onJump(ProviderPath(providerID: path.providerID, components: components))
    }

    private func cancelEdit() {
        isEditing = false
    }
}

// MARK: - PathSegment

private struct PathSegment: View {
    let label: String
    let icon: String?
    let isLast: Bool
    let onTap: () -> Void
    @State private var isHovering = false
    @Environment(\.appearanceTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: theme.captionFontSize))
                        .foregroundStyle(theme.secondaryText)
                }
                Text(label)
                    .font(.system(size: theme.bodyFontSize,
                                  weight: isLast ? .semibold : .regular))
                    .foregroundStyle(isLast ? theme.primaryText : theme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering ? theme.rowHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
