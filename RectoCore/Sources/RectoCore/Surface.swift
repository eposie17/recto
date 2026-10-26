import Foundation

/// What the window gives us. The layout comes only from this, never from the pose or the hinge angle.
public struct WindowEnvironment: Equatable, Sendable {
    /// The window size in points.
    public var size: CGSize
    /// The fold, in window points, when the window spans it (from the system's reserved regions).
    public var fold: CGRect?
    /// The whole screen in window points. Equal to the window unless the window is a Split View pane.
    /// Used for the grip-edge rule, which only applies at the screen's real edges.
    public var screen: CGRect
    /// In a single page, which edge the side bar sits on. In Split View it goes on the edge away from the fold.
    public var sideBarEdge: MarginSide?

    public init(size: CGSize, fold: CGRect? = nil, screen: CGRect? = nil, sideBarEdge: MarginSide? = nil) {
        self.size = size
        self.fold = fold
        self.screen = screen ?? CGRect(origin: .zero, size: size)
        self.sideBarEdge = sideBarEdge
    }

    // Sizes from the Duo research (points). Handy for tests and previews.
    public static let duoClosed = WindowEnvironment(size: CGSize(width: 466, height: 678))
    public static let duoOpen = WindowEnvironment(size: CGSize(width: 951, height: 669),
                                                  fold: CGRect(x: 467.5, y: 0, width: 16, height: 669))
    public static let duoLaptop = WindowEnvironment(size: CGSize(width: 669, height: 951),
                                                    fold: CGRect(x: 0, y: 467.5, width: 669, height: 16))
    public static let duoSplitLeft = WindowEnvironment(size: CGSize(width: 467.5, height: 669),
                                                       screen: CGRect(x: 0, y: 0, width: 951, height: 669),
                                                       sideBarEdge: .left)
    public static let iPadLandscape = WindowEnvironment(size: CGSize(width: 1180, height: 820))
    public static let iPadPortrait = WindowEnvironment(size: CGSize(width: 820, height: 1180))
    public static let iPhone = WindowEnvironment(size: CGSize(width: 393, height: 852))
}

/// What the facing page shows. Only the picker changes it.
public enum FacingMode: String, Codable, Sendable {
    case margin       // Notes, Margin layout: the paper's own margin
    case notebook     // Notes, Notebook layout: fixed pages for handwriting, typing and quotes
    case samePaper
    case figures
    case anotherPaper

    public var isNotes: Bool { self == .margin || self == .notebook }
}

/// On a single page (closed phone, Split View, plain iPhone): the paper or the notes.
public enum SinglePageShows: String, Codable, Sendable { case paper, notes }

public struct LayoutSettings: Equatable, Sendable {
    public var notesSide: MarginSide = .right
    public var bandOpen = false            // closed by default (Posi, 26 Oct)
    public var facing: FacingMode = .margin
    public var singleShows: SinglePageShows = .paper
    public var viewChoice: PaperView? = nil // remembered per paper; nil = follow the pane width

    public init() {}
}

/// How the margin is shown.
public enum MarginDisplay: Equatable, Sendable {
    /// Beside the paper and scrolled with it. `edgeX` is the screen x of the page edge (across 0),
    /// and the margin runs outward from it toward `side`. Visible across 0...`visibleAcross`.
    case beside(side: MarginSide, edgeX: CGFloat, visibleAcross: CGFloat, frame: CGRect)
    /// The whole margin in its own pane, synced to the paper line by line, drawn at `scale`.
    /// The last words of each line are shown in a strip `snippetWidth` wide next to it.
    case whole(side: MarginSide, frame: CGRect, scale: CGFloat, snippetWidth: CGFloat)
}

public enum Arrangement: String, Sendable { case single, sideBySide, stacked }

/// Where everything goes on screen for one window and one set of settings.
public struct Surface: Equatable, Sendable {
    public static let sideBarWidth: CGFloat = 56
    public static let topBarHeight: CGFloat = 50
    public static let bandScale: CGFloat = 0.78
    public static let twoPageMinWidth: CGFloat = 860
    public static let notebookPage = CGSize(width: 400, height: 560)
    public static let snippetWidth: CGFloat = 96

    public var arrangement: Arrangement
    public var sideBar: CGRect?
    /// Where the paper strip shows. The strip is laid out at this width. Empty if the paper is hidden.
    public var paper: CGRect
    public var view: PaperView
    public var margin: MarginDisplay?
    public var crease: CGRect?
    /// The facing page area when it is not the margin.
    public var facing: CGRect?
    /// The fixed-size notebook page, fitted into the facing area. Never reflowed.
    public var notebookPage: CGRect?
    public var notebookScale: CGFloat = 1

