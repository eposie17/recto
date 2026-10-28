import XCTest
@testable import RectoCore

final class ReadingLineTests: XCTestCase {
    let text = Fixture.paper()

    /// The saved line really is at the top of the pane in the current layout.
    func assertLineAtTop(_ r: ReaderState, _ pos: ReadingPosition, file: StaticString = #filePath, line: UInt = #line) {
        let rect = r.layout.stripRect(ofLine: text.lines[pos.lineID!])!
        let expected = rect.minY + pos.fraction * rect.height
        XCTAssertEqual(r.scrollY, max(0, expected), accuracy: 0.001, file: file, line: line)
        // And the line is on screen.
        XCTAssert(rect.maxY > r.scrollY && rect.minY < r.scrollY + r.surface.paper.height, file: file, line: line)
    }

    func testFoldingKeepsTheLine() {
        var r = ReaderState(text: text, environment: .duoClosed)
        r.scroll(to: 1234.5)
        let before = r.position!
        for env in [WindowEnvironment.duoOpen, .duoLaptop, .duoSplitLeft, .iPadLandscape, .iPadPortrait, .duoClosed] {
            r.setEnvironment(env)
            let now = r.position!
            XCTAssertEqual(now.lineID, before.lineID, "\(env.size)")
            XCTAssertEqual(now.fraction, before.fraction, accuracy: 0.001, "\(env.size)")
            assertLineAtTop(r, before)
        }
    }

    func testPageAndColumnsSwitchKeepsTheLine() {
        var r = ReaderState(text: text, environment: .duoOpen)
        r.scroll(to: 2000)
        let before = r.position!
        r.setView(.page)
        XCTAssertEqual(r.position!.lineID, before.lineID)
        assertLineAtTop(r, before)
        r.setView(.columns)
        assertLineAtTop(r, before)
        XCTAssertEqual(r.position!.lineID, before.lineID)
        XCTAssertEqual(r.position!.fraction, before.fraction, accuracy: 0.001)
    }

    func testThreeHundredRandomChangesNeverLoseTheLine() {
        var rng = SystemRandomNumberGenerator()
        var r = ReaderState(text: text, environment: .duoClosed)
        let envs: [WindowEnvironment] = [.duoClosed, .duoOpen, .duoLaptop, .duoSplitLeft, .iPadLandscape, .iPadPortrait, .iPhone]
        for _ in 0..<300 {
            switch Int.random(in: 0..<5, using: &rng) {
            case 0: r.scroll(to: CGFloat.random(in: 0...r.layout.height, using: &rng))
            case 1: r.setEnvironment(envs.randomElement(using: &rng)!)
            case 2: r.setBandOpen(Bool.random(using: &rng))
            case 3: r.swapSides()
            default: r.setView([PaperView.page, .columns, nil].randomElement(using: &rng)!)
            }
            if let saved = r.record.position, r.scrollY > 0 { assertLineAtTop(r, saved) }
        }
    }
}

final class MarginInkTests: XCTestCase {
    let text = Fixture.paper()

    func openReader() -> ReaderState {
        var r = ReaderState(text: text, environment: .duoOpen)
        r.scroll(to: 400)
        return r
    }

    func testOneStrokeCrossesFromThePaperOverTheCreaseOntoTheNotes() throws {
        var r = openReader()
        let pts = stride(from: 380.0, through: 700.0, by: 10.0).map { CGPoint(x: $0, y: 300) }
        r.finishStroke(pts)
        XCTAssertEqual(r.record.marks.pageStrokes.count, 1)
        XCTAssertEqual(r.record.marks.marginStrokes.count, 1)
        let page = r.record.marks.pageStrokes[0], margin = r.record.marks.marginStrokes[0]
        XCTAssertEqual(page.group, margin.group)
        // The two parts meet on the page edge with no gap.
        let vp = r.viewport
        let a = try XCTUnwrap(vp.screenPoint(page: page.page, point: page.points.last!))
        let b = try XCTUnwrap(vp.screenPoint(margin.points.first!, line: margin.lineID, side: margin.side))
        XCTAssertEqual(a.x, b.x, accuracy: 0.01)
        XCTAssertEqual(a.y, b.y, accuracy: 0.01)
        // And the margin part lands where it was drawn.
        let end = try XCTUnwrap(vp.screenPoint(margin.points.last!, line: margin.lineID, side: margin.side))
        XCTAssertEqual(end.x, 700, accuracy: 0.01)
        XCTAssertEqual(end.y, 300, accuracy: 0.01)
    }

