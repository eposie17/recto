// Prints a PDF's text layer the way the app reads it (same rules as App/Recto/PDFText.swift),
// as JSON in the shape of RectoCore's test-paper.json, so engine tests can use real PDFKit data.
// Run on a Mac: swift tools/dump_pdf_text.swift App/Recto/Resources/Sample-Paper.pdf > pdfkit-paper.json
import Foundation
import PDFKit

func lines(on page: PDFPage, box: CGRect) -> [[(String, CGRect)]] {
    guard let text = page.string as NSString?, text.length > 0 else { return [] }
    var lines: [[(String, CGRect)]] = []
    var line: [(String, CGRect)] = []
    var word = ""
    var wordRect = CGRect.null
    func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX - box.minX, y: box.maxY - r.maxY, width: r.width, height: r.height)
    }
    func endLine() { if !line.isEmpty { lines.append(line) }; line = [] }
    func endWord() {
        guard !word.isEmpty, !wordRect.isNull else { word = ""; wordRect = .null; return }
        let r = flip(wordRect)
        if let last = line.last {
            let sameRow = abs(last.1.midY - r.midY) < max(last.1.height, r.height) * 0.5
            if !sameRow || r.minX < last.1.minX { endLine() }
        }
        line.append((word, r))
        word = ""; wordRect = .null
    }
    for i in 0..<text.length {
        let c = text.character(at: i)
        let isSpace = c == 0x20 || c == 0x09 || c == 0xA0
        let isBreak = c == 0x0A || c == 0x0D
        if isSpace || isBreak { endWord(); if isBreak { endLine() }; continue }
        let b = page.characterBounds(at: i)
        guard b.width > 0 || b.height > 0 else { continue }
        if let u = UnicodeScalar(c) { word.unicodeScalars.append(u) }
        wordRect = wordRect.union(b)
    }
    endWord(); endLine()
    return lines
}

guard CommandLine.arguments.count > 1, let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    FileHandle.standardError.write("usage: swift dump_pdf_text.swift file.pdf\n".data(using: .utf8)!); exit(1)
}
var sizes: [[Double]] = []
var pages: [[[[String: Any]]]] = []
for i in 0..<doc.pageCount {
    guard let page = doc.page(at: i) else { continue }
    let box = page.bounds(for: .mediaBox)
    sizes.append([box.width, box.height])
    pages.append(lines(on: page, box: box).map { $0.map { ["t": $0.0, "r": [$0.1.minX, $0.1.minY, $0.1.width, $0.1.height]] } })
}
let data = try! JSONSerialization.data(withJSONObject: ["sizes": sizes, "pages": pages])
FileHandle.standardOutput.write(data)
