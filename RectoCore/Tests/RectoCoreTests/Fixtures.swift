import Foundation
@testable import RectoCore

/// A made-up two-column paper laid out like a typical journal page (US Letter, 612 x 792 points).
enum Fixture {
    static let pageSize = CGSize(width: 612, height: 792)
    static let leftColumn: ClosedRange<CGFloat> = 54...300
    static let rightColumn: ClosedRange<CGFloat> = 312...558

    static func line(x0: CGFloat, x1: CGFloat, y: CGFloat, words: [String]) -> [(String, CGRect)] {
        let step = (x1 - x0) / CGFloat(words.count)
        return words.enumerated().map { i, w in
            (w, CGRect(x: x0 + CGFloat(i) * step, y: y, width: step - 4, height: 9))
        }
    }

    static func paper(pages: Int = 3) -> DocumentText {
        var all: [[[(String, CGRect)]]] = []
        var n = 0
        for p in 0..<pages {
            var lines: [[(String, CGRect)]] = []
            var top: CGFloat = 60
            if p == 0 {
                // A title and an author line across both columns.
                lines.append(line(x0: 90, x1: 522, y: 60, words: ["A", "Study", "of", "Facing", "Pages."]))
                lines.append(line(x0: 160, x1: 452, y: 80, words: ["Posi", "and", "Others."]))
                top = 120
            }
            for column in [leftColumn, rightColumn] {
                var y = top
                while y < 740 {
                    n += 1
                    let last = n % 3 == 0 ? "end." : "more"
                    let mid = n % 7 == 0 ? "Fig." : "text"
                    lines.append(line(x0: column.lowerBound, x1: column.upperBound, y: y,
                                      words: ["w\(n)", "line", mid, "and", "so", last]))
                    y += 12
                }
            }
            all.append(lines)
        }
        return DocumentText(pageSizes: Array(repeating: pageSize, count: pages), linesPerPage: all)
    }
}