    func testTheCreaseTakesInk() {
        var r = openReader()
        let x = WindowEnvironment.duoOpen.fold!.midX
        r.finishStroke([CGPoint(x: x, y: 200), CGPoint(x: x, y: 260)])
        XCTAssertEqual(r.record.marks.marginStrokes.count, 1)
        XCTAssertEqual(InputRules.decide(kind: .finger, start: CGPoint(x: x, y: 200), writeMode: true,
                                         environment: .duoOpen), .ink)
    }

    func testMarginInkStaysWithItsLineThroughAFold() throws {
        var r = openReader()
        r.finishStroke([CGPoint(x: 600, y: 300), CGPoint(x: 640, y: 310)])
        let s = r.record.marks.marginStrokes[0]
        func offsetFromLine(_ r: ReaderState) throws -> CGFloat {
            let vp = r.viewport
            let p = try XCTUnwrap(vp.screenPoint(s.points[0], line: s.lineID, side: s.side))
            let line = try XCTUnwrap(vp.layout.stripRect(ofLine: text.lines[s.lineID]))
            return p.y - vp.toScreen(strip: CGPoint(x: 0, y: line.minY)).y
        }
        let before = try offsetFromLine(r)
        r.setEnvironment(.iPadLandscape)
        XCTAssertEqual(try offsetFromLine(r), before, accuracy: 0.001)
    }

    func testSwapSidesLeavesNotesInTheirMarginAndShowsInkTabs() {
        var r = openReader()
        r.finishStroke([CGPoint(x: 600, y: 300), CGPoint(x: 640, y: 310)])
        XCTAssertEqual(r.inkTabs.count, 0)
        r.swapSides()
        XCTAssertEqual(r.record.marks.marginStrokes[0].side, .right, "notes stay in the margin they were written in")
        XCTAssertEqual(r.surface.shownMarginSide, .left)
        XCTAssertEqual(r.inkTabs.map(\.kind), [.ink])
        XCTAssertEqual(r.inkTabs.first?.side, .right)
        r.swapSides()
        XCTAssertEqual(r.inkTabs.count, 0)
    }

    func testBandShowsAMoreTabForInkPastItsEdge() {
        var r = openReader()
        r.finishStroke([CGPoint(x: 600, y: 300), CGPoint(x: 800, y: 310)])
        r.setEnvironment(.duoClosed)
        XCTAssertEqual(r.inkTabs.map(\.kind), [.ink], "band closed: the margin is hidden")
        r.setBandOpen(true)
        XCTAssertEqual(r.inkTabs.map(\.kind), [.more], "band open: ink runs past it")
    }

    func testCloseTabsMerge() {
        var r = openReader()
        for y in stride(from: 200.0, through: 230.0, by: 10.0) {
            r.finishStroke([CGPoint(x: 600, y: y), CGPoint(x: 620, y: y)])
        }
        r.swapSides()
        XCTAssertEqual(r.inkTabs.count, 1)
        XCTAssertEqual(r.inkTabs.first?.strokeCount, 4)
    }
}

final class PenRulesTests: XCTestCase {
    func testPencilAlwaysInks() {
        XCTAssertEqual(InputRules.decide(kind: .pencil, start: CGPoint(x: 2, y: 2), writeMode: false, environment: .duoClosed), .ink)
    }

