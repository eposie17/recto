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

    /// The page's characters with their boxes, flipped to a top-left origin. RectoCore pairs
    /// them up and turns them into words and lines (TextLayerReader), so the rules are tested on
    /// Linux with real PDFKit data (tools/dump_pdf_text.swift).
    private static func lines(on page: PDFPage, box: CGRect) -> [[(String, CGRect)]] {
        guard let text = page.string as NSString?, text.length > 0 else { return [] }
        var codes: [UInt16] = [], bounds: [CGRect] = []
        codes.reserveCapacity(text.length); bounds.reserveCapacity(text.length)
        for i in 0..<text.length {
            codes.append(text.character(at: i))
            let r = page.characterBounds(at: i)
            bounds.append(r.isNull || (r.width == 0 && r.height == 0) ? .null
                          : CGRect(x: r.minX - box.minX, y: box.maxY - r.maxY, width: r.width, height: r.height))
        }
        return TextLayerReader.lines(TextLayerReader.glyphs(codes: codes, bounds: bounds))
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
