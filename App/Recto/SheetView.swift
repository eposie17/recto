import SwiftUI
import UIKit
import PDFKit
import RectoCore

/// The paper and the margin beside it, as one scrolling sheet, plus the ink on top.
/// A finger scrolls; in Write mode one finger inks and two fingers scroll; a Pencil always inks.
struct SheetRepresentable: UIViewRepresentable {
    let model: ReaderModel
    // Passed in so SwiftUI redraws us when they change.
    let surface: Surface
    let view: PaperView
    let scrollY: CGFloat
    let marksVersion: Int
    let writeMode: Bool

    func makeUIView(context: Context) -> SheetView { SheetView(model: model) }

    func updateUIView(_ v: SheetView, context: Context) { v.sync() }
}

final class SheetView: UIView, UIScrollViewDelegate {
    let model: ReaderModel
    private let scroll = UIScrollView()
    private let content = InkCaptureView()
    private let ink = InkLayerView()
    private var pieceViews: [Int: UIImageView] = [:]
    private var builtFor: (Surface, PaperView, CGFloat)?
    private var settingOffset = false

    init(model: ReaderModel) {
        self.model = model
        super.init(frame: .zero)
        scroll.delegate = self
        scroll.delaysContentTouches = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        scroll.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scroll.addSubview(content)
        addSubview(scroll)
        ink.isUserInteractionEnabled = false
        ink.backgroundColor = .clear
        ink.model = model
        addSubview(ink)
        content.sheet = self
        backgroundColor = .systemBackground
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        ink.frame = bounds
        sync()
    }

    /// Bring the views in line with the model.
    func sync() {
        let st = model.state
        scroll.panGestureRecognizer.minimumNumberOfTouches = st.writeMode ? 2 : 1
        let key = (st.surface, st.layout.view, st.layout.width)
        if builtFor == nil || builtFor!.0 != key.0 || builtFor!.1 != key.1 || builtFor!.2 != key.2 {
            builtFor = key
            pieceViews.values.forEach { $0.removeFromSuperview() }
            pieceViews = [:]
            let paper = st.surface.paper
            scroll.isHidden = paper.width <= 0
            content.frame = CGRect(x: 0, y: 0, width: bounds.width, height: paper.minY + st.layout.height + bounds.height * 0.5)
            scroll.contentSize = content.frame.size
        }
        if abs(scroll.contentOffset.y - st.scrollY) > 0.5, !scroll.isDragging, !scroll.isDecelerating {
            settingOffset = true
            scroll.contentOffset = CGPoint(x: 0, y: st.scrollY)
            settingOffset = false
        }
        showVisiblePieces()
        ink.setNeedsDisplay()
    }

    func scrollViewDidScroll(_ s: UIScrollView) {
        if !settingOffset { model.scroll(to: s.contentOffset.y) }
        showVisiblePieces()
        ink.setNeedsDisplay()
    }

    /// Render the crops near the screen and drop the far ones.
    private func showVisiblePieces() {
        let st = model.state
        let paper = st.surface.paper
        guard paper.width > 0 else { return }
        let top = scroll.contentOffset.y - bounds.height, bottom = scroll.contentOffset.y + bounds.height * 2
        for (i, piece) in st.layout.pieces.enumerated() {
            let f = piece.frame.offsetBy(dx: paper.minX, dy: paper.minY)
            let near = f.maxY > top && f.minY < bottom
            if near, pieceViews[i] == nil {
                let iv = UIImageView(frame: f)
                iv.image = PieceRenderer.image(for: piece, in: model.document)
                iv.layer.shadowOpacity = 0.08
                iv.layer.shadowRadius = 2
                content.addSubview(iv)
                pieceViews[i] = iv
            } else if !near, let iv = pieceViews[i] {
                iv.removeFromSuperview()
                pieceViews[i] = nil
            }
        }
    }

    // MARK: Ink input, from the capture view

    private var live: [CGPoint] = []

    func begin(_ touch: UITouch, at p: CGPoint) -> Bool {
        let kind: TouchKind = touch.type == .pencil ? .pencil : .finger
        var env = model.state.environment
        env.screen = screenFrame
        let decision = InputRules.decide(kind: kind, start: p, writeMode: model.state.writeMode, environment: env)
        guard decision == .ink else { return false }
        live = [p]
        ink.live = live
        return true
    }

    func move(to pts: [CGPoint]) {
        live += pts
        ink.live = live
        ink.setNeedsDisplay()
    }

    func end(cancelled: Bool) {
        if !cancelled, !live.isEmpty { model.finishStroke(live) }
        live = []
        ink.live = []
        ink.setNeedsDisplay()
    }

    /// The screen's frame in our coordinates, for the grip-edge rule (differs in Split View).
    var screenFrame: CGRect {
        guard let window else { return bounds }
        let s = window.screen.bounds
        return convert(window.convert(s, from: window.screen.coordinateSpace), from: window)
    }
}

