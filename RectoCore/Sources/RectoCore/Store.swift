import Foundation

/// Everything Recto saves for one paper, written next to the PDF as JSON.
/// The PDF itself is never changed until export.
public struct PaperRecord: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = PaperRecord.currentVersion
    public var marks = PaperMarks()
    public var notebook = Notebook()
    public var position: ReadingPosition?
    public var viewChoice: PaperView?
    public var notesSide: MarginSide = .right

    public init() {}

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> PaperRecord {
        let r = try JSONDecoder().decode(PaperRecord.self, from: data)
        guard r.version <= currentVersion else { throw StoreError.newerVersion(r.version) }
        return r
    }
}

public enum StoreError: Error, Equatable { case newerVersion(Int) }
