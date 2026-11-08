import CoreGraphics
import XCTest
@testable import TextSnipperCore

final class TextAssemblyTests: XCTestCase {
    func testWordsOnTheSameLineAreOrderedLeftToRight() {
        let pieces = [
            TextPiece(text: "world", box: CGRect(x: 0.5, y: 0.6, width: 0.2, height: 0.1)),
            TextPiece(text: "Hello", box: CGRect(x: 0.1, y: 0.61, width: 0.2, height: 0.1)),
        ]
        XCTAssertEqual(TextAssembly.assemble(pieces, keepLineBreaks: true), "Hello world")
    }

    func testLinesStaySeparateWhenRequested() {
        let pieces = [
            TextPiece(text: "world", box: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08)),
            TextPiece(text: "there", box: CGRect(x: 0.45, y: 0.7, width: 0.2, height: 0.08)),
            TextPiece(text: "Hello", box: CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.08)),
        ]
        XCTAssertEqual(
            TextAssembly.assemble(pieces, keepLineBreaks: true),
            "Hello there\nworld"
        )
    }

    func testLinesJoinIntoAParagraph() {
        let pieces = [
            TextPiece(text: "Hello", box: CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.08)),
            TextPiece(text: "world", box: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08)),
        ]
        XCTAssertEqual(TextAssembly.assemble(pieces, keepLineBreaks: false), "Hello world")
    }

    func testCodeLinesKeepRelativeIndent() {
        let pieces = [
            TextPiece(text: "abcdefghij", box: CGRect(x: 0.10, y: 0.70, width: 0.40, height: 0.05)),
            TextPiece(text: "abcdefgh", box: CGRect(x: 0.26, y: 0.40, width: 0.32, height: 0.05)),
        ]
        XCTAssertEqual(
            TextAssembly.assemble(pieces, keepLineBreaks: true, preserveColumns: true),
            "abcdefghij\n    abcdefgh"
        )
    }

    func testSideBySideColumnsAreReadOneAfterTheOther() {
        func piece(_ text: String, _ x: CGFloat, _ y: CGFloat) -> TextPiece {
            TextPiece(text: text, box: CGRect(x: x, y: y, width: 0.18, height: 0.05))
        }
        let pieces = [
            piece("Changelog", 0.05, 0.90),
            piece("Dev Builds", 0.72, 0.90),
            piece("BUILD 4215", 0.05, 0.75),
            piece("Sublime Text 2", 0.72, 0.75),
            piece("25 Sep 2026", 0.05, 0.60),
            piece("Sublime Text 3", 0.72, 0.60),
        ]
        XCTAssertEqual(
            TextAssembly.assemble(pieces, keepLineBreaks: true),
            """
            Changelog
            BUILD 4215
            25 Sep 2026

            Dev Builds
            Sublime Text 2
            Sublime Text 3
            """
        )
    }

    func testBlankPiecesAreDropped() {
        let pieces = [
            TextPiece(text: "   ", box: CGRect(x: 0, y: 0, width: 0.1, height: 0.1)),
            TextPiece(text: "", box: CGRect(x: 0.2, y: 0, width: 0.1, height: 0.1)),
        ]
        XCTAssertEqual(TextAssembly.assemble(pieces, keepLineBreaks: true), "")
    }
}
