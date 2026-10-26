import Foundation

public enum PaperTool: String, Codable, Sendable { case pen, highlighter, eraser }

/// All the reader's state in one place, outside the views, so a fold or a resize loses nothing.
/// The app wraps this in an observable object; the views only draw it.
public struct ReaderState: Sendable {
    public let text: DocumentText
    public private(set) var record: PaperRecord
    public private(set) var settings: LayoutSettings
    public private(set) var environment: WindowEnvironment
    public private(set) var surface: Surface
    public private(set) var layout: ContentLayout
    public private(set) var scrollY: CGFloat = 0

    public var writeMode = false
    public var tool: PaperTool = .pen
    public var color: InkColor = .blue
    public var penWidth: CGFloat = 2

    public private(set) var paperHistory = History<Mark>()
    public private(set) var notebookHistory = History<NotebookItem>()

    public init(text: DocumentText, record: PaperRecord = PaperRecord(), environment: WindowEnvironment) {
        self.text = text
        self.record = record
        var s = LayoutSettings()
        s.notesSide = record.notesSide
        s.viewChoice = record.viewChoice
        self.settings = s
        self.environment = environment
        self.surface = Surface(environment: environment, settings: s)
        self.layout = ContentLayout(text: text, view: surface.view, width: surface.paper.width)
        if let pos = record.position { scrollY = pos.scrollY(text: text, layout: layout) ?? 0 }
    }

    public var viewport: PaperViewport {
        PaperViewport(text: text, layout: layout, surface: surface, scrollY: scrollY)
    }

    /// The reading line. Taken when the reader scrolls, and only then, so a layout change can never
    /// move it: on a two-column page a scroll distance alone cannot say which column you were in.
    public var position: ReadingPosition? {
        record.position ?? ReadingPosition.capture(text: text, layout: layout, scrollY: scrollY)
    }

    // MARK: Scrolling

    public mutating func scroll(to y: CGFloat) {
        let maxY = max(0, layout.height - surface.paper.height)
        scrollY = min(max(0, y), maxY)
        record.position = ReadingPosition.capture(text: text, layout: layout, scrollY: scrollY)
    }

    // MARK: Anything that changes the layout keeps the reading line

    /// The window changed: a fold, a resize, Split View. Save the line, lay out again, restore the line.
    public mutating func setEnvironment(_ env: WindowEnvironment) {
        relayout { $0.environment = env }
    }

    public mutating func setFacing(_ mode: FacingMode) { relayout { $0.settings.facing = mode } }
    public mutating func setBandOpen(_ open: Bool) { relayout { $0.settings.bandOpen = open } }
    public mutating func setSingleShows(_ shows: SinglePageShows) { relayout { $0.settings.singleShows = shows } }

    /// Columns or Page, remembered per paper. Nil goes back to following the pane width.
    public mutating func setView(_ view: PaperView?) {
        relayout { $0.settings.viewChoice = view; $0.record.viewChoice = view }
    }

    /// Swap sides moves the notes page to the other side. The notes stay in the margin they were
    /// written in; the other margin becomes the one in use and the old one shows as ink tabs.
    public mutating func swapSides() {
        relayout { $0.settings.notesSide = $0.settings.notesSide.other; $0.record.notesSide = $0.settings.notesSide }
    }

    private mutating func relayout(_ change: (inout ReaderState) -> Void) {
        let saved = position
        change(&self)
        surface = Surface(environment: environment, settings: settings)
        layout = ContentLayout(text: text, view: surface.view, width: surface.paper.width)
        if let saved, let y = saved.scrollY(text: text, layout: layout) {
            scrollY = max(0, y)
            record.position = saved
        }
    }

    // MARK: Marks

    /// A finished pen, highlighter or eraser movement on the paper or the margin, in window points.
    public mutating func finishStroke(_ points: [CGPoint]) {
        guard points.count > 0 else { return }
        let vp = viewport
        var edit = Edit<Mark>()
        switch tool {
        case .pen:
            edit.added = InkRouter.route(screenPoints: points, in: vp, color: color, width: penWidth)
        case .highlighter:
            // Snap to the words crossed on the page the stroke starts on.
            if case let .page(page, _, _) = vp.spot(at: points[0]) {
                let pagePts = points.compactMap { p -> CGPoint? in
                    if case let .page(pg, q, _) = vp.spot(at: p), pg == page { return q }
                    return nil
                }
                if let range = Highlighter.snap(points: pagePts, page: page, text: text) {
                    edit.added = [.highlight(Highlight(wordIDs: range, color: color))]
                }
            }
        case .eraser:
            edit = Eraser.erase(screenPoints: points, marks: record.marks, in: vp)
        }
        guard !edit.isEmpty else { return }
        record.marks.apply(edit)
        paperHistory.record(edit)
    }

    public mutating func undoPaper() {
        if let e = paperHistory.undo() { record.marks.apply(e) }
    }

    public mutating func redoPaper() {
        if let e = paperHistory.redo() { record.marks.apply(e) }
    }

    public mutating func quote(wordIDs: ClosedRange<Int>) {
        let excerpt = wordIDs.map { text.words[$0].text }.joined(separator: " ")
        let page = text.lines[text.words[wordIDs.lowerBound].lineID].page + 1
        let edit = record.notebook.addQuote(excerpt: excerpt, wordIDs: wordIDs, pageNumber: page)
        notebookHistory.record(edit)
    }

    public mutating func undoNotebook() {
        if let e = notebookHistory.undo() { record.notebook.apply(e) }
    }

    public mutating func redoNotebook() {
        if let e = notebookHistory.redo() { record.notebook.apply(e) }
    }

    public var inkTabs: [InkTab] { InkTabs.tabs(marks: record.marks, in: viewport) }
}
