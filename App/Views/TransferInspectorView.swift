import SwiftUI
import TransferEngine
import AppearanceKit

struct TransferInspectorView: View {
    @ObservedObject var queue: TransferQueue
    @Binding var isPresented: Bool
    @Environment(\.appearanceTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if queue.tasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .background(theme.paneBackground)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack(alignment: .center) {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.accent)
                Text("传输队列")
                    .font(.system(size: theme.bodyFontSize, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                // Clear completed
                if doneCount > 0 {
                    Button(action: { queue.clearCompleted() }) {
                        Text("清空")
                            .font(.system(size: theme.captionFontSize))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .buttonStyle(.borderless)
                }
                // Close panel
                Button(action: { withAnimation(.easeInOut(duration: 0.22)) { isPresented = false } }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle().fill(theme.rowHover)
                        )
                }
                .buttonStyle(.plain)
                .help("关闭传输面板")
            }

            // Summary + aggregate progress
            if !queue.tasks.isEmpty {
                HStack(spacing: 6) {
                    if activeCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(theme.accent)
                                .frame(width: 6, height: 6)
                            Text("\(activeCount) 进行中")
                                .foregroundStyle(theme.accent)
                        }
                    }
                    if doneCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("\(doneCount) 完成")
                        }
                    }
                    if failedCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("\(failedCount) 失败")
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    if !formattedTotal.isEmpty {
                        Text(formattedTotal)
                            .monospacedDigit()
                    }
                }
                .font(.system(size: theme.captionFontSize))
                .foregroundStyle(theme.secondaryText)

                // Aggregate progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.rowHover)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(activeCount > 0 ? theme.accent : Color.green)
                            .frame(width: geo.size.width * aggregateFraction, height: 4)
                            .animation(.linear(duration: 0.3), value: aggregateFraction)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.sidebarBackground)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(theme.secondaryText.opacity(0.4))
            Text("暂无传输任务")
                .font(.system(size: theme.captionFontSize))
                .foregroundStyle(theme.secondaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Task list

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(queue.tasks) { task in
                    TransferRow(task: task, theme: theme) {
                        queue.cancel(task.id)
                    }
                    Divider()
                        .padding(.leading, 14)
                }
            }
        }
    }

    // MARK: - Computed helpers

    private var activeCount: Int {
        queue.tasks.filter {
            if case .pending = $0.status { return true }
            if case .running = $0.status { return true }
            return false
        }.count
    }

    private var doneCount: Int {
        queue.tasks.filter {
            if case .completed  = $0.status { return true }
            if case .cancelled  = $0.status { return true }
            if case .skipped    = $0.status { return true }
            return false
        }.count
    }

    private var failedCount: Int {
        queue.tasks.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    private var aggregateFraction: Double {
        guard !queue.tasks.isEmpty else { return 0 }
        let total = Double(queue.tasks.count)
        let done  = queue.tasks.reduce(0.0) { acc, t in
            switch t.status {
            case .completed, .cancelled, .skipped: return acc + 1.0
            case .running(let p):            return acc + p
            case .failed:                    return acc + 1.0
            default:                         return acc
            }
        }
        return min(done / total, 1.0)
    }

    private var formattedTotal: String {
        let total = queue.tasks.reduce(Int64(0)) { $0 + max(0, $1.bytesTotal) }
        guard total > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}

// MARK: - TransferRow

private struct TransferRow: View {
    let task: TransferTask
    let theme: any AppearanceTheme
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Status icon
            statusIcon
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                // File name + action badge
                HStack(spacing: 6) {
                    Text(fileName)
                        .font(.system(size: theme.bodyFontSize))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    kindBadge
                }

                // Route
                Text(route)
                    .font(.system(size: theme.captionFontSize - 1))
                    .foregroundStyle(theme.secondaryText.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Progress / error
                progressArea
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var fileName: String {
        task.source.components.last ?? "—"
    }

    private var route: String {
        let src = task.source.components.dropLast().joined(separator: "/")
        let dst = task.destination.components.dropLast().joined(separator: "/")
        return "/\(src) → /\(dst)"
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(theme.secondaryText.opacity(0.6))
        case .running:
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(theme.accent)
                .symbolEffect(.pulse)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle")
                .foregroundStyle(theme.secondaryText.opacity(0.5))
        case .skipped:
            Image(systemName: "arrow.right.to.line.compact")
                .foregroundStyle(theme.secondaryText.opacity(0.5))
        }
    }

    @ViewBuilder
    private var kindBadge: some View {
        switch task.status {
        case .pending:
            HStack(spacing: 4) {
                Text(task.kind == .copy ? "复制" : "移动")
                    .font(.system(size: theme.captionFontSize - 1))
                    .foregroundStyle(theme.secondaryText)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        case .running(let p):
            Text("\(Int(p * 100))%")
                .font(.system(size: theme.captionFontSize - 1).monospacedDigit())
                .foregroundStyle(theme.secondaryText)
        case .completed:
            Text("完成")
                .font(.system(size: theme.captionFontSize - 1))
                .foregroundStyle(.green.opacity(0.9))
        case .failed:
            Text("失败")
                .font(.system(size: theme.captionFontSize - 1))
                .foregroundStyle(.red)
        case .cancelled:
            Text("已取消")
                .font(.system(size: theme.captionFontSize - 1))
                .foregroundStyle(theme.secondaryText.opacity(0.6))
        case .skipped:
            Text("已跳过")
                .font(.system(size: theme.captionFontSize - 1))
                .foregroundStyle(theme.secondaryText.opacity(0.6))
        }
    }

    @ViewBuilder
    private var progressArea: some View {
        switch task.status {
        case .running(let p):
            ProgressView(value: p)
                .progressViewStyle(.linear)
                .tint(theme.accent)
        case .pending:
            ProgressView(value: 0)
                .progressViewStyle(.linear)
                .tint(theme.secondaryText)
                .opacity(0.35)
        case .completed:
            ProgressView(value: 1)
                .progressViewStyle(.linear)
                .tint(.green)
        case .failed(let msg):
            Text(msg)
                .font(.system(size: theme.captionFontSize - 1))
                .foregroundStyle(.red.opacity(0.85))
                .lineLimit(2)
        case .cancelled:
            EmptyView()
        case .skipped:
            EmptyView()
        }
    }
}
