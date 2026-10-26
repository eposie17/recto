import XCTest
@testable import RectoCore

final class ColumnsTests: XCTestCase {
    let text = Fixture.paper()

    func testFindsTheGapBetweenColumns() throws {
        let gap = try XCTUnwrap(ColumnDetector.gapX(page: text.pages[0], lines: text.lines))
        XCTAssert(gap > 300 && gap < 312, "gap at \(gap)")
    }

    func testCropsTitleThenLeftThenRight() {
        let crops = ColumnDetector.crops(page: text.pages[0], lines: text.lines)
        XCTAssertEqual(crops.count, 3)
        XCTAssertEqual(crops[0].1, [0, 1])               // the title band
        XCTAssert(crops[1].0.maxX < crops[2].0.minX + 1)   // left column, then right column
        // Every line is in exactly one crop.
        XCTAssertEqual(crops.flatMap(\.1).sorted(), text.pages[0].lineIDs)
    }

    func testColumnsReadAboutOnePointEightTimesLarger() {
        let width: CGFloat = 466 - Surface.sideBarWidth
        let page = ContentLayout(text: text, view: .page, width: width)
        let cols = ContentLayout(text: text, view: .columns, width: width)
        let line = text.lines[10]
        let a = try! XCTUnwrap(page.stripRect(ofLine: line)), b = try! XCTUnwrap(cols.stripRect(ofLine: line))
        let ratio = b.height / a.height
        // Against the whole printed page (with its white margins) a column reads about 2.4 times larger.
        XCTAssert(ratio > 1.8 && ratio < 2.6, "ratio \(ratio)")
    }

    func testOneColumnPageIsOneCrop() {
        let lines = (0..<20).map { i in Fixture.line(x0: 72, x1: 540, y: 80 + CGFloat(i) * 14, words: ["one", "wide", "line."]) }
        let t = DocumentText(pageSizes: [Fixture.pageSize], linesPerPage: [lines])
        XCTAssertNil(ColumnDetector.gapX(page: t.pages[0], lines: t.lines))
        XCTAssertEqual(ColumnDetector.crops(page: t.pages[0], lines: t.lines).count, 1)
    }

    func testSentencesSkipAbbreviations() {
        // "Fig." must not end a sentence; "end." does.
        let s = text.sentence(ofWord: 0)!
        XCTAssertEqual(text.words[s.wordIDs.upperBound].text, "Pages.")
        for sentence in text.sentences.dropLast() {
            XCTAssertNotEqual(text.words[sentence.wordIDs.upperBound].text, "Fig.")
        }
    }
}

final class SurfaceTests: XCTestCase {
    func testClosedPhoneShowsFullSizeTextWithTheBandOff() {
        let s = Surface(environment: .duoClosed, settings: LayoutSettings())
        XCTAssertEqual(s.arrangement, .single)
        XCTAssertEqual(s.paper.width, 466 - Surface.sideBarWidth)
        XCTAssertNil(s.margin)
        XCTAssertEqual(s.view, .columns)
    }

    func testBandShrinksThePageToAbout78Percent() {
        var set = LayoutSettings(); set.bandOpen = true
        let s = Surface(environment: .duoClosed, settings: set)
        let area = 466 - Surface.sideBarWidth
        XCTAssertEqual(s.paper.width, (area * 0.78).rounded())
        guard case let .beside(side, edgeX, visible, _)? = s.margin else { return XCTFail("no band") }
        XCTAssertEqual(side, .right)
        XCTAssertEqual(edgeX, s.paper.maxX)
        XCTAssertEqual(visible, area - s.paper.width)
    }

    func testOpenFlatMarginRunsOverTheCreaseOntoTheFacingPage() {
        let s = Surface(environment: .duoOpen, settings: LayoutSettings())
        XCTAssertEqual(s.arrangement, .sideBySide)
        let fold = WindowEnvironment.duoOpen.fold!
        XCTAssertEqual(s.paper.maxX, fold.minX)
        guard case let .beside(_, edgeX, visible, frame)? = s.margin else { return XCTFail("no margin") }
        XCTAssertEqual(edgeX, fold.minX)
        XCTAssert(frame.contains(CGPoint(x: fold.midX, y: 300)), "crease is part of the margin")
        XCTAssertEqual(visible, 951 - fold.minX)
        XCTAssertEqual(s.view, .columns) // each open half is under 600 points
    }

    func testSwapSidesPutsThePaperOnTheRight() {
        var set = LayoutSettings(); set.notesSide = .left
        let s = Surface(environment: .duoOpen, settings: set)
        XCTAssertEqual(s.paper.minX, WindowEnvironment.duoOpen.fold!.maxX)
        XCTAssertEqual(s.shownMarginSide, .left)
    }

    func testLaptopShowsWholeMarginBelowAndPageViewOnTop() {
        let s = Surface(environment: .duoLaptop, settings: LayoutSettings())
        XCTAssertEqual(s.arrangement, .stacked)
        XCTAssertEqual(s.view, .page)
        guard case let .whole(_, frame, _, _)? = s.margin else { return XCTFail("no whole margin") }
        XCTAssertEqual(frame.minY, WindowEnvironment.duoLaptop.fold!.maxY)
    }

    func testIPadDrawsThePaperLargerSoTheMarginFillsTheNotesPage() {
        let s = Surface(environment: .iPadLandscape, settings: LayoutSettings())
        XCTAssertEqual(s.arrangement, .sideBySide)
        XCTAssertEqual(s.paper.width, 1180 - 520)
        XCTAssertEqual(s.view, .page)
        guard case let .beside(_, _, visible, _)? = s.margin else { return XCTFail() }
        XCTAssertEqual(visible, 520)
    }

    func testSplitViewIsOnePageWithTheBarAwayFromTheFold() {
        let s = Surface(environment: .duoSplitLeft, settings: LayoutSettings())
        XCTAssertEqual(s.arrangement, .single)
        XCTAssertEqual(s.sideBar?.minX, 0)
    }

    func testNotebookPageNeverChangesSizeBetweenPocketAndDesk() {
        var set = LayoutSettings(); set.facing = .notebook; set.singleShows = .notes
        for env in [WindowEnvironment.duoClosed, .duoOpen, .duoSplitLeft, .iPadLandscape] {
            let s = Surface(environment: env, settings: set)
            XCTAssertEqual(s.notebookPage?.size, Surface.notebookPage, "\(env.size)")
        }
        // A narrower pane shows it smaller, never reflowed.
        let narrow = Surface(environment: .iPhone, settings: set)
        XCTAssertLessThan(narrow.notebookScale, 1)
    }
}
