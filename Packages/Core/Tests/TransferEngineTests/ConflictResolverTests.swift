import XCTest
import FileSystemKit
@testable import TransferEngine

final class ConflictResolverTests: XCTestCase {
    private func item(_ name: String) -> FileItem {
        FileItem(
            id: "/tmp/\(name)",
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            isDirectory: false
        )
    }

    func testAutoRenameWithExtension() async {
        let resolution = await AutoRenameResolver().resolve(
            source: item("foo.txt"), destination: item("foo.txt"))
        XCTAssertEqual(resolution, .rename(newName: "foo (副本).txt"))
    }

    func testAutoRenameWithoutExtension() async {
        let resolution = await AutoRenameResolver().resolve(
            source: item("foo"), destination: item("foo"))
        XCTAssertEqual(resolution, .rename(newName: "foo (副本)"))
    }

    func testAutoRenameMultiDotExtension() async {
        // Only the last extension is treated as ext (matches FileManager / NSString conventions)
        let resolution = await AutoRenameResolver().resolve(
            source: item("archive.tar.gz"), destination: item("archive.tar.gz"))
        XCTAssertEqual(resolution, .rename(newName: "archive.tar (副本).gz"))
    }

    func testAlwaysSkipResolver() async {
        let resolution = await AlwaysSkipResolver().resolve(
            source: item("a"), destination: item("a"))
        XCTAssertEqual(resolution, .skip)
    }

    func testAlwaysOverwriteResolver() async {
        let resolution = await AlwaysOverwriteResolver().resolve(
            source: item("a"), destination: item("a"))
        XCTAssertEqual(resolution, .overwrite)
    }
}