/// Sits inside the scroll view and receives the touches the scroll view's pan does not take.
final class InkCaptureView: UIView {
    weak var sheet: SheetView?
    private var tracking: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracking == nil, let t = touches.first, let sheet else { return }
        if sheet.begin(t, at: t.location(in: sheet)) { tracking = t }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = tracking, touches.contains(t), let sheet else { return }
        let all = event?.coalescedTouches(for: t) ?? [t]
        sheet.move(to: all.map { $0.location(in: sheet) })
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = tracking, touches.contains(t) else { return }
        tracking = nil
        sheet?.end(cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // A second finger turned this into a scroll: drop the stroke.
        guard let t = tracking, touches.contains(t) else { return }
        tracking = nil
        sheet?.end(cancelled: true)
    }
}

extension InkColor {
    var ui: UIColor {
        switch self {
        case .blue: return .systemBlue
        case .red: return .systemRed
        case .purple: return .systemPurple
        case .orange: return .systemOrange
        case .black: return .label
        }
    }
}

/// Draws highlights, page ink, margin ink, the crease and the pen stroke in progress.
final class InkLayerView: UIView {
    weak var model: ReaderModel?
    var live: [CGPoint] = []

    override func draw(_ rect: CGRect) {
        guard let model, let ctx = UIGraphicsGetCurrentContext() else { return }
        let st = model.state
        let vp = st.viewport
        let marks = st.record.marks

        if let crease = st.surface.crease {
            UIColor.secondarySystemBackground.withAlphaComponent(0.5).setFill()
            ctx.fill(crease)
        }

        // Highlights under the ink.
        for h in marks.highlights {
            h.color.ui.withAlphaComponent(0.25).setFill()
            for (page, r) in Highlighter.rects(for: h, text: st.text) {
                guard let a = vp.screenPoint(page: page, point: r.origin),
                      let b = vp.screenPoint(page: page, point: CGPoint(x: r.maxX, y: r.maxY)) else { continue }
                ctx.fill(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
            }
        }

        for s in marks.pageStrokes {
            stroke(s.points.compactMap { vp.screenPoint(page: s.page, point: $0) }, s.color, s.width)
        }

        switch st.surface.margin {
        case .beside(_, _, _, let frame)?:
            ctx.saveGState()
            ctx.clip(to: frame.union(st.surface.paper))
            for s in marks.marginStrokes {
                stroke(s.points.compactMap { vp.screenPoint($0, line: s.lineID, side: s.side) }, s.color, s.width)
            }
            ctx.restoreGState()
        case let .whole(side, frame, scale, snippet)?:
            drawWholeMargin(st: st, vp: vp, side: side, frame: frame, scale: scale, snippet: snippet, ctx: ctx)
        case nil:
            break
        }

        if live.count > 1 {
            let color: UIColor = st.tool == .eraser ? .systemGray : st.color.ui.withAlphaComponent(st.tool == .highlighter ? 0.35 : 1)
            stroke(live, color, st.tool == .highlighter ? 12 : st.penWidth)
        }
    }

    /// The whole margin in its own pane: ink at `scale`, and the last words of each line beside it
    /// so you can tell which line a note belongs to. Read-only in this first build.
    private func drawWholeMargin(st: ReaderState, vp: PaperViewport, side: MarginSide, frame: CGRect,
                                 scale: CGFloat, snippet: CGFloat, ctx: CGContext) {
        ctx.saveGState()
        ctx.clip(to: frame)
        UIColor.secondarySystemBackground.setFill()
        ctx.fill(CGRect(x: frame.minX, y: frame.minY, width: snippet, height: frame.height))
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.secondaryLabel]
        // Lines are placed as in the paper strip, so the pane follows the line you are reading.
        let top = vp.scrollY
        for (line, r) in st.layout.linesInOrder(st.text) where r.maxY > top - 40 && r.minY < top + frame.height + 40 {
            let y = frame.minY + (r.minY - top)
            let words = line.wordIDs.suffix(2).map { st.text.words[$0].text }.joined(separator: " ")
            (words as NSString).draw(at: CGPoint(x: frame.minX + 4, y: y), withAttributes: attrs)
        }
        for s in st.record.marks.marginStrokes(on: side) {
            guard s.lineID < st.text.lines.count, let r = st.layout.stripRect(ofLine: st.text.lines[s.lineID]) else { continue }
            let pts = s.points.map { CGPoint(x: frame.minX + snippet + $0.across * scale,
                                             y: frame.minY + (r.minY - top) + $0.down * scale) }
            stroke(pts, s.color.ui, s.width)
        }
        ctx.restoreGState()
    }

    private func stroke(_ pts: [CGPoint], _ color: InkColor, _ width: CGFloat) { stroke(pts, color.ui, width) }

    private func stroke(_ pts: [CGPoint], _ color: UIColor, _ width: CGFloat) {
        guard let first = pts.first else { return }
        let path = UIBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: first)
        if pts.count == 1 { path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y)) }
        for p in pts.dropFirst() { path.addLine(to: p) }
        color.setStroke()
        path.stroke()
    }
}
