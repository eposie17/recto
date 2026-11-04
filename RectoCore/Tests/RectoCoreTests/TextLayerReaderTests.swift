import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import RectoCore

final class TextLayerReaderTests: XCTestCase {
    typealias G = TextLayerReader.Glyph

    /// Characters for a word at x, on a row whose glyph tops are at y, 5 points per letter.
    func glyphs(_ s: String, x: CGFloat, y: CGFloat) -> [G] {
        s.utf16.enumerated().map { i, c in
            c == 0x20 ? G(code: c, rect: .null) : G(code: c, rect: CGRect(x: x + CGFloat(i) * 5, y: y, width: 4.5, height: 6.6))
        }
    }

    /// What PDFKit did with the sample paper: no space or break between one printed line and the next.
    func testLineEndWithNoBreakStillStartsANewLine() {
        let g = glyphs("page written an", x: 400, y: 106) + glyphs("d beside", x: 60, y: 117.5)
        let lines = TextLayerReader.lines(g)
        XCTAssertEqual(lines.map { $0.map(\.0) }, [["page", "written", "an"], ["d", "beside"]])
        XCTAssert(lines[0].allSatisfy { $0.1.maxX < 500 })
    }

    func testDescendersAndPeriodsStayOnTheRow() {
        var g = glyphs("Eq", x: 60, y: 100)
        g.append(G(code: 0x2E, rect: CGRect(x: 70, y: 105, width: 2, height: 1.6)))   // "." sits on the baseline
        g.append(G(code: 0x20, rect: .null))
        g.append(G(code: 0x67, rect: CGRect(x: 76, y: 101.5, width: 4.5, height: 7)))  // "g" hangs lower
        let lines = TextLayerReader.lines(g)
        XCTAssertEqual(lines.map { $0.map(\.0) }, [["Eq.", "g"]])
    }

    func testWordsOnALineShareTheLineHeight() {
        var g = glyphs("a", x: 60, y: 102)
        g.append(G(code: 0x20, rect: .null))
        g.append(G(code: 0x54, rect: CGRect(x: 70, y: 100, width: 5, height: 9)))     // "T" is taller
        let line = TextLayerReader.lines(g)[0]
        XCTAssertEqual(line[0].1.minY, 100); XCTAssertEqual(line[0].1.height, 9)
    }

    func testColumnJumpOnTheSameRowSplitsTheLine() {
        let g = glyphs("left", x: 60, y: 100) + glyphs("right", x: 320, y: 100)
        XCTAssertEqual(TextLayerReader.lines(g).count, 2)
    }
}