    func testFingerScrollsUnlessWriting() {
        XCTAssertEqual(InputRules.decide(kind: .finger, start: CGPoint(x: 200, y: 300), writeMode: false, environment: .duoClosed), .scroll)
        XCTAssertEqual(InputRules.decide(kind: .finger, start: CGPoint(x: 200, y: 300), writeMode: true, environment: .duoClosed), .ink)
    }

    func testGripEdgeOnlyAtTheScreensRealEdges() {
        XCTAssertEqual(InputRules.decide(kind: .finger, start: CGPoint(x: 10, y: 300), writeMode: true, environment: .duoClosed), .ignore)
        // In a Split View pane the inner edge of the window is not a screen edge.
        XCTAssertEqual(InputRules.decide(kind: .finger, start: CGPoint(x: 460, y: 300), writeMode: true, environment: .duoSplitLeft), .ink)
    }
}

final class UndoTests: XCTestCase {
    let text = Fixture.paper()

    func testUndoTakesBackAWholePenMovementAcrossTheFold() {
        var r = ReaderState(text: text, environment: .duoOpen)
        r.finishStroke([CGPoint(x: 400, y: 300), CGPoint(x: 600, y: 300)])
        XCTAssertEqual(r.record.marks.all.count, 2)
        r.undoPaper()
        XCTAssertEqual(r.record.marks.all.count, 0)
        r.redoPaper()
        XCTAssertEqual(r.record.marks.all.count, 2)
    }

    func testOneEraserPassIsOneUndo() {
        var r = ReaderState(text: text, environment: .duoOpen)
        r.tool = .highlighter
        let lineRect = r.viewport.layout.stripRect(ofLine: text.lines[5])!
        let y = r.viewport.toScreen(strip: CGPoint(x: 0, y: lineRect.midY)).y
        r.finishStroke([CGPoint(x: 20, y: y), CGPoint(x: 200, y: y)])
        r.tool = .pen
        r.finishStroke([CGPoint(x: 100, y: y + 2), CGPoint(x: 140, y: y + 2)])
        XCTAssertEqual(r.record.marks.highlights.count, 1)
        XCTAssertEqual(r.record.marks.pageStrokes.count, 1)
        r.tool = .eraser
        r.finishStroke([CGPoint(x: 120, y: y)])
        XCTAssertEqual(r.record.marks.all.count, 0)
        r.undoPaper()
        XCTAssertEqual(r.record.marks.highlights.count, 1)
        XCTAssertEqual(r.record.marks.pageStrokes.count, 1)
    }

    func testPaperAndNotebookKeepSeparateHistories() {
        var r = ReaderState(text: text, environment: .duoOpen)
        r.finishStroke([CGPoint(x: 100, y: 300), CGPoint(x: 140, y: 300)])
        r.quote(wordIDs: 10...15)
        r.undoPaper()
        XCTAssertEqual(r.record.marks.all.count, 0)
        XCTAssertEqual(r.record.notebook.pages[0].blocks.count, 1)
        r.undoNotebook()
        XCTAssertEqual(r.record.notebook.pages[0].blocks.count, 0)
    }
}

final class HighlighterTests: XCTestCase {
    let text = Fixture.paper()

    func testSnapsToTheWordsItCrosses() throws {
        let line = text.lines[4]
        let first = text.words[line.wordIDs.lowerBound].rect, third = text.words[line.wordIDs.lowerBound + 2].rect
        let range = try XCTUnwrap(Highlighter.snap(points: [CGPoint(x: first.midX, y: first.midY), CGPoint(x: third.midX, y: third.midY)],
                                                   page: 0, text: text))
        XCTAssertEqual(range, line.wordIDs.lowerBound...(line.wordIDs.lowerBound + 2))
        // The same words chosen from the menu make the same highlight.
        let fromMenu = Highlight(wordIDs: range, color: .blue)
        XCTAssertEqual(Highlighter.rects(for: fromMenu, text: text).count, 1)
    }

