import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Reads file content and converts it into Claude message blocks.
public struct FileContextBuilder {

    /// Maximum characters for text files before truncation.
    private static let maxTextChars = 300_000   // ~100k tokens

    /// Build a user message block for one file.
    /// Returns `.text` for text/PDF, `.image` for images, or a metadata
    /// placeholder for unsupported binaries.
    public static func block(for url: URL) async throws -> ClaudeMessage.ContentBlock {
        let ext = url.pathExtension.lowercased()

        if imageExtensions.contains(ext) {
            return try imageBlock(url: url, ext: ext)
        }
        if ext == "pdf" {
            return pdfBlock(url: url)
        }
        if textExtensions.contains(ext) || ext.isEmpty {
            return textBlock(url: url)
        }
        // Binary / unknown — send metadata only
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return .text("[\(url.lastPathComponent) — \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)), binary, cannot display content]")
    }

    /// Build multiple blocks for a set of files, preceded by a context header.
    public static func blocks(for urls: [URL]) async -> [ClaudeMessage.ContentBlock] {
        var result: [ClaudeMessage.ContentBlock] = []
        for url in urls {
            result.append(.text("\n\n---\n**File: \(url.lastPathComponent)**\n"))
            if let block = try? await block(for: url) {
                result.append(block)
            } else {
                result.append(.text("[Could not read file]"))
            }
        }
        return result
    }

    // MARK: - Private helpers

    private static func textBlock(url: URL) -> ClaudeMessage.ContentBlock {
        guard let raw = try? String(contentsOf: url, encoding: .utf8)
                     ?? String(contentsOf: url, encoding: .isoLatin1) else {
            return .text("[Could not read text file]")
        }
        let truncated = raw.count > maxTextChars
            ? String(raw.prefix(maxTextChars)) + "\n\n[… truncated …]"
            : raw
        return .text("```\n\(truncated)\n```")
    }

    private static func pdfBlock(url: URL) -> ClaudeMessage.ContentBlock {
        guard let doc = PDFDocument(url: url) else {
            return .text("[Could not parse PDF]")
        }
        var pages: [String] = []
        let limit = min(doc.pageCount, 50)   // cap at 50 pages to stay in token budget
        for i in 0..<limit {
            if let text = doc.page(at: i)?.string, !text.isEmpty {
                pages.append("— Page \(i + 1) —\n\(text)")
            }
        }
        if doc.pageCount > limit {
            pages.append("[… \(doc.pageCount - limit) more pages not shown …]")
        }
        let combined = pages.joined(separator: "\n\n")
        let truncated = combined.count > maxTextChars
            ? String(combined.prefix(maxTextChars)) + "\n\n[… truncated …]"
            : combined
        return .text(truncated)
    }

    private static func imageBlock(url: URL, ext: String) throws -> ClaudeMessage.ContentBlock {
        let data = try Data(contentsOf: url)
        let b64  = data.base64EncodedString()
        let mime: String
        switch ext {
        case "jpg", "jpeg": mime = "image/jpeg"
        case "png":         mime = "image/png"
        case "gif":         mime = "image/gif"
        case "webp":        mime = "image/webp"
        default:            mime = "image/jpeg"
        }
        return .image(mediaType: mime, base64: b64)
    }

    // MARK: - Extension sets

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif"
    ]

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "rst",
        "swift", "py", "js", "ts", "jsx", "tsx",
        "html", "htm", "css", "scss", "less",
        "json", "yaml", "yml", "toml", "ini", "env",
        "sh", "bash", "zsh", "fish",
        "rb", "go", "rs", "java", "kt", "c", "cpp", "h", "m",
        "sql", "graphql", "proto",
        "xml", "plist", "csv", "log",
        "dockerfile", "makefile", "gitignore",
    ]
}
