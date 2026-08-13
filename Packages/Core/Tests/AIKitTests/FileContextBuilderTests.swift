import XCTest
import FileSystemKit
@testable import AIKit

final class FileContextBuilderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ai-context-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeZip(_ name: String, _ parts: [(String, String)]) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        let data = try StoredZipWriter.write(entries: parts.map {
            .init(name: $0.0, data: Data($0.1.utf8))
        })
        try data.write(to: url)
        return url
    }

    private func textOf(_ block: ClaudeMessage.ContentBlock,
                        file: StaticString = #filePath, line: UInt = #line) throws -> String {
        guard case .text(let text) = block else {
            XCTFail("期望 text block", file: file, line: line)
            return ""
        }
        return text
    }

    // MARK: - docx

    func testDocxExtractsParagraphsAndUnescapes() async throws {
        let doc = """
        <?xml version="1.0"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
        <w:p><w:r><w:t>第一段 &amp; 内容</w:t></w:r></w:p>
        <w:p><w:r><w:t xml:space="preserve">第二段 带属性</w:t></w:r></w:p>
        <w:p><w:r><w:t></w:t></w:r></w:p>
        </w:body></w:document>
        """
        let url = try makeZip("t.docx", [
            ("[Content_Types].xml", "<Types/>"),
            ("word/document.xml", doc),
        ])
        let text = try await textOf(FileContextBuilder.block(for: url))
        XCTAssertTrue(text.contains("第一段 & 内容"), "实际: \(text)")
        XCTAssertTrue(text.contains("第二段 带属性"), "实际: \(text)")
        XCTAssertFalse(text.contains("&amp;"))
    }

    // MARK: - pptx

    func testPptxExtractsSlidesInOrder() async throws {
        let url = try makeZip("t.pptx", [
            ("ppt/slides/slide2.xml", "<p:sld><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>第二页标题</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>"),
            ("ppt/slides/slide1.xml", "<p:sld><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>第一页标题</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>"),
        ])
        let text = try await textOf(FileContextBuilder.block(for: url))
        let first = try XCTUnwrap(text.range(of: "第一页标题"))
        let second = try XCTUnwrap(text.range(of: "第二页标题"))
        XCTAssertTrue(first.lowerBound < second.lowerBound, "应按页码排序: \(text)")
        XCTAssertTrue(text.contains("— 第 1 页 —"))
    }

    // MARK: - xlsx

    func testXlsxResolvesSharedStrings() async throws {
        let shared = """
        <sst><si><t>产品名称</t></si><si><t>单价</t></si><si><r><t>富</t></r><r><t>文本</t></r></si></sst>
        """
        let sheet = """
        <worksheet><sheetData>
        <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
        <row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>99.5</v></c></row>
        </sheetData></worksheet>
        """
        let url = try makeZip("t.xlsx", [
            ("xl/sharedStrings.xml", shared),
            ("xl/worksheets/sheet1.xml", sheet),
        ])
        let text = try await textOf(FileContextBuilder.block(for: url))
        XCTAssertTrue(text.contains("产品名称 | 单价"), "表头共享字符串应还原: \(text)")
        XCTAssertTrue(text.contains("富文本 | 99.5"), "富文本 si 拼接 + 数值: \(text)")
    }

    // MARK: - 图片缩放

    func testLargeImageDownscaled() async throws {
        // 造一张 3000×2000 的 PNG
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 3000, pixelsHigh: 2000,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let png = rep.representation(using: .png, properties: [:]) else {
            throw XCTSkip("无法生成测试图片")
        }
        let url = tempDir.appendingPathComponent("big.png")
        try png.write(to: url)

        let block = try await FileContextBuilder.block(for: url)
        guard case .image(let media, let b64) = block else {
            return XCTFail("期望 image block")
        }
        XCTAssertEqual(media, "image/jpeg")   // 缩放后统一走 JPEG
        let data = try XCTUnwrap(Data(base64Encoded: b64))
        let scaled = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertLessThanOrEqual(max(scaled.pixelsWide, scaled.pixelsHigh), 1568)
        XCTAssertLessThan(data.count, png.count)   // 体积必须显著下降
    }
}
