import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Paper ink comes in four colours so no stroke hides in the black text. Notebook adds black.
public enum InkColor: String, Codable, CaseIterable, Sendable {
    case blue, red, purple, orange, black

    public static let paperColors: [InkColor] = [.blue, .red, .purple, .orange]
}

public enum MarginSide: String, Codable, Sendable {
    case left, right
    public var other: MarginSide { self == .left ? .right : .left }
}

/// Ink on a printed page, in page points. Keeps its place through zoom, Columns and export.
public struct PageStroke: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// Strokes cut at the page edge share a group, so one pen movement stays one mark.
    public var group: UUID
    public var page: Int
    public var points: [CGPoint]
    public var color: InkColor
    public var width: CGFloat

    public init(id: UUID = UUID(), group: UUID, page: Int, points: [CGPoint], color: InkColor, width: CGFloat) {
        self.id = id; self.group = group; self.page = page; self.points = points; self.color = color; self.width = width
    }
}

/// A point in a margin: `across` is points out from the page edge (0 at the edge, up to 520),
/// `down` is points below the top of the line it sits beside. Margin ink never rescales.
public struct MarginPoint: Codable, Equatable, Sendable {
    public var across: CGFloat
    public var down: CGFloat
    public init(across: CGFloat, down: CGFloat) { self.across = across; self.down = down }
}

public struct MarginStroke: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var group: UUID
    public var side: MarginSide
    public var lineID: Int
    public var points: [MarginPoint]
    public var color: InkColor
    public var width: CGFloat

    public init(id: UUID = UUID(), group: UUID, side: MarginSide, lineID: Int, points: [MarginPoint], color: InkColor, width: CGFloat) {
        self.id = id; self.group = group; self.side = side; self.lineID = lineID; self.points = points
        self.color = color; self.width = width
    }
}

/// A highlight is a run of words, so a pen highlight and a menu highlight are the same thing.
public struct Highlight: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var wordIDs: ClosedRange<Int>
    public var color: InkColor

    public init(id: UUID = UUID(), wordIDs: ClosedRange<Int>, color: InkColor) {
        self.id = id; self.wordIDs = wordIDs; self.color = color
    }
}

public enum Mark: Codable, Equatable, Sendable {
    case page(PageStroke)
    case margin(MarginStroke)
    case highlight(Highlight)

    public var id: UUID {
        switch self {
        case .page(let s): return s.id
        case .margin(let s): return s.id
        case .highlight(let h): return h.id
        }
    }
}

/// Every mark on one paper. Marks live only here, so every view of the paper shows the same marks.
public struct PaperMarks: Codable, Equatable, Sendable {
    public static let marginWidth: CGFloat = 520

    public var pageStrokes: [PageStroke] = []
    public var marginStrokes: [MarginStroke] = []
    public var highlights: [Highlight] = []

    public init() {}

    public var all: [Mark] {
        pageStrokes.map(Mark.page) + marginStrokes.map(Mark.margin) + highlights.map(Mark.highlight)
    }

    public mutating func insert(_ m: Mark) {
        switch m {
        case .page(let s): pageStrokes.append(s)
        case .margin(let s): marginStrokes.append(s)
        case .highlight(let h): highlights.append(h)
        }
    }

    public mutating func remove(id: UUID) {
        pageStrokes.removeAll { $0.id == id }
        marginStrokes.removeAll { $0.id == id }
        highlights.removeAll { $0.id == id }
    }

    public func marks(inGroup group: UUID) -> [Mark] {
        pageStrokes.filter { $0.group == group }.map(Mark.page)
            + marginStrokes.filter { $0.group == group }.map(Mark.margin)
    }

    public func marginStrokes(on side: MarginSide) -> [MarginStroke] {
        marginStrokes.filter { $0.side == side }
    }
}
