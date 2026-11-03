import Foundation
import CoreGraphics

/// A view of the paper: the strip layout, where it sits on screen and how far it is scrolled.
public struct PaperViewport: Sendable {
    public var text: DocumentText
    public var layout: ContentLayout
    public var surface: Surface
    public var scrollY: CGFloat

    public init(text: DocumentText, layout: ContentLayout, surface: Surface, scrollY: CGFloat) {
        self.text = text; self.layout = layout; self.surface = surface; self.scrollY = scrollY
    }

    public func toStrip(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - surface.paper.minX, y: p.y - surface.paper.minY + scrollY)
    }

    public func toScreen(strip p: CGPoint) -> CGPoint {
        CGPoint(x: p.x + surface.paper.minX, y: p.y + surface.paper.minY - scrollY)
    }

    /// What lies under a screen point.
    public enum Spot: Equatable, Sendable {
        case page(page: Int, point: CGPoint, piece: Int)
        case margin(side: MarginSide, across: CGFloat, stripY: CGFloat)
        case none
    }

    public func spot(at p: CGPoint) -> Spot {
        if surface.paper.contains(p) {
            let s = toStrip(p)
            if let i = layout.pieces.firstIndex(where: { $0.frame.contains(s) }) {
                return .page(page: layout.pieces[i].page, point: layout.pieces[i].toPage(s), piece: i)
            }
            return .none
        }
        if case let .beside(side, edgeX, visible, frame)? = surface.margin, frame.contains(p) {
            let across = side == .right ? p.x - edgeX : edgeX - p.x
            guard across >= 0, across <= visible else { return .none }
            return .margin(side: side, across: across, stripY: toStrip(p).y)
        }
        return .none
    }

    /// The line a margin point belongs to: the last line that starts at or above it.
    public func anchorLine(stripY: CGFloat) -> (TextLine, CGRect)? {
        let lines = layout.linesInOrder(text)
        guard !lines.isEmpty else { return nil }
        var best = lines[0]
        for l in lines where l.1.minY <= stripY { best = l }
        return best
    }

    /// Screen point of a margin point, if that margin is shown beside the paper.
    public func screenPoint(_ m: MarginPoint, line: Int, side: MarginSide) -> CGPoint? {
        guard case let .beside(shown, edgeX, _, _)? = surface.margin, shown == side,
              line < text.lines.count, let rect = layout.stripRect(ofLine: text.lines[line]) else { return nil }
        let x = side == .right ? edgeX + m.across : edgeX - m.across
        return CGPoint(x: x, y: rect.minY + m.down + surface.paper.minY - scrollY)
    }

    public func screenPoint(page: Int, point: CGPoint) -> CGPoint? {
        layout.stripPoint(page: page, point: point).map { toScreen(strip: $0) }
    }
}

