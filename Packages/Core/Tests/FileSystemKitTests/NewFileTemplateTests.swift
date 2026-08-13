import XCTest
@testable import FileSystemKit

final class NewFileTemplateTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("template-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - 纯文本模板

    func testPlainTextTemplatesAreEmpty() {
        for t in [NewFileTemplate.txt, .md, .py] {
            XCTAssertEqual(t.makeData().count, 0, "\(t) 应为空文件")
        }
    }

    // MARK: - OOXML 模板结构

    func testDocxIsValidZipWithRequiredParts() throws {
        let data = NewFileTemplate.docx.makeData()
        let url = tempDir.appendingPathComponent("t.docx")
        try data.write(to: url)
        let reader = try ZipArchiveReader(url: url)
        let names = Set(reader.entries.map(\.path))
        XCTAssertTrue(names.contains("[Content_Types].xml"))
        XCTAssertTrue(names.contains("_rels/.rels"))
        XCTAssertTrue(names.contains("word/document.xml"))
        let doc = try reader.data(for: "word/document.xml")
        XCTAssertTrue(String(decoding: doc, as: UTF8.self).contains("<w:body>"))
    }

    func testXlsxIsValidZipWithRequiredParts() throws {
        let data = NewFileTemplate.xlsx.makeData()
        let url = tempDir.appendingPathComponent("t.xlsx")
        try data.write(to: url)
        let reader = try ZipArchiveReader(url: url)
        let names = Set(reader.entries.map(\.path))
        XCTAssertTrue(names.contains("xl/workbook.xml"))
        XCTAssertTrue(names.contains("xl/worksheets/sheet1.xml"))
        XCTAssertTrue(names.contains("xl/_rels/workbook.xml.rels"))
        let wb = try reader.data(for: "xl/workbook.xml")
        XCTAssertTrue(String(decoding: wb, as: UTF8.self).contains("<sheet "))
    }

    func testPptxIsValidZipWithRequiredParts() throws {
        let data = NewFileTemplate.pptx.makeData()
        let url = tempDir.appendingPathComponent("t.pptx")
        try data.write(to: url)
        let reader = try ZipArchiveReader(url: url)
        let names = Set(reader.entries.map(\.path))
        for required in ["ppt/presentation.xml", "ppt/slides/slide1.xml",
                         "ppt/slideLayouts/slideLayout1.xml",
                         "ppt/slideMasters/slideMaster1.xml",
                         "ppt/theme/theme1.xml",
                         "ppt/_rels/presentation.xml.rels"] {
            XCTAssertTrue(names.contains(required), "缺少 \(required)")
        }
    }

    /// 系统级交叉验证：macOS 自带 unzip 能解开我们的模板。
    func testTemplateUnzippableBySystem() throws {
        for t in [NewFileTemplate.docx, .xlsx, .pptx] {
            let url = tempDir.appendingPathComponent("sys.\(t.rawValue)")
            try t.makeData().write(to: url)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-t", url.path]   // 仅测试完整性
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "\(t) 未通过系统 unzip 校验")
        }
    }

    // MARK: - createFile 落链

    func testCreateFileViaProvider() async throws {
        let provider = LocalFileProvider()
        let target = tempDir.appendingPathComponent("未命名.md")
        let p = provider.providerPath(for: target)
        try await provider.createFile(p, contents: NewFileTemplate.md.makeData())
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        // 已存在时拒绝覆盖
        await XCTAssertThrowsErrorAsync(try await provider.createFile(p, contents: Data())) { _ in }
    }
}
