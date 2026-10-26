import Foundation

/// Page view shows each printed page at the width of the pane.
/// Columns view crops each printed column and stacks the crops, so the type reads larger
/// and nothing is reflowed.
public enum PaperView: String, Codable, Sendable {
    case page, columns

    /// Columns or Page follows the width of the pane, never the pose.
    public static let columnsBelowWidth: CGFloat = 600

    public static func automatic(forPaneWidth width: CGFloat) -> PaperView {
        width < columnsBelowWidth ? .columns : .page
    }
}

/// One cropped part of a printed page, placed in the scrolling strip.
public struct Piece: Equatable, Sendable {
    public var page: Int
    public var source: CGRect     // page points
    public var origin: CGPoint    // where the crop's top left sits in the strip
    public var scale: CGFloat
    public var lineIDs: [Int]

    public var frame: CGRect {
        CGRect(x: origin.x, y: origin.y, width: source.width * scale, height: source.height * scale)
    }

    public func toStrip(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + (p.x - source.minX) * scale, y: origin.y + (p.y - source.minY) * scale)
    }

    public func toPage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: source.minX + (p.x - origin.x) / scale, y: source.minY + (p.y - origin.y) / scale)
    }

    public func toStrip(_ r: CGRect) -> CGRect {
        let o = toStrip(r.origin)
        return CGRect(x: o.x, y: o.y, width: r.width * scale, height: r.height * scale)
    }
}

/// The paper laid out as one vertical strip of a given width.
/// Strip coordinates: x from 0 at the strip's left edge, y from 0 at the top of the first page.
public struct ContentLayout: Sendable {
    public let view: PaperView
    public let width: CGFloat
    public let pieces: [Piece]
    public let height: CGFloat
    private let pieceOfLine: [Int: Int]

    public static let pageGap: CGFloat = 12
    public static let pieceGap: CGFloat = 6

    public init(text: DocumentText, view: PaperView, width: CGFloat) {
        var pieces: [Piece] = []
        var y: CGFloat = 0
        for (p, page) in text.pages.enumerated() {
            let crops: [(CGRect, [Int])]
            switch view {
            case .page:
                crops = [(CGRect(origin: .zero, size: page.size), page.lineIDs)]
            case .columns:
                crops = ColumnDetector.crops(page: page, lines: text.lines)
            }
            for (i, (source, ids)) in crops.enumerated() {
                let scale = width / source.width
                let piece = Piece(page: p, source: source, origin: CGPoint(x: 0, y: y), scale: scale, lineIDs: ids)
                pieces.append(piece)
                y += piece.frame.height + (i == crops.count - 1 ? ContentLayout.pageGap : ContentLayout.pieceGap)
            }
        }
        var map: [Int: Int] = [:]
        for (i, piece) in pieces.enumerated() { for id in piece.lineIDs { map[id] = i } }
        self.view = view
        self.width = width
        self.pieces = pieces
        self.height = max(0, y - ContentLayout.pageGap)
        self.pieceOfLine = map
    }

    public func piece(ofLine id: Int) -> Piece? {
        pieceOfLine[id].map { pieces[$0] }
    }

    /// Where a text line sits in the strip.
    public func stripRect(ofLine line: TextLine) -> CGRect? {
        piece(ofLine: line.id)?.toStrip(line.rect)
    }

    /// The piece under a strip point, if any.
    public func piece(atStrip p: CGPoint) -> Piece? {
        pieces.first { $0.frame.contains(p) }
    }

    /// The strip position of a point on a printed page.
    public func stripPoint(page: Int, point: CGPoint) -> CGPoint? {
        pieces.first { $0.page == page && $0.source.contains(point) }?.toStrip(point)
    }

    /// The text lines in strip order, each with its strip rect.
    public func linesInOrder(_ text: DocumentText) -> [(TextLine, CGRect)] {
        pieces.flatMap { piece in piece.lineIDs.map { (text.lines[$0], piece.toStrip(text.lines[$0].rect)) } }
    }
}

/// Finds the printed columns on a page from the text line boxes.
public enum ColumnDetector {
    static let pad: CGFloat = 6
    static let figureGap: CGFloat = 36

    /// The x position of the gap between two columns, or nil for a one-column page.
    public static func gapX(page: PageInfo, lines: [TextLine]) -> CGFloat? {
        let rects = page.lineIDs.map { lines[$0].rect }
        guard rects.count >= 6 else { return nil }
        let w = page.size.width
        var best: (x: CGFloat, count: Int)? = nil
        var runStart: CGFloat = 0
        var x = w * 0.3
        while x <= w * 0.7 {
            let c = rects.filter { $0.minX < x && $0.maxX > x }.count
            if best == nil || c < best!.count { best = (x, c); runStart = x }
            else if c == best!.count, x - best!.x <= 1.01 { best!.x = x }
            x += 1
        }
        guard let b = best, CGFloat(b.count) <= CGFloat(rects.count) * 0.15 else { return nil }
        let gap = (runStart + b.x) / 2
        let left = rects.filter { $0.maxX <= gap }.count
        let right = rects.filter { $0.minX >= gap }.count
        return left >= 3 && right >= 3 ? gap : nil
    }