/// Turns one pen movement on screen into marks. A stroke that runs from the paper onto the margin
/// is cut at the page edge into a page part and a margin part that share a group, with a shared
/// point on the edge so they join without a gap.
public enum InkRouter {
    public static func route(screenPoints pts: [CGPoint], in vp: PaperViewport,
                             color: InkColor, width: CGFloat, group: UUID = UUID()) -> [Mark] {
        enum Key: Equatable { case piece(Int), margin(MarginSide), none }
        func key(_ s: PaperViewport.Spot) -> Key {
            switch s {
            case .page(_, _, let i): return .piece(i)
            case .margin(let side, _, _): return .margin(side)
            case .none: return .none
            }
        }

        var runs: [(Key, [CGPoint])] = []
        var prev: CGPoint? = nil
        var prevKey: Key = .none
        for p in pts {
            let k = key(vp.spot(at: p))
            if let q = prev, k != prevKey, let edge = edgeCrossing(from: q, to: p, vp: vp) {
                // Share the point on the page edge between the two runs.
                if !runs.isEmpty, runs[runs.count - 1].0 == prevKey { runs[runs.count - 1].1.append(edge) }
                runs.append((k, [edge, p]))
            } else if let last = runs.last, last.0 == k {
                runs[runs.count - 1].1.append(p)
            } else {
                runs.append((k, [p]))
            }
            prev = p; prevKey = k
        }

        var marks: [Mark] = []
        for (k, run) in runs {
            switch k {
            case .none:
                continue
            case .piece(let i):
                let piece = vp.layout.pieces[i]
                let points = run.map { piece.toPage(vp.toStrip($0)) }
                marks.append(.page(PageStroke(group: group, page: piece.page, points: points, color: color, width: width)))
            case .margin(let side):
                guard case let .beside(_, edgeX, _, _)? = vp.surface.margin,
                      let (line, rect) = vp.anchorLine(stripY: vp.toStrip(run[0]).y) else { continue }
                let points = run.map { p -> MarginPoint in
                    let across = side == .right ? p.x - edgeX : edgeX - p.x
                    return MarginPoint(across: max(0, across), down: vp.toStrip(p).y - rect.minY)
                }
                marks.append(.margin(MarginStroke(group: group, side: side, lineID: line.id, points: points,
                                                  color: color, width: width)))
            }
        }
        return marks
    }

    /// The point where a segment meets the page edge, when it crosses between the page and the margin.
    static func edgeCrossing(from a: CGPoint, to b: CGPoint, vp: PaperViewport) -> CGPoint? {
        guard case let .beside(side, edgeX, _, _)? = vp.surface.margin else { return nil }
        let aIn = vp.surface.paper.contains(a), bIn = vp.surface.paper.contains(b)
        guard aIn != bIn, b.x != a.x else { return nil }
        let t = (edgeX - a.x) / (b.x - a.x)
        guard t >= 0, t <= 1 else { return nil }
        // Nudge onto the paper side by a hair so the page part keeps it.
        let x = side == .right ? edgeX - 0.001 : edgeX + 0.001
        return CGPoint(x: x, y: a.y + t * (b.y - a.y))
    }
}

/// Tabs at the page edge for ink the current view does not show.
public struct InkTab: Equatable, Sendable {
    public enum Kind: String, Sendable { case more, ink }
    public var kind: Kind
    public var side: MarginSide
    public var screenY: CGFloat
    public var strokeCount: Int
}

public enum InkTabs {
    public static let mergeDistance: CGFloat = 44

    /// "more" for ink past the edge of a thin band; "ink" for ink in a margin that is not shown.
    public static func tabs(marks: PaperMarks, in vp: PaperViewport) -> [InkTab] {
        var raw: [InkTab] = []
        for s in marks.marginStrokes {
            guard s.lineID < vp.text.lines.count,
                  let rect = vp.layout.stripRect(ofLine: vp.text.lines[s.lineID]) else { continue }
            let y = rect.minY + (s.points.first?.down ?? 0) + vp.surface.paper.minY - vp.scrollY
            switch vp.surface.margin {
            case let .beside(side, _, visible, _)? where side == s.side:
                if s.points.contains(where: { $0.across > visible }) {
                    raw.append(InkTab(kind: .more, side: side, screenY: y, strokeCount: 1))
                }
            case .whole(let side, _, _, _)? where side == s.side:
                continue
            default:
                raw.append(InkTab(kind: .ink, side: s.side, screenY: y, strokeCount: 1))
            }
        }
        raw.sort { ($0.side.rawValue, $0.kind.rawValue, $0.screenY) < ($1.side.rawValue, $1.kind.rawValue, $1.screenY) }
        var merged: [InkTab] = []
        for t in raw {
            if let last = merged.last, last.side == t.side, last.kind == t.kind,
               t.screenY - last.screenY < mergeDistance {
                merged[merged.count - 1].strokeCount += 1
            } else {
                merged.append(t)
            }
        }
        return merged
    }
}

