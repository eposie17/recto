import XCTest
@testable import RectoCore

final class SamePaperTests: XCTestCase {
    let text = Fixture.paper()

    func reader() -> ReaderState {
        var r = ReaderState(text: text, environment: .duoOpen)
        r.scroll(to: 600)
        r.setFacing(.samePaper)
        return r
    }

    func testFacingPageStartsOnTheSameLineThenScrollsOnItsOwn() throws {
        var r = reader()
        let fp = try XCTUnwrap(r.facingPosition)
        XCTAssertEqual(fp.lineID, r.position?.lineID)
        r.scrollFacing(to: 3000)
        XCTAssertNotEqual(r.facingPosition?.lineID, r.position?.lineID, "the paper did not move")
    }

    func testAMarkOnOnePageShowsOnTheOther() throws {
        var r = reader()
        let face = try XCTUnwrap(r.surface.facing)
        // Draw on the Same paper page.
        r.finishStroke([CGPoint(x: face.minX + 60, y: 300), CGPoint(x: face.minX + 160, y: 300)])
        let s = try XCTUnwrap(r.record.marks.pageStrokes.first)
        // It is stored once, on the document, and the paper page can draw it too.
        XCTAssertEqual(r.record.marks.pageStrokes.count, 1)
        XCTAssertNotNil(r.viewport.screenPoint(page: s.page, point: s.points[0]))
        XCTAssertNotNil(r.facingViewport?.screenPoint(page: s.page, point: s.points[0]))
    }

    func testBringHereAndSendThere() throws {
        var r = reader()
        r.scrollFacing(to: 4000)
        r.bringHere()
        XCTAssertEqual(r.facingPosition?.lineID, r.position?.lineID)
        r.scrollFacing(to: 5000)
        let target = try XCTUnwrap(r.facingPosition?.lineID)
        r.sendThere()
        XCTAssertEqual(r.position?.lineID, target)
        XCTAssertTrue(r.canGoBack, "Back returns the paper to where it was")
    }

    func testBothPagesKeepTheirLinesThroughAResize() throws {
        var r = reader()
        r.scrollFacing(to: 2500)
        let paperLine = r.position?.lineID, facingLine = r.facingPosition?.lineID
        r.setEnvironment(.iPadLandscape)
        XCTAssertEqual(r.position?.lineID, paperLine)
        XCTAssertEqual(r.facingPosition?.lineID, facingLine)
        let fl = try XCTUnwrap(r.facingLayout)
        let rect = try XCTUnwrap(fl.stripRect(ofLine: text.lines[facingLine!]))
        XCTAssertEqual(r.facingScrollY, rect.minY + r.facingPosition!.fraction * rect.height, accuracy: 0.01)
    }

    func testFacingPositionIsSaved() throws {
        var r = reader()
        r.scrollFacing(to: 2500)
        let back = try PaperRecord.decode(r.record.encoded())
        XCTAssertEqual(back.facingPosition, r.record.facingPosition)
    }
}
