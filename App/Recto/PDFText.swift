import PDFKit
import RectoCore

/// Reads the PDF text layer into RectoCore's DocumentText.
/// PDFKit uses a bottom-left origin; RectoCore uses top-left, so we flip here and only here.
enum PDFText {
    static func read(_ document: PDFDocument) -> DocumentText {
        var sizes: [CGSize] = []
        var pages: [[[(String, CGRect)]]] = []
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            sizes.append(box.size)
            pages.append(lines(on: page, box: box))
        }
        return DocumentText(pageSizes: sizes, linesPerPage: pages)
    }

    private static func lines(on page: PDFPage, box: CGRect) -> [[(String, CGRect)]] {
        guard let text = page.string as NSString?, text.length > 0 else { return [] }
        var lines: [[(String, CGRect)]] = []
        var line: [(String, CGRect)] = []
        var word = ""
        var wordRect = CGRect.null

        func flip(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX - box.minX, y: box.maxY - r.maxY, width: r.width, height: r.height)
        }
        func endWord() {
            guard !word.isEmpty, !wordRect.isNull else { word = ""; wordRect = .null; return }
            let r = flip(wordRect)
            if let last = line.last {
                // A new line when the baseline moves or the text jumps back to the left.
                let sameRow = abs(last.1.midY - r.midY) < max(last.1.height, r.height) * 0.5
                if !sameRow || r.minX < last.1.minX { endLine() }
            }
            line.append((word, r))
            word = ""; wordRect = .null
        }
        func endLine() {
            if !line.isEmpty { lines.append(line) }
            line = []
        }

        for i in 0..<text.length {
            let c = text.character(at: i)
            let isSpace = c == 0x20 || c == 0x09 || c == 0xA0
            let isBreak = c == 0x0A || c == 0x0D
            if isSpace || isBreak {
                endWord()
                if isBreak { endLine() }
                continue
            }
            let b = page.characterBounds(at: i)
            guard b.width > 0 || b.height > 0 else { continue }
            if let u = UnicodeScalar(c) { word.unicodeScalars.append(u) }
            wordRect = wordRect.union(b)
        }
        endWord()
        endLine()
        return lines
    }
}

/// Draws one crop of a printed page at a given scale.
enum PieceRenderer {
    static func image(for piece: Piece, in document: PDFDocument) -> UIImage? {
        guard let page = document.page(at: piece.page) else { return nil }
        let box = page.bounds(for: .mediaBox)
        let s = piece.scale
        let size = CGSize(width: piece.source.width * s, height: piece.source.height * s)
        guard size.width > 1, size.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            // page point (x, yTop) -> image ((x - sx) * s, (yTop - sy) * s), with yTop = box.maxY - yPDF
            cg.translateBy(x: -(piece.source.minX + box.minX) * s, y: (box.height - piece.source.minY) * s)
            cg.scaleBy(x: s, y: -s)
            cg.translateBy(x: 0, y: -box.minY)
            page.draw(with: .mediaBox, to: cg)
        }
    }
}