public enum Highlighter {
    /// The run of words a highlighter stroke crosses on one page, or nil if it crosses none.
    public static func snap(points: [CGPoint], page: Int, text: DocumentText, tolerance: CGFloat = 2) -> ClosedRange<Int>? {
        let ids = text.pages[page].lineIDs.flatMap { Array(text.lines[$0].wordIDs) }
        var hit: [Int] = []
        for id in ids {
            let r = text.words[id].rect.insetBy(dx: -tolerance, dy: -tolerance)
            if crosses(points, r) { hit.append(id) }
        }
        guard let lo = hit.min(), let hi = hit.max() else { return nil }
        return lo...hi
    }

    /// One rect per line for a highlight, in page points.
    public static func rects(for h: Highlight, text: DocumentText) -> [(page: Int, rect: CGRect)] {
        var byLine: [Int: CGRect] = [:]
        for id in h.wordIDs where id < text.words.count {
            let w = text.words[id]
            byLine[w.lineID] = (byLine[w.lineID] ?? .null).union(w.rect)
        }
        return byLine.keys.sorted().map { (text.lines[$0].page, byLine[$0]!) }
    }

    static func crosses(_ pts: [CGPoint], _ r: CGRect) -> Bool {
        if pts.contains(where: { r.contains($0) }) { return true }
        for (a, b) in zip(pts, pts.dropFirst()) where segment(a, b, hits: r) { return true }
        return false
    }

    static func segment(_ a: CGPoint, _ b: CGPoint, hits r: CGRect) -> Bool {
        // Sample along the segment; strokes are dense, so a few samples per word width is enough.
        let len = hypot(b.x - a.x, b.y - a.y)
        let n = max(1, Int(len / 2))
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            if r.contains(CGPoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y))) { return true }
        }
        return false
    }
}

public enum Eraser {
    /// Everything an eraser pass touches, as one action: whole pen movements and highlights.
    public static func erase(screenPoints pts: [CGPoint], radius: CGFloat = 10, marks: PaperMarks,
                             in vp: PaperViewport) -> Edit<Mark> {
        var groups = Set<UUID>()
        var highlights = Set<UUID>()
        // Does the eraser come within `radius` of a stroke's path (not just its points)?
        func touches(_ path: [CGPoint]) -> Bool { Eraser.touches(pts, path: path, radius: radius) }
        for s in marks.pageStrokes where !groups.contains(s.group) {
            if touches(s.points.compactMap { vp.screenPoint(page: s.page, point: $0) }) { groups.insert(s.group) }
        }
        for s in marks.marginStrokes where !groups.contains(s.group) {
            if touches(s.points.compactMap { vp.screenPoint($0, line: s.lineID, side: s.side) }) { groups.insert(s.group) }
        }
        for h in marks.highlights {
            for (page, rect) in Highlighter.rects(for: h, text: vp.text) {
                guard let o = vp.screenPoint(page: page, point: rect.origin),
                      let e = vp.screenPoint(page: page, point: CGPoint(x: rect.maxX, y: rect.maxY)) else { continue }
                let screenRect = CGRect(x: o.x, y: o.y, width: e.x - o.x, height: e.y - o.y).insetBy(dx: -radius, dy: -radius)
                if pts.contains(where: { screenRect.contains($0) }) { highlights.insert(h.id); break }
            }
        }
        var removed: [Mark] = []
        for g in groups { removed += marks.marks(inGroup: g) }
        removed += marks.highlights.filter { highlights.contains($0.id) }.map(Mark.highlight)
        return Edit(removed: removed)
    }

    /// Does any eraser point come within `radius` of a path?
    public static func touches(_ eraser: [CGPoint], path: [CGPoint], radius: CGFloat) -> Bool {
        guard let first = path.first else { return false }
        if path.count == 1 { return eraser.contains { hypot($0.x - first.x, $0.y - first.y) <= radius } }
        for (a, b) in zip(path, path.dropFirst()) {
            for p in eraser where distance(p, a, b) <= radius { return true }
        }
        return false
    }

    /// Distance from p to the segment ab.
    static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
