// Prints every character of a PDF's text layer with its box, exactly as the app gets them from
// PDFKit (flipped to a top-left origin), so engine tests can use real Apple data on Linux.
// Run on a Mac: swift tools/dump_pdf_text.swift App/Pageside/Resources/Sample-Paper.pdf > pdfkit-glyphs.json
// Shape: {"sizes": [[w, h]], "glyphs": [[[code, x, y, w, h], ...] per page]}; a glyph with no box has w = h = 0.
import Foundation
import PDFKit

guard CommandLine.arguments.count > 1, let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    FileHandle.standardError.write("usage: swift dump_pdf_text.swift file.pdf\n".data(using: .utf8)!); exit(1)
}
func round2(_ v: CGFloat) -> Double { (Double(v) * 100).rounded() / 100 }
var sizes: [[Double]] = []
var pages: [[[Double]]] = []
for i in 0..<doc.pageCount {
    guard let page = doc.page(at: i) else { continue }
    let box = page.bounds(for: .mediaBox)
    sizes.append([box.width, box.height])
    var glyphs: [[Double]] = []
    if let text = page.string as NSString? {
        for k in 0..<text.length {
            let r = page.characterBounds(at: k)
            let none = r.isNull || (r.width == 0 && r.height == 0)
            glyphs.append([Double(text.character(at: k)),
                           none ? 0 : round2(r.minX - box.minX), none ? 0 : round2(box.maxY - r.maxY),
                           none ? 0 : round2(r.width), none ? 0 : round2(r.height)])
        }
    }
    pages.append(glyphs)
}
let data = try! JSONSerialization.data(withJSONObject: ["sizes": sizes, "glyphs": pages])
FileHandle.standardOutput.write(data)
