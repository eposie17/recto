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

/// The sample paper as PDFKit gives it on Apple devices (tools/dump_pdf_text.swift, run on the Mac).
final class PDFKitPaperTests: XCTestCase {
    struct Raw: Decodable { let sizes: [[CGFloat]]; let glyphs: [[[CGFloat]]] }

    static let text: DocumentText = {
        let url = Bundle.module.url(forResource: "pdfkit-glyphs", withExtension: "json", subdirectory: "Resources")!
        let raw = try! JSONDecoder().decode(Raw.self, from: Data(contentsOf: url))
        let pages = raw.glyphs.map { page -> [[(String, CGRect)]] in
            let codes = page.map { UInt16($0[0]) }
            let bounds = page.map { $0[3] == 0 && $0[4] == 0 ? CGRect.null : CGRect(x: $0[1], y: $0[2], width: $0[3], height: $0[4]) }
            return TextLayerReader.lines(TextLayerReader.glyphs(codes: codes, bounds: bounds))
        }
        return DocumentText(pageSizes: raw.sizes.map { CGSize(width: $0[0], height: $0[1]) }, linesPerPage: pages)
    }()

    func lineText(_ id: Int) -> String {
        Self.text.lines[id].wordIDs.map { Self.text.words[$0].text }.joined(separator: " ")
    }

    func testLinesMatchThePrintedLines() {
        let t = Self.text
        let first = t.pages[0].lineIDs.prefix(8).map(lineText)
        XCTAssertEqual(first[0], "Notes Beside the Line: A Study of Facing Pages")
        XCTAssertEqual(first[1], "Posi Example and A. N. Other")
        XCTAssert(first[2].hasPrefix("Abstract. Fold beside"), first[2])
        XCTAssertEqual(first[6], "reader of page the who same (see Fig. 2 and Eq. 3).")
        XCTAssertEqual(first[7], "1 Section 1")
        // Every word is narrower than a column: none runs across a line break.
        XCTAssert(t.words.allSatisfy { $0.rect.width < 120 }, "a word spans lines")
    }

    func testFirstPageReadsTitleAbstractThenColumns() {
        let t = Self.text
        let crops = ColumnDetector.crops(page: t.pages[0], lines: t.lines)
        XCTAssertEqual(crops.count, 3, "title and abstract, then two columns")
        XCTAssertEqual(crops[0].1.count, 7, "title, authors and all five abstract lines")
        XCTAssertNotNil(ColumnDetector.gapX(page: t.pages[1], lines: t.lines))
    }

    func testEveryLineIsShownOnceInColumns() {
        let layout = ContentLayout(text: Self.text, view: .columns, width: 330)
        XCTAssertEqual(layout.pieces.flatMap(\.lineIDs).sorted(), Array(0..<Self.text.lines.count))
    }
}

extension PDFKitPaperTests {
    /// Seen on the simulator: the right column showed larger and further in than the left one,
    /// and the wide figure's right edge was cut off.
    func testColumnsShowAtTheSameSizeAndIndent() {
        let t = Self.text
        for p in t.pages.indices {
            let crops = ColumnDetector.crops(page: t.pages[p], lines: t.lines)
            let gap = ColumnDetector.gapX(page: t.pages[p], lines: t.lines)!
            let left = crops.filter { $0.0.maxX <= gap + 1 && !$0.1.isEmpty }
            let right = crops.filter { $0.0.minX >= gap - 1 && !$0.1.isEmpty }
            XCTAssertFalse(left.isEmpty); XCTAssertFalse(right.isEmpty)
            let widths = Set((left + right).map { ($0.0.width * 10).rounded() })
            XCTAssertEqual(widths.count, 1, "page \(p + 1): column crops differ in width")
            func indent(_ c: (CGRect, [Int])) -> CGFloat { c.1.map { t.lines[$0].rect.minX }.min()! - c.0.minX }
            for c in left + right { XCTAssertEqual(indent(c), indent(left[0]), accuracy: 3, "page \(p + 1)") }
        }
    }

    func testWideFigureCropReachesTheRightMargin() {
        let t = Self.text
        let crops = ColumnDetector.crops(page: t.pages[1], lines: t.lines)
        let full = crops.filter { $0.0.width > 400 }
        XCTAssertFalse(full.isEmpty)
        // The figure frame sticks out to 564 points on a 612-point page.
        for c in full { XCTAssertGreaterThanOrEqual(c.0.maxX, 564 + 3) }
        // The caption is a bit wider than a column; it reads across, not cut at the column edge.
        let caption = t.pages[1].lineIDs.first { t.words[t.lines[$0].wordIDs.lowerBound].text == "Figure" }!
        let holder = crops.first { $0.1.contains(caption) }!
        XCTAssertGreaterThanOrEqual(holder.0.maxX, t.lines[caption].rect.maxX)
    }
}
