import Foundation

/// 「新建文件」的模板工厂。
///
/// txt/md/py 是纯文本（空内容，与 Finder 语义一致——给文件起个名字）；
/// docx/xlsx/pptx 是 OOXML 包（本质是 zip），这里用 StoredZipWriter
/// 在运行时生成最小合法结构，不依赖任何外部模板文件。
public enum NewFileTemplate: String, CaseIterable, Sendable {
    case txt, md, py, docx, xlsx, pptx

    public var displayName: String {
        switch self {
        case .txt:  return "文本文档 (.txt)"
        case .md:   return "Markdown (.md)"
        case .py:   return "Python 脚本 (.py)"
        case .docx: return "Word 文档 (.docx)"
        case .xlsx: return "Excel 工作簿 (.xlsx)"
        case .pptx: return "PowerPoint 演示 (.pptx)"
        }
    }

    /// 不含扩展名的默认文件名主体。
    public var defaultStem: String {
        switch self {
        case .txt, .md:  return "未命名"
        case .py:        return "未命名"
        case .docx:      return "未命名文档"
        case .xlsx:      return "未命名工作簿"
        case .pptx:      return "未命名演示"
        }
    }

    public var fileExtension: String { rawValue }

    /// 生成文件的初始字节内容。
    public func makeData() -> Data {
        switch self {
        case .txt, .md, .py:
            return Data()
        case .docx:
            return Self.makeOOXML(entries: Self.docxParts)
        case .xlsx:
            return Self.makeOOXML(entries: Self.xlsxParts)
        case .pptx:
            return Self.makeOOXML(entries: Self.pptxParts)
        }
    }

    private static func makeOOXML(entries: [(String, String)]) -> Data {
        let zipEntries = entries.map {
            StoredZipWriter.Entry(name: $0.0, data: Data($0.1.utf8))
        }
        // 模板内容全部由下方常量构造，不可能失败；失败时退回空 Data 由上层兜底报错
        return (try? StoredZipWriter.write(entries: zipEntries)) ?? Data()
    }

    // MARK: - OOXML 最小部件集

    private static let xmlDecl = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    private static func contentTypes(overrides: [(String, String)]) -> String {
        let body = overrides.map {
            "<Override PartName=\"\($0.0)\" ContentType=\"\($0.1)\"/>"
        }.joined()
        return xmlDecl
            + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
            + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
            + body + "</Types>"
    }

    private static func rootRels(target: String) -> String {
        xmlDecl
        + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"\(target)\"/>"
        + "</Relationships>"
    }

    private static func rels(_ items: [(String, String, String)]) -> String {
        let body = items.map {
            "<Relationship Id=\"\($0.0)\" Type=\"\($0.1)\" Target=\"\($0.2)\"/>"
        }.joined()
        return xmlDecl
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + body + "</Relationships>"
    }

    // MARK: Word