    /// Crops in reading order: full-width bands, and pairs of column crops for two-column bands.
    /// Bands tile the page from the first line to the last, so figures between text are kept.
    public static func crops(page: PageInfo, lines: [TextLine]) -> [(CGRect, [Int])] {
        let ids = page.lineIDs.sorted { lines[$0].rect.minY < lines[$1].rect.minY }
        guard !ids.isEmpty else { return [(CGRect(origin: .zero, size: page.size), [])] }
        guard let gap = gapX(page: page, lines: lines) else {
            let box = ids.reduce(CGRect.null) { $0.union(lines[$1].rect) }
            return [(clamp(box.insetBy(dx: -pad, dy: -pad), page.size), page.lineIDs)]
        }
        // Group lines into bands: spanning lines make full bands, the rest two-column bands.
        var groups: [(spanning: Bool, ids: [Int])] = []
        for (k, id) in ids.enumerated() {
            let r = lines[id].rect
            var spanning = r.minX < gap && r.maxX > gap
            // The short last line of a full-width paragraph (an abstract, a caption) belongs to it:
            // it sits at normal line spacing under a full-width line and nothing follows it closely.
            if !spanning, let last = groups.last, last.spanning,
               r.minY - lines[last.ids[last.ids.count - 1]].rect.maxY < r.height * 0.8 {
                let next = k + 1 < ids.count ? lines[ids[k + 1]].rect : nil
                if next == nil || next!.minY - r.maxY > r.height * 0.8 { spanning = true }
            }
            if let last = groups.last, last.spanning == spanning { groups[groups.count - 1].ids.append(id) }
            else { groups.append((spanning, [id])) }
        }
        let all = ids.reduce(CGRect.null) { $0.union(lines[$1].rect) }
        let minX = max(0, all.minX - pad), maxX = min(page.size.width, all.maxX + pad)
        // A tall stretch with no text in either column is almost always a wide figure or table.
        // Give it its own full-width crop so it is not cut into two column halves.
        var split: [(spanning: Bool, ids: [Int], hole: CGRect?)] = []
        for band in groups {
            guard !band.spanning else { split.append((true, band.ids, nil)); continue }
            var current: [Int] = []
            var coveredTo = -CGFloat.infinity
            for id in band.ids {   // already sorted top to bottom
                let r = lines[id].rect
                if !current.isEmpty, r.minY - coveredTo > figureGap {
                    split.append((false, current, nil))
                    split.append((true, [], CGRect(x: minX, y: coveredTo, width: maxX - minX, height: r.minY - coveredTo)))
                    current = []
                }
                current.append(id)
                coveredTo = max(coveredTo, r.maxY)
            }
            split.append((false, current, nil))
        }
        let bands = split.map { (spanning: $0.spanning, ids: $0.ids) }
        var out: [(CGRect, [Int])] = []
        let boxes = split.map { b in b.hole ?? b.ids.reduce(CGRect.null) { $0.union(lines[$1].rect) } }
        // Bands meet so that the empty space between them (usually a figure) goes to the
        // full-width band, and a wide figure is never cut into two column halves.
        func boundary(_ upper: Int) -> CGFloat {
            bands[upper].spanning ? boxes[upper + 1].minY - pad : boxes[upper].maxY + pad
        }
        for (i, band) in bands.enumerated() {
            let box = boxes[i]
            let top = i == 0 ? max(0, box.minY - pad) : boundary(i - 1)
            let bottom = i == bands.count - 1 ? min(page.size.height, box.maxY + pad) : boundary(i)
            // Keep reading order inside the band as the PDF gave it.
            let ordered = band.ids.sorted()
            if band.spanning {
                out.append((CGRect(x: minX, y: top, width: maxX - minX, height: bottom - top), ordered))
            } else {
                let left = ordered.filter { lines[$0].rect.maxX <= gap }
                let right = ordered.filter { lines[$0].rect.minX >= gap }
                if !left.isEmpty { out.append((CGRect(x: minX, y: top, width: gap - minX, height: bottom - top), left)) }
                if !right.isEmpty { out.append((CGRect(x: gap, y: top, width: maxX - gap, height: bottom - top), right)) }
            }
        }
        return out
    }

    static func clamp(_ r: CGRect, _ size: CGSize) -> CGRect {
        r.intersection(CGRect(origin: .zero, size: size))
    }
}
