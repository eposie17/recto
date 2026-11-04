import XCTest
@testable import RectoCore

/// A paper made with a real PDF tool and read back with a real text extractor
/// (tools/make_test_paper.py): title and abstract across both columns, a full-width figure
/// in the middle of page 2 with its caption, uneven line lengths.
final class RealPaperTests: XCTestCase {
    struct Raw: Decodable {
        struct W: Decodable { let t: String; let r: [CGFloat] }
        let sizes: [[CGFloat]]
        let pages: [[[W]]]
    }

    static let text: DocumentText = {
        let url = Bundle.module.url(forResource: "test-paper", withExtension: "json", subdirectory: "Resources")!
        let raw = try! JSONDecoder().decode(Raw.self, from: Data(contentsOf: url))
        return DocumentText(
            pageSizes: raw.sizes.map { CGSize(width: $0[0], height: $0[1]) },
            linesPerPage: raw.pages.map { $0.map { $0.map { ($0.t, CGRect(x: $0.r[0], y: $0.r[1], width: $0.r[2], height: $0.r[3])) } } })
    }()

    var text: DocumentText { Self.text }

    func testEveryPageIsTwoColumns() {
        for p in text.pages.indices {
            let gap = ColumnDetector.gapX(page: text.pages[p], lines: text.lines)
            XCTAssertNotNil(gap, "page \(p + 1)")
            if let gap { XCTAssert(gap > 290 && gap < 322, "page \(p + 1) gap at \(gap)") }
        }
    }

    func testFirstPageReadsTitleAbstractThenColumns() {
        let crops = ColumnDetector.crops(page: text.pages[0], lines: text.lines)
        XCTAssertEqual(crops.count, 3)
        let firstWords = crops[0].1.prefix(1).map { text.words[text.lines[$0].wordIDs.lowerBound].text }
        XCTAssertEqual(firstWords, ["Notes"])
    }

    /// The same first page with the abstract's short last line pushed down, the way another text
    /// extractor (PDFKit on the iPhone) can report it. Seen on the simulator: that line came out
    /// alone at column size, followed by a blank crop, before Section 1.
    func testShortLastAbstractLineStaysWithTheAbstract() {
        for push in [CGFloat(4), 9, 14, 30] {
            let page = Self.firstPage(pushingShortAbstractLineBy: push)
            let crops = ColumnDetector.crops(page: page.pages[0], lines: page.lines)
            XCTAssertEqual(crops.count, 3, "push \(push): title and abstract, then two columns")
            let short = page.lines.first { page.words[$0.wordIDs.lowerBound].text == "reader" && $0.page == 0 }!
            XCTAssert(crops[0].1.contains(short.id), "push \(push): the short line is in the abstract's crop")
            XCTAssertEqual(crops[0].0.width, crops.map(\.0.width).max(), "push \(push): first crop is full width")
        }
    }

    /// Page 1 of the test paper with its sixth line (the abstract's short last line) moved down.
    static func firstPage(pushingShortAbstractLineBy push: CGFloat) -> DocumentText {
        let url = Bundle.module.url(forResource: "test-paper", withExtension: "json", subdirectory: "Resources")!
        let raw = try! JSONDecoder().decode(Raw.self, from: Data(contentsOf: url))
        let lines = raw.pages[0].enumerated().map { i, line in
            line.map { w -> (String, CGRect) in
                (w.t, CGRect(x: w.r[0], y: w.r[1] + (i == 6 ? push : 0), width: w.r[2], height: w.r[3]))
            }
        }
        return DocumentText(pageSizes: [CGSize(width: raw.sizes[0][0], height: raw.sizes[0][1])], linesPerPage: [lines])
    }

    func testWideFigureStaysWholeInOneCrop() throws {
        let crops = ColumnDetector.crops(page: text.pages[1], lines: text.lines)
        XCTAssertEqual(crops.count, 5, "columns, caption band with the figure, columns")
        // The figure sits between the upper columns and its caption, across the whole text width.
        let caption = try XCTUnwrap(text.pages[1].lineIDs.first { text.words[text.lines[$0].wordIDs.lowerBound].text == "Figure" })
        let capRect = text.lines[caption].rect
        let probes = [100, 306, 520].map { CGPoint(x: CGFloat($0), y: capRect.minY - 60) }
        let holders = probes.map { p in crops.firstIndex { $0.0.contains(p) } }
        XCTAssertNotNil(holders[0])
        XCTAssertEqual(Set(holders.compactMap { $0 }).count, 1, "one crop holds the whole figure")
        XCTAssertEqual(holders.compactMap { $0 }.count, 3)
    }

    func testEveryLineIsShownOnceInColumns() {
        let layout = ContentLayout(text: text, view: .columns, width: 410)
        let shown = layout.pieces.flatMap(\.lineIDs).sorted()
        XCTAssertEqual(shown, Array(0..<text.lines.count))
    }

    func testFoldKeepsTheLineOnARealPaper() {
        var r = ReaderState(text: text, environment: .duoClosed)
        for y in stride(from: 300.0, to: 3000, by: 377) {
            r.scroll(to: y)
            let pos = r.position!
            for env in [WindowEnvironment.duoOpen, .duoLaptop, .iPadLandscape, .duoClosed] {
                r.setEnvironment(env)
                let rect = r.layout.stripRect(ofLine: text.lines[pos.lineID!])!
                XCTAssertEqual(r.scrollY, rect.minY + pos.fraction * rect.height, accuracy: 0.001)
            }
        }
    }
}