    private static let docxParts: [(String, String)] = [
        ("[Content_Types].xml", contentTypes(overrides: [
            ("/word/document.xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"),
        ])),
        ("_rels/.rels", rootRels(target: "word/document.xml")),
        ("word/document.xml", xmlDecl
            + "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + "<w:body><w:p/><w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/></w:sectPr></w:body></w:document>"),
    ]

    // MARK: Excel

    private static let xlsxParts: [(String, String)] = [
        ("[Content_Types].xml", contentTypes(overrides: [
            ("/xl/workbook.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"),
            ("/xl/worksheets/sheet1.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"),
        ])),
        ("_rels/.rels", rootRels(target: "xl/workbook.xml")),
        ("xl/workbook.xml", xmlDecl
            + "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" "
            + "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
            + "<sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"),
        ("xl/_rels/workbook.xml.rels", rels([
            ("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet", "worksheets/sheet1.xml"),
        ])),
        ("xl/worksheets/sheet1.xml", xmlDecl
            + "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData/></worksheet>"),
    ]

    // MARK: PowerPoint

    /// 空 spTree（slide/layout/master 共用）。
    private static let emptySpTree = "<p:spTree>"
        + "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"
        + "<p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/>"
        + "<a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr></p:spTree>"

    private static let pmlNS = "xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" "
        + "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
        + "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""

    private static let pptxParts: [(String, String)] = [
        ("[Content_Types].xml", contentTypes(overrides: [
            ("/ppt/presentation.xml", "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"),
            ("/ppt/slides/slide1.xml", "application/vnd.openxmlformats-officedocument.presentationml.slide+xml"),
            ("/ppt/slideLayouts/slideLayout1.xml", "application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"),
            ("/ppt/slideMasters/slideMaster1.xml", "application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"),
            ("/ppt/theme/theme1.xml", "application/vnd.openxmlformats-officedocument.theme+xml"),
        ])),
        ("_rels/.rels", rootRels(target: "ppt/presentation.xml")),
        ("ppt/presentation.xml", xmlDecl
            + "<p:presentation \(pmlNS)>"
            + "<p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst>"
            + "<p:sldIdLst><p:sldId id=\"256\" r:id=\"rId2\"/></p:sldIdLst>"
            + "<p:sldSz cx=\"9144000\" cy=\"6858000\" type=\"screen4x3\"/>"
            + "<p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>"),
        ("ppt/_rels/presentation.xml.rels", rels([
            ("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster", "slideMasters/slideMaster1.xml"),
            ("rId2", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide", "slides/slide1.xml"),
            ("rId3", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme", "theme/theme1.xml"),
        ])),
        ("ppt/slides/slide1.xml", xmlDecl
            + "<p:sld \(pmlNS)><p:cSld>\(emptySpTree)</p:cSld>"
            + "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"),
        ("ppt/slides/_rels/slide1.xml.rels", rels([
            ("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout", "../slideLayouts/slideLayout1.xml"),
        ])),
        ("ppt/slideLayouts/slideLayout1.xml", xmlDecl
            + "<p:sldLayout \(pmlNS) type=\"blank\" preserve=\"1\">"
            + "<p:cSld name=\"空白\">\(emptySpTree)</p:cSld>"
            + "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"),
        ("ppt/slideLayouts/_rels/slideLayout1.xml.rels", rels([
            ("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster", "../slideMasters/slideMaster1.xml"),
        ])),
        ("ppt/slideMasters/slideMaster1.xml", xmlDecl
            + "<p:sldMaster \(pmlNS)>"
            + "<p:cSld>\(emptySpTree)</p:cSld>"
            + "<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>"
            + "<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst>"
            + "<p:txStyles><p:titleStyle><a:lvl1pPr/></p:titleStyle>"
            + "<p:bodyStyle><a:lvl1pPr/></p:bodyStyle>"
            + "<p:otherStyle><a:lvl1pPr/></p:otherStyle></p:txStyles></p:sldMaster>"),
        ("ppt/slideMasters/_rels/slideMaster1.xml.rels", rels([
            ("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout", "../slideLayouts/slideLayout1.xml"),
            ("rId2", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme", "../theme/theme1.xml"),
        ])),
        ("ppt/theme/theme1.xml", xmlDecl
            + "<a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"Lumen\">"
            + "<a:themeElements>"
            + "<a:clrScheme name=\"Office\">"
            + "<a:dk1><a:sysClr val=\"windowText\" lastClr=\"000000\"/></a:dk1>"
            + "<a:lt1><a:sysClr val=\"window\" lastClr=\"FFFFFF\"/></a:lt1>"
            + "<a:dk2><a:srgbClr val=\"1F2937\"/></a:dk2>"
            + "<a:lt2><a:srgbClr val=\"F3F4F6\"/></a:lt2>"
            + "<a:accent1><a:srgbClr val=\"4472C4\"/></a:accent1>"
            + "<a:accent2><a:srgbClr val=\"ED7D31\"/></a:accent2>"
            + "<a:accent3><a:srgbClr val=\"A5A5A5\"/></a:accent3>"
            + "<a:accent4><a:srgbClr val=\"FFC000\"/></a:accent4>"
            + "<a:accent5><a:srgbClr val=\"5B9BD5\"/></a:accent5>"
            + "<a:accent6><a:srgbClr val=\"70AD47\"/></a:accent6>"
            + "<a:hlink><a:srgbClr val=\"0563C1\"/></a:hlink>"
            + "<a:folHlink><a:srgbClr val=\"954F72\"/></a:folHlink>"
            + "</a:clrScheme>"
            + "<a:fontScheme name=\"Office\">"
            + "<a:majorFont><a:latin typeface=\"Calibri\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:majorFont>"
            + "<a:minorFont><a:latin typeface=\"Calibri\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:minorFont>"
            + "</a:fontScheme>"
            + "<a:fmtScheme name=\"Office\">"
            + "<a:fillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
            + "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
            + "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:fillStyleLst>"
            + "<a:lnStyleLst><a:ln w=\"6350\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln>"
            + "<a:ln w=\"12700\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln>"
            + "<a:ln w=\"19050\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln></a:lnStyleLst>"
            + "<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle>"
            + "<a:effectStyle><a:effectLst/></a:effectStyle>"
            + "<a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>"
            + "<a:bgFillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
            + "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
            + "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:bgFillStyleLst>"
            + "</a:fmtScheme>"
            + "</a:themeElements></a:theme>"),
    ]
}
