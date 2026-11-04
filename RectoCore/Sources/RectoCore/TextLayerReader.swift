import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Builds words and lines from a page's characters, as a PDF text layer gives them.
///
/// PDFKit's page text does not always put a space or line break where a printed line ends,
/// and its character boxes are tight around each glyph. So the breaks come from where the
/// characters sit: a jump back to the left or down to another row starts a new line.
public enum TextLayerReader {
    /// One character of the page text, in reading order. `rect` is in page points with a top-left
    /// origin, or empty for characters with no box (spaces, line breaks).
    public struct Glyph: Sendable {
        public var code: UInt16
        public var rect: CGRect
        public init(code: UInt16, rect: CGRect) { self.code = code; self.rect = rect }
    }

    public static func lines(_ glyphs: [Glyph]) -> [[(String, CGRect)]] {
        var lines: [[(String, CGRect)]] = []
        var line: [(String, CGRect)] = []
        var word: [UInt16] = []
        var wordRect = CGRect.null
        var prev: CGRect? = nil      // the last character with a box, on the current line

        func endWord() {
            if !word.isEmpty, !wordRect.isNull { line.append((String(utf16CodeUnits: word, count: word.count), wordRect)) }
            word = []; wordRect = .null
        }
        func endLine() {
            endWord()
            if !line.isEmpty { lines.append(even(line)) }
            line = []; prev = nil
        }

        for g in glyphs {
            switch g.code {
            case 0x0A, 0x0D: endLine(); continue
            case 0x20, 0x09, 0xA0: endWord(); continue
            default: break
            }
            let b = g.rect
            guard !b.isNull, b.width > 0 || b.height > 0 else { continue }
            if let p = prev {
                let h = max(p.height, b.height, 3)
                // Bottoms differ by a descender at most within a row; a new row is a line apart.
                let newRow = abs(b.maxY - p.maxY) > h * 0.7 && (b.minY > p.maxY - 1 || b.maxY < p.minY + 1)
                let backLeft = b.minX < p.minX - 1
                let farRight = b.minX - p.maxX > h * 3
                if newRow || backLeft || farRight { endLine() }
                else if b.minX - p.maxX > h * 0.6 { endWord() }   // a gap with no space character
            }
            word.append(g.code)
            wordRect = wordRect.union(b)
            prev = b
        }
        endLine()
        return lines
    }

    /// Glyph boxes are tight, so "a" is shorter than "Tg". Give every word on a line the line's
    /// full height, so line boxes are steady and crops never cut off tall letters or descenders.
    static func even(_ line: [(String, CGRect)]) -> [(String, CGRect)] {
        let top = line.map(\.1.minY).min()!, bottom = line.map(\.1.maxY).max()!
        return line.map { ($0.0, CGRect(x: $0.1.minX, y: top, width: $0.1.width, height: bottom - top)) }
    }
}
