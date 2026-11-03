import Foundation
import CoreGraphics

/// Typed notes and Quote cards go on fixed-size notebook pages. Every block keeps its place.
public struct NotebookStroke: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var points: [CGPoint]   // notebook page points
    public var color: InkColor
    public var width: CGFloat
    public init(points: [CGPoint], color: InkColor, width: CGFloat) { self.points = points; self.color = color; self.width = width }

    public var bounds: CGRect {
        points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }.insetBy(dx: -width, dy: -width)
    }
}

public struct NotebookBlock: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case typed(String)
        /// A quote remembers its passage, so tapping it jumps the paper back there.
        case quote(excerpt: String, wordIDs: ClosedRange<Int>, pageNumber: Int)
    }
    public var id = UUID()
    public var kind: Kind
    public var frame: CGRect
}

public struct NotebookPage: Codable, Equatable, Sendable {
    public var strokes: [NotebookStroke] = []
    public var blocks: [NotebookBlock] = []
    public init() {}
}

public enum NotebookItem: Equatable, Sendable {
    case stroke(page: Int, NotebookStroke)
    case block(page: Int, NotebookBlock)

    public var id: UUID {
        switch self {
        case .stroke(_, let s): return s.id
        case .block(_, let b): return b.id
        }
    }
}

public struct Notebook: Codable, Equatable, Sendable {
    public static let size = Surface.notebookPage
    public static let inset: CGFloat = 16
    public static let step: CGFloat = 8

    public var pages: [NotebookPage] = [NotebookPage()]
    public init() {}

    /// The next free slot for a block of this height: the first place on any page, top to bottom,
    /// that overlaps no block and no ink. A full page starts a new page. Nothing already placed moves.
    public func nextFreeSlot(height: CGFloat) -> (page: Int, frame: CGRect) {
        let w = Notebook.size.width - 2 * Notebook.inset
        for (i, page) in pages.enumerated() {
            let taken = page.blocks.map(\.frame) + page.strokes.map(\.bounds)
            var y = Notebook.inset
            while y + height <= Notebook.size.height - Notebook.inset {
                let r = CGRect(x: Notebook.inset, y: y, width: w, height: height)
                if !taken.contains(where: { $0.intersects(r) }) { return (i, r) }
                y += Notebook.step
            }
        }
        return (pages.count, CGRect(x: Notebook.inset, y: Notebook.inset, width: w, height: height))
    }

    /// Adds a Quote card in the next free slot. Returns the edit for the notebook's history.
    public mutating func addQuote(excerpt: String, wordIDs: ClosedRange<Int>, pageNumber: Int, height: CGFloat = 72) -> Edit<NotebookItem> {
        let slot = nextFreeSlot(height: height)
        let block = NotebookBlock(kind: .quote(excerpt: excerpt, wordIDs: wordIDs, pageNumber: pageNumber), frame: slot.frame)
        let edit = Edit(added: [NotebookItem.block(page: slot.page, block)])
        apply(edit)
        return edit
    }

    public mutating func apply(_ edit: Edit<NotebookItem>) {
        for item in edit.removed {
            for i in pages.indices {
                pages[i].strokes.removeAll { $0.id == item.id }
                pages[i].blocks.removeAll { $0.id == item.id }
            }
        }
        for item in edit.added {
            switch item {
            case .stroke(let p, let s): ensure(p); pages[p].strokes.append(s)
            case .block(let p, let b): ensure(p); pages[p].blocks.append(b)
            }
        }
    }

    private mutating func ensure(_ page: Int) {
        while pages.count <= page { pages.append(NotebookPage()) }
    }
}
