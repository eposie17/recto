import Foundation

/// Where the reader is: the line under the top of the pane and how far into it the top sits.
/// Never a scroll distance, so it survives a fold, a resize, and Page/Columns switches.
public struct ReadingPosition: Codable, Equatable, Sendable {
    public var sentenceID: Int
    public var lineID: Int
    /// 0 = top of the line at the top of the pane, 1 = bottom of the line.
    public var fraction: CGFloat

    public init(sentenceID: Int, lineID: Int, fraction: CGFloat) {
        self.sentenceID = sentenceID; self.lineID = lineID; self.fraction = fraction
    }

    /// Read the position from a strip scrolled so that `scrollY` is at the top of the pane.
    public static func capture(text: DocumentText, layout: ContentLayout, scrollY: CGFloat) -> ReadingPosition? {
        let lines = layout.linesInOrder(text)
        guard !lines.isEmpty else { return nil }
        // The first line whose bottom is below the top of the pane.
        let hit = lines.first { $0.1.maxY > scrollY } ?? lines[lines.count - 1]
        let (line, rect) = hit
        let f = rect.height > 0 ? (scrollY - rect.minY) / rect.height : 0
        let sentence = text.sentence(ofLine: line.id)?.id ?? 0
        return ReadingPosition(sentenceID: sentence, lineID: line.id, fraction: f)
    }

    /// The scroll distance that puts this position at the top of the pane in `layout`.
    public func scrollY(text: DocumentText, layout: ContentLayout) -> CGFloat? {
        guard lineID < text.lines.count, let rect = layout.stripRect(ofLine: text.lines[lineID]) else { return nil }
        return rect.minY + fraction * rect.height
    }

    /// Same, but with the top of the pane on the start of the line, so the paper opens on a whole line.
    public func wholeLineScrollY(text: DocumentText, layout: ContentLayout, lead: CGFloat = 8) -> CGFloat? {
        guard lineID < text.lines.count, let rect = layout.stripRect(ofLine: text.lines[lineID]) else { return nil }
        return max(0, rect.minY - lead)
    }
}
