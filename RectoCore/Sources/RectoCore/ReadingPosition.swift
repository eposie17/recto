import Foundation

/// Where the reader is. Never a scroll distance, so it survives a fold, a resize, and Page/Columns switches.
///
/// Two layers: the text line under the top of the pane (with how far into it the top sits), and
/// a plain place on the printed page. The page place is the fallback for scanned pages with no
/// text, and for when the saved line no longer matches the file (the PDF was replaced).
public struct ReadingPosition: Codable, Equatable, Sendable {
    public var sentenceID: Int?
    public var lineID: Int?
    /// The words of that line, to check it is still the same line when the paper is reopened.
    public var lineText: String?
    /// 0 = top of the line at the top of the pane, 1 = bottom of the line.
    public var fraction: CGFloat
    public var page: Int
    /// Page points from the top of the printed page.
    public var pageY: CGFloat

    public init(sentenceID: Int?, lineID: Int?, lineText: String?, fraction: CGFloat, page: Int, pageY: CGFloat) {
        self.sentenceID = sentenceID; self.lineID = lineID; self.lineText = lineText
        self.fraction = fraction; self.page = page; self.pageY = pageY
    }

    /// Read the position from a strip scrolled so that `scrollY` is at the top of the pane.
    public static func capture(text: DocumentText, layout: ContentLayout, scrollY: CGFloat) -> ReadingPosition? {
        guard !layout.pieces.isEmpty else { return nil }
        // The page place: the piece at the top of the pane, or the next one down.
        let piece = layout.pieces.first { $0.frame.maxY > scrollY } ?? layout.pieces[layout.pieces.count - 1]
        let pageY = piece.toPage(CGPoint(x: 0, y: max(scrollY, piece.frame.minY))).y

        // The text line: the first line whose bottom is below the top of the pane, if the paper has text.
        let lines = layout.linesInOrder(text)
        guard let (line, rect) = lines.first(where: { $0.1.maxY > scrollY }) ?? lines.last else {
            return ReadingPosition(sentenceID: nil, lineID: nil, lineText: nil, fraction: 0, page: piece.page, pageY: pageY)
        }
        let f = rect.height > 0 ? (scrollY - rect.minY) / rect.height : 0
        return ReadingPosition(sentenceID: text.sentence(ofLine: line.id)?.id, lineID: line.id,
                               lineText: text.lineText(line.id), fraction: f, page: piece.page, pageY: pageY)
    }

    /// The saved line, if it is still there and still says the same thing.
    func validLine(in text: DocumentText) -> TextLine? {
        guard let id = lineID, id >= 0, id < text.lines.count else { return nil }
        if let saved = lineText, saved != text.lineText(id) { return nil }
        return text.lines[id]
    }

    /// The scroll distance that puts this position at the top of the pane in `layout`.
    public func scrollY(text: DocumentText, layout: ContentLayout) -> CGFloat? {
        if let line = validLine(in: text), let rect = layout.stripRect(ofLine: line) {
            return rect.minY + fraction * rect.height
        }
        return pageScrollY(layout: layout)
    }

    /// The fallback: the same place on the printed page.
    public func pageScrollY(layout: ContentLayout) -> CGFloat? {
        let onPage = layout.pieces.filter { $0.page == page }
        guard !onPage.isEmpty else { return nil }
        // The piece covering that height, else the first piece below it, else the page's last piece.
        let piece = onPage.first { $0.source.minY <= pageY && $0.source.maxY > pageY }
            ?? onPage.first { $0.source.minY > pageY } ?? onPage[onPage.count - 1]
        let y = min(max(pageY, piece.source.minY), piece.source.maxY)
        return piece.toStrip(CGPoint(x: piece.source.minX, y: y)).y
    }
}

extension DocumentText {
    public func lineText(_ id: Int) -> String {
        lines[id].wordIDs.map { words[$0].text }.joined(separator: " ")
    }
}
