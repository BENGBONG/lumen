import Foundation
import AppKit
import PDFKit
import UniformTypeIdentifiers
import FileSystemKit

/// Reads file content and converts it into Claude message blocks.
public struct FileContextBuilder {

    /// Maximum characters for text files before truncation.
    private static let maxTextChars = 300_000   // ~100k tokens

    /// Images sent to the model are downscaled to this max dimension —
    /// raw photos would blow the token budget and slow the request.
    private static let maxImageDimension: CGFloat = 1568

    /// Build a user message block for one file.
    /// Returns `.text` for text/PDF/Office, `.image` for images, or a metadata
    /// placeholder for unsupported binaries.
    public static func block(for url: URL) async throws -> ClaudeMessage.ContentBlock {
        let ext = url.pathExtension.lowercased()

        if imageExtensions.contains(ext) {
            return try imageBlock(url: url, ext: ext)
        }
        if ext == "pdf" {
            return pdfBlock(url: url)
        }
        if officeExtensions.contains(ext) {
            return officeBlock(url: url, ext: ext)
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
        // 先缩放到模型视觉的最佳尺寸——原图直传既贵又慢
        if let scaled = downscale(url: url, maxDimension: maxImageDimension) {
            return .image(mediaType: "image/jpeg", base64: scaled.base64EncodedString())
        }
        // 缩放失败（罕见格式）回退原图
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

    /// 超过 maxDimension 的图片缩放到该尺寸并编码为 JPEG(0.85)；
    /// 小图返回 nil（走原图）。
    private static func downscale(url: URL, maxDimension: CGFloat) -> Data? {
        guard let src = NSImage(contentsOf: url) else { return nil }
        let size = src.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return nil }
        let scale = maxDimension / longest
        let target = NSSize(width: (size.width * scale).rounded(),
                            height: (size.height * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        src.draw(in: NSRect(origin: .zero, size: target),
                 from: NSRect(origin: .zero, size: size),
                 operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    // MARK: - Office (OOXML) 文本提取

    /// docx/xlsx/pptx 本质是 zip：解包取 XML，抽出文本节点。
    private static func officeBlock(url: URL, ext: String) -> ClaudeMessage.ContentBlock {
        do {
            let reader = try ZipArchiveReader(url: url)
            let text: String
            switch ext {
            case "docx": text = try extractDocx(reader)
            case "pptx": text = try extractPptx(reader)
            case "xlsx": text = try extractXlsx(reader)
            default:     text = ""
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .text("[\(url.lastPathComponent)：文档内容为空或无法提取文本]")
            }
            let truncated = text.count > maxTextChars
                ? String(text.prefix(maxTextChars)) + "\n\n[… truncated …]"
                : text
            return .text(truncated)
        } catch {
            return .text("[无法解析 \(url.lastPathComponent)：\(error.localizedDescription)]")
        }
    }

    /// Word：按段落抽 <w:t> 文本。
    private static func extractDocx(_ reader: ZipArchiveReader) throws -> String {
        let xml = String(decoding: try reader.data(for: "word/document.xml"), as: UTF8.self)
        let paragraphs = xml.components(separatedBy: "</w:p>").map { chunk -> String in
            extractTags(chunk, tag: "w:t").joined()
        }.map(xmlUnescape).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return paragraphs.joined(separator: "\n")
    }

    /// PowerPoint：按页抽 <a:t> 文本。
    private static func extractPptx(_ reader: ZipArchiveReader) throws -> String {
        let slideEntries = reader.entries
            .map(\.path)
            .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted { lhs, rhs in
                // slideN.xml 按数字排序
                func num(_ s: String) -> Int {
                    Int(s.replacingOccurrences(of: "ppt/slides/slide", with: "")
                          .replacingOccurrences(of: ".xml", with: "")) ?? 0
                }
                return num(lhs) < num(rhs)
            }
            .prefix(60)   // 页数上限，控制 token
        var pages: [String] = []
        for (i, path) in slideEntries.enumerated() {
            let xml = String(decoding: try reader.data(for: path), as: UTF8.self)
            let texts = extractTags(xml, tag: "a:t").map(xmlUnescape)
            let joined = texts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { pages.append("— 第 \(i + 1) 页 —\n\(joined)") }
        }
        return pages.joined(separator: "\n\n")
    }

    /// Excel：sharedStrings 建索引，逐 sheet 逐行输出（共享字符串按索引还原）。
    private static func extractXlsx(_ reader: ZipArchiveReader) throws -> String {
        var shared: [String] = []
        if reader.entries.contains(where: { $0.path == "xl/sharedStrings.xml" }) {
            let xml = String(decoding: try reader.data(for: "xl/sharedStrings.xml"), as: UTF8.self)
            var parts = xml.components(separatedBy: "</si>")
            parts.removeLast()   // 尾块是 </sst> 之后的残余，不是条目
            shared = parts.map { xmlUnescape(extractTags($0, tag: "t").joined()) }
        }

        let sheetPaths = reader.entries.map(\.path).filter {
            $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml")
        }.sorted()
        var out: [String] = []
        for path in sheetPaths.prefix(10) {
            let xml = String(decoding: try reader.data(for: path), as: UTF8.self)
            var lines: [String] = []
            for rowChunk in xml.components(separatedBy: "</row>") {
                let cells = extractCells(rowChunk).map { cell -> String in
                    guard let value = cell.value else { return "" }
                    if cell.isShared, let idx = Int(value), idx < shared.count {
                        return shared[idx]
                    }
                    return xmlUnescape(value)
                }
                let line = cells.joined(separator: " | ")
                    .trimmingCharacters(in: .whitespaces)
                if !line.isEmpty, line != "|" { lines.append(line) }
                if lines.joined().count > maxTextChars / 3 { break }   // 单表限额
            }
            if !lines.isEmpty {
                let name = (path as NSString).lastPathComponent
                out.append("— \(name) —\n" + lines.joined(separator: "\n"))
            }
        }
        return out.joined(separator: "\n\n")
    }

    /// 从一行 XML 里抽出单元格（是否共享字符串, 值）。
    private static func extractCells(_ row: String) -> [(isShared: Bool, value: String?)] {
        var out: [(Bool, String?)] = []
        var idx = row.startIndex
        while let cStart = row.range(of: "<c", range: idx..<row.endIndex) {
            guard let gt = row.range(of: ">", range: cStart.upperBound..<row.endIndex) else { break }
            let attrs = row[cStart.upperBound..<gt.lowerBound]
            if attrs.hasSuffix("/") { idx = gt.upperBound; continue }   // 空单元格
            guard let close = row.range(of: "</c>", range: gt.upperBound..<row.endIndex) else { break }
            let inner = String(row[gt.upperBound..<close.lowerBound])
            let isShared = attrs.contains("t=\"s\"")
            let value = extractTags(inner, tag: "v").first
                        ?? extractTags(inner, tag: "t").first
            out.append((isShared, value))
            idx = close.upperBound
        }
        return out
    }

    /// 抽取 XML 中指定标签的文本节点（容忍属性与命名空间）。
    static func extractTags(_ xml: String, tag: String) -> [String] {
        var results: [String] = []
        var searchStart = xml.startIndex
        let openPrefix = "<\(tag)"
        while let openRange = xml.range(of: openPrefix, range: searchStart..<xml.endIndex) {
            guard let gtRange = xml.range(of: ">", range: openRange.upperBound..<xml.endIndex) else { break }
            let before = xml.index(before: gtRange.lowerBound)
            if xml[before] == "/" { searchStart = gtRange.upperBound; continue }  // 自闭合
            let closeTag = "</\(tag)>"
            guard let closeRange = xml.range(of: closeTag, range: gtRange.upperBound..<xml.endIndex) else { break }
            results.append(String(xml[gtRange.upperBound..<closeRange.lowerBound]))
            searchStart = closeRange.upperBound
        }
        return results
    }

    private static func xmlUnescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&apos;", with: "'")
    }

    // MARK: - Extension sets

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif"
    ]

    private static let officeExtensions: Set<String> = [
        "docx", "xlsx", "pptx"
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