    func testMissesEmptySpace() {
        XCTAssertNil(Highlighter.snap(points: [CGPoint(x: 5, y: 5), CGPoint(x: 20, y: 5)], page: 0, text: text))
    }
}

final class NotebookTests: XCTestCase {
    func testQuoteCardsTakeTheNextFreeSlotAndNothingMoves() {
        var nb = Notebook()
        nb.apply(Edit(added: [.stroke(page: 0, NotebookStroke(points: [CGPoint(x: 50, y: 30), CGPoint(x: 300, y: 60)], color: .black, width: 2))]))
        _ = nb.addQuote(excerpt: "one", wordIDs: 0...1, pageNumber: 1)
        let card = nb.pages[0].blocks[0].frame
        XCTAssertGreaterThan(card.minY, 60, "the card goes under the ink, not over it")
        var count = 1
        while nb.pages.count == 1 { _ = nb.addQuote(excerpt: "more", wordIDs: 0...1, pageNumber: 1); count += 1 }
        XCTAssertEqual(nb.pages[0].blocks[0].frame, card)
        XCTAssertEqual(nb.pages[1].blocks.count, 1)
        XCTAssertGreaterThan(count, 4)
    }
}

final class StoreTests: XCTestCase {
    func testSavesAndLoadsEverything() throws {
        let text = Fixture.paper()
        var r = ReaderState(text: text, environment: .duoOpen)
        r.scroll(to: 900)
        r.finishStroke([CGPoint(x: 400, y: 300), CGPoint(x: 600, y: 320)])
        r.quote(wordIDs: 3...8)
        r.swapSides()
        let data = try r.record.encoded()
        let back = try PaperRecord.decode(data)
        XCTAssertEqual(back, r.record)
        let reopened = ReaderState(text: text, record: back, environment: .duoClosed)
        XCTAssertEqual(reopened.position?.lineID, r.record.position?.lineID)
        XCTAssertEqual(reopened.settings.notesSide, .left)
    }

    func testRefusesAFileFromANewerVersion() throws {
        var rec = PaperRecord(); rec.version = 99
        XCTAssertThrowsError(try PaperRecord.decode(rec.encoded()))
    }
}

final class ReadingFallbackTests: XCTestCase {
    /// A scanned paper: pages but no text layer.
    func testScannedPaperKeepsItsPlaceByPage() throws {
        let scan = DocumentText(pageSizes: Array(repeating: Fixture.pageSize, count: 4), linesPerPage: [])
        var r = ReaderState(text: scan, environment: .duoClosed)
        r.scroll(to: 1500)
        let pos = try XCTUnwrap(r.position)
        XCTAssertNil(pos.lineID)
        let before = pos.pageY
        for env in [WindowEnvironment.duoOpen, .iPadLandscape, .duoLaptop, .duoClosed] {
            r.setEnvironment(env)
            // Same place on the same printed page.
            let piece = try XCTUnwrap(r.layout.pieces.first { $0.page == pos.page })
            XCTAssertEqual(piece.toPage(CGPoint(x: 0, y: r.scrollY)).y, before, accuracy: 0.01, "\(env.size)")
        }
    }

    /// The PDF was replaced by a different one: the saved line no longer matches, so use the page place.
    func testChangedFileFallsBackToThePage() throws {
        let text = Fixture.paper()
        var r = ReaderState(text: text, environment: .duoOpen)
        r.scroll(to: 1800)
        var record = r.record
        record.position?.lineText = "words that are not there any more"
        let reopened = ReaderState(text: text, record: record, environment: .duoOpen)
        let pos = try XCTUnwrap(record.position)
        XCTAssertEqual(reopened.scrollY, try XCTUnwrap(pos.pageScrollY(layout: reopened.layout)), accuracy: 0.01)
        // And it lands on the right page.
        XCTAssertEqual(reopened.layout.piece(atStrip: CGPoint(x: 1, y: reopened.scrollY + 1))?.page, pos.page)
    }
}
