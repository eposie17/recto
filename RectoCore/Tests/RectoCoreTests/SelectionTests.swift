import XCTest
@testable import RectoCore

final class SelectionTests: XCTestCase {
    let text = Fixture.paper()

    /// Screen point of the middle of a word in the current layout.
    func point(ofWord id: Int, _ r: ReaderState) -> CGPoint {
        let w = text.words[id]
        return r.viewport.screenPoint(page: text.lines[w.lineID].page, point: CGPoint(x: w.rect.midX, y: w.rect.midY))!
    }

    func reader() -> ReaderState {
        var r = ReaderState(text: text, environment: .duoOpen)
        r.scroll(to: 300)
        return r
    }

    func firstVisibleWord(_ r: ReaderState) -> Int {
        text.lines[r.position!.lineID! + 2].wordIDs.lowerBound
    }

    func testDragSelectsTheWordsBetweenItsEnds() {
        var r = reader()
        let a = firstVisibleWord(r)
        r.select(from: point(ofWord: a + 3, r), to: point(ofWord: a, r))
        XCTAssertEqual(r.selection, a...(a + 3), "either direction, reading order")
    }

    func testTapSelectsTheSentence() {
        var r = reader()
        let a = firstVisibleWord(r)
        r.selectSentence(at: point(ofWord: a, r))
        XCTAssertEqual(r.selection, text.sentence(ofWord: a)!.wordIDs)
    }

    func testTapOffThePaperSelectsNothing() {
        var r = reader()
        r.selectSentence(at: CGPoint(x: 700, y: 600)) // the margin, not the paper
        XCTAssertNil(r.selection)
    }

    func testMenuHighlightIsOneUndo() {
        var r = reader()
        let a = firstVisibleWord(r)
        r.select(from: point(ofWord: a, r), to: point(ofWord: a + 2, r))
        r.highlightSelection()
        XCTAssertEqual(r.record.marks.highlights.first?.wordIDs, a...(a + 2))
        XCTAssertNil(r.selection)
        r.undoPaper()
        XCTAssertTrue(r.record.marks.highlights.isEmpty)
    }

    func testQuoteCardJumpsBackToItsPassageAndBackReturns() throws {
        var r = reader()
        let a = firstVisibleWord(r)
        r.select(from: point(ofWord: a, r), to: point(ofWord: a + 4, r))
        r.quoteSelection()
        let card = try XCTUnwrap(r.record.notebook.pages[0].blocks.first)
        guard case let .quote(excerpt, words, pageNumber) = card.kind else { return XCTFail() }
        XCTAssertEqual(words, a...(a + 4))
        XCTAssertEqual(excerpt.split(separator: " ").count, 5)
        XCTAssertEqual(pageNumber, 1)

        r.scroll(to: 5000)
        let far = r.position!
        r.jump(toQuote: card.id)
        let rect = r.layout.stripRect(ofLine: text.lines[text.words[a].lineID])!
        XCTAssert(rect.minY >= r.scrollY && rect.maxY <= r.scrollY + r.surface.paper.height, "passage is on screen")
        XCTAssertTrue(r.canGoBack)
        r.goBack()
        XCTAssertEqual(r.position?.lineID, far.lineID)
        XCTAssertFalse(r.canGoBack)
    }

    func testNotebookInkUndoesAndErases() {
        var r = reader()
        r.finishNotebookStroke(page: 0, points: [CGPoint(x: 50, y: 100), CGPoint(x: 200, y: 100)])
        XCTAssertEqual(r.record.notebook.pages[0].strokes.count, 1)
        r.tool = .eraser
        r.finishNotebookStroke(page: 0, points: [CGPoint(x: 120, y: 104)])
        XCTAssertEqual(r.record.notebook.pages[0].strokes.count, 0, "the eraser hits the middle of a long stroke")
        r.undoNotebook()
        XCTAssertEqual(r.record.notebook.pages[0].strokes.count, 1)
        // Paper history is untouched by notebook edits.
        XCTAssertFalse(r.paperHistory.canUndo)
    }

    func testQuoteCardsGoUnderNotebookInk() {
        var r = reader()
        r.finishNotebookStroke(page: 0, points: [CGPoint(x: 30, y: 20), CGPoint(x: 360, y: 90)])
        r.quote(wordIDs: 10...14)
        XCTAssertGreaterThan(r.record.notebook.pages[0].blocks[0].frame.minY, 90)
    }
}
