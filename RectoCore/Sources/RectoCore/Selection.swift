import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Picking text on the paper: a tap takes a sentence, a drag takes the words between its ends.
public enum TextPicker {
    /// The word under a screen point, or the nearest word on the same line within `slop` points.
    public static func word(at p: CGPoint, in vp: PaperViewport, slop: CGFloat = 12) -> Int? {
        guard case let .page(page, q, _) = vp.spot(at: p) else { return nil }
        let text = vp.text
        var best: (id: Int, d: CGFloat)? = nil
        for lineID in text.pages[page].lineIDs {
            let line = text.lines[lineID]
            guard q.y >= line.rect.minY - 2, q.y <= line.rect.maxY + 2 else { continue }
            for id in line.wordIDs {
                let r = text.words[id].rect
                let d = r.contains(q) ? 0 : max(r.minX - q.x, q.x - r.maxX, 0)
                if best == nil || d < best!.d { best = (id, d) }
            }
        }
        // Distances are in page points; slop is in screen points.
        let scale = vp.layout.pieces.first { $0.page == page && $0.source.contains(q) }?.scale ?? 1
        guard let b = best, b.d * scale <= slop else { return nil }
        return b.id
    }

    /// A drag from one point to another: every word between the two ends, in reading order.
    public static func range(from a: CGPoint, to b: CGPoint, in vp: PaperViewport) -> ClosedRange<Int>? {
        guard let x = word(at: a, in: vp), let y = word(at: b, in: vp) else { return nil }
        return min(x, y)...max(x, y)
    }

    /// A tap: the whole sentence under the finger.
    public static func sentence(at p: CGPoint, in vp: PaperViewport) -> ClosedRange<Int>? {
        word(at: p, in: vp).flatMap { vp.text.sentence(ofWord: $0)?.wordIDs }
    }

    /// The words as text, for the Quote card and copy.
    public static func excerpt(_ range: ClosedRange<Int>, text: DocumentText) -> String {
        range.map { text.words[$0].text }.joined(separator: " ")
    }
}
