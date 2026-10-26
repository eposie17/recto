import Foundation

// The text of a paper, as read from the PDF text layer.
// All rects are in page points with the origin at the top left of the page.
// (PDFKit uses a bottom-left origin; the app flips once when it builds this.)

public struct Word: Codable, Equatable, Sendable {
    public var id: Int          // index in reading order across the whole document
    public var text: String
    public var rect: CGRect
    public var lineID: Int

    public init(id: Int, text: String, rect: CGRect, lineID: Int) {
        self.id = id; self.text = text; self.rect = rect; self.lineID = lineID
    }
}

public struct TextLine: Codable, Equatable, Sendable {
    public var id: Int          // index in reading order across the whole document
    public var page: Int
    public var rect: CGRect
    public var wordIDs: ClosedRange<Int>

    public init(id: Int, page: Int, rect: CGRect, wordIDs: ClosedRange<Int>) {
        self.id = id; self.page = page; self.rect = rect; self.wordIDs = wordIDs
    }
}

public struct Sentence: Codable, Equatable, Sendable {
    public var id: Int
    public var wordIDs: ClosedRange<Int>
}

public struct PageInfo: Codable, Equatable, Sendable {
    public var size: CGSize
    public var lineIDs: [Int]
}

public struct DocumentText: Sendable {
    public private(set) var pages: [PageInfo]
    public private(set) var lines: [TextLine]
    public private(set) var words: [Word]
    public private(set) var sentences: [Sentence]
    private var sentenceOfWord: [Int]

    /// Build from raw lines per page. Each line is its words (text + rect), already in reading order.
    public init(pageSizes: [CGSize], linesPerPage: [[[(String, CGRect)]]]) {
        var pages: [PageInfo] = []
        var lines: [TextLine] = []
        var words: [Word] = []
        for (p, size) in pageSizes.enumerated() {
            var ids: [Int] = []
            let raw = p < linesPerPage.count ? linesPerPage[p] : []
            for lineWords in raw where !lineWords.isEmpty {
                let lineID = lines.count
                let first = words.count
                var box = CGRect.null
                for (text, rect) in lineWords {
                    words.append(Word(id: words.count, text: text, rect: rect, lineID: lineID))
                    box = box.union(rect)
                }
                lines.append(TextLine(id: lineID, page: p, rect: box, wordIDs: first...(words.count - 1)))
                ids.append(lineID)
            }
            pages.append(PageInfo(size: size, lineIDs: ids))
        }
        self.pages = pages
        self.lines = lines
        self.words = words
        (self.sentences, self.sentenceOfWord) = DocumentText.splitSentences(words)
    }

    public func sentence(ofWord id: Int) -> Sentence? {
        guard id >= 0, id < sentenceOfWord.count else { return nil }
        return sentences[sentenceOfWord[id]]
    }

    public func sentence(ofLine id: Int) -> Sentence? {
        guard id >= 0, id < lines.count else { return nil }
        return sentence(ofWord: lines[id].wordIDs.lowerBound)
    }

    // Short words that end in a full stop but do not end a sentence.
    static let abbreviations: Set<String> = [
        "fig.", "figs.", "eq.", "eqs.", "e.g.", "i.e.", "et", "al.", "vs.", "cf.", "ref.", "refs.",
        "sec.", "no.", "dr.", "mr.", "ms.", "approx.", "resp.", "tab.",
    ]

    static func splitSentences(_ words: [Word]) -> ([Sentence], [Int]) {
        var sentences: [Sentence] = []
        var owner = Array(repeating: 0, count: words.count)
        var start = 0
        for (i, w) in words.enumerated() {
            owner[i] = sentences.count
            let t = w.text.lowercased()
            let ends = (t.hasSuffix(".") || t.hasSuffix("?") || t.hasSuffix("!")) && !abbreviations.contains(t)
            if ends || i == words.count - 1 {
                sentences.append(Sentence(id: sentences.count, wordIDs: start...i))
                start = i + 1
            }
        }
        return (sentences, owner)
    }
}