    public init(environment env: WindowEnvironment, settings s: LayoutSettings) {
        let W = env.size.width, H = env.size.height
        let top = Surface.topBarHeight
        arrangement = .single; paper = .zero; view = .page
        sideBar = nil; margin = nil; crease = nil; facing = nil; notebookPage = nil

        if let fold = env.fold, fold.width >= fold.height {
            // Fold runs across: laptop pose, or open and held tall. Paper on top, facing page below.
            arrangement = .stacked
            crease = fold
            paper = CGRect(x: 0, y: top, width: W, height: max(0, fold.minY - top))
            let below = CGRect(x: 0, y: fold.maxY, width: W, height: max(0, H - fold.maxY))
            if s.facing == .margin {
                let scale = min(1, (W - Surface.snippetWidth) / PaperMarks.marginWidth)
                margin = .whole(side: s.notesSide, frame: below, scale: scale, snippetWidth: Surface.snippetWidth)
            } else {
                facing = below
                if s.facing == .notebook { placeNotebook(in: below, scrolls: true) }
            }
        } else if env.fold != nil || W >= Surface.twoPageMinWidth {
            // Two pages side by side: open flat, book pose, iPad landscape.
            arrangement = .sideBySide
            let fold = env.fold ?? CGRect(x: W / 2, y: 0, width: 0, height: H)
            crease = env.fold
            let paperOnLeft = s.notesSide == .right
            var paperWidth = paperOnLeft ? fold.minX : W - fold.maxX
            // With no fold (iPad), draw the column a little larger so the margin fills the notes page.
            if env.fold == nil, s.facing == .margin {
                paperWidth = max(paperWidth, W - PaperMarks.marginWidth)
            }
            paper = paperOnLeft
                ? CGRect(x: 0, y: top, width: paperWidth, height: H - top)
                : CGRect(x: W - paperWidth, y: top, width: paperWidth, height: H - top)
            let rest = paperOnLeft
                ? CGRect(x: paper.maxX, y: top, width: W - paper.maxX, height: H - top)
                : CGRect(x: 0, y: top, width: paper.minX, height: H - top)
            if s.facing == .margin {
                // The margin starts at the page edge, runs over the crease and fills the facing page.
                margin = .beside(side: s.notesSide, edgeX: paperOnLeft ? paper.maxX : paper.minX,
                                 visibleAcross: min(PaperMarks.marginWidth, rest.width), frame: rest)
            } else {
                let face = paperOnLeft
                    ? CGRect(x: fold.maxX, y: top, width: W - fold.maxX, height: H - top)
                    : CGRect(x: 0, y: top, width: fold.minX, height: H - top)
                facing = face
                if s.facing == .notebook { placeNotebook(in: face, scrolls: false) }
            }
        } else {
            // One page: the closed phone, a Split View pane, a plain iPhone, iPad portrait.
            arrangement = .single
            let barEdge = env.sideBarEdge ?? s.notesSide.other
            let bar = barEdge == .left
                ? CGRect(x: 0, y: 0, width: Surface.sideBarWidth, height: H)
                : CGRect(x: W - Surface.sideBarWidth, y: 0, width: Surface.sideBarWidth, height: H)
            sideBar = bar
            let area = barEdge == .left
                ? CGRect(x: bar.maxX, y: 0, width: W - bar.width, height: H)
                : CGRect(x: 0, y: 0, width: W - bar.width, height: H)
            if s.singleShows == .notes && s.facing.isNotes {
                paper = .zero
                if s.facing == .margin {
                    let scale = min(1, (area.width - Surface.snippetWidth) / PaperMarks.marginWidth)
                    margin = .whole(side: s.notesSide, frame: area, scale: scale, snippetWidth: Surface.snippetWidth)
                } else {
                    facing = area
                    placeNotebook(in: area, scrolls: false)
                }
            } else if s.bandOpen && s.facing == .margin {
                // The thin band: the page shrinks to about 78 percent and the margin shows beside it.
                let pw = (area.width * Surface.bandScale).rounded()
                let band = area.width - pw
                if s.notesSide == .right {
                    paper = CGRect(x: area.minX, y: area.minY, width: pw, height: area.height)
                    margin = .beside(side: .right, edgeX: paper.maxX, visibleAcross: band,
                                     frame: CGRect(x: paper.maxX, y: area.minY, width: band, height: area.height))
                } else {
                    paper = CGRect(x: area.maxX - pw, y: area.minY, width: pw, height: area.height)
                    margin = .beside(side: .left, edgeX: paper.minX, visibleAcross: band,
                                     frame: CGRect(x: area.minX, y: area.minY, width: band, height: area.height))
                }
            } else {
                paper = area
            }
        }
        view = s.viewChoice ?? PaperView.automatic(forPaneWidth: paper.width)
    }

    private mutating func placeNotebook(in area: CGRect, scrolls: Bool) {
        let size = Surface.notebookPage
        // Shown a little smaller in a narrow pane, never reflowed. In laptop pose it scrolls instead.
        let scale = scrolls ? min(1, area.width / size.width) : min(1, area.width / size.width, area.height / size.height)
        notebookScale = scale
        let w = size.width * scale, h = size.height * scale
        notebookPage = CGRect(x: area.midX - w / 2, y: scrolls ? area.minY : area.midY - h / 2, width: w, height: h)
    }

    /// The side of the margin on screen, if any.
    public var shownMarginSide: MarginSide? {
        switch margin {
        case .beside(let side, _, _, _), .whole(let side, _, _, _): return side
        case nil: return nil
        }
    }
}
