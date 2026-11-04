import Observation
import PDFKit
import RectoCore

/// The app's single model object for an open paper. All state lives in RectoCore's ReaderState;
/// this class only makes it observable, loads the PDF and saves the record next to it.
@Observable
final class ReaderModel {
    let document: PDFDocument
    let title: String
    private(set) var state: ReaderState
    private let recordURL: URL

    /// Bumped whenever marks change, so the ink layer knows to redraw.
    private(set) var marksVersion = 0

    init?(url: URL) {
        guard let doc = PDFDocument(url: url) else { return nil }
        document = doc
        title = url.deletingPathExtension().lastPathComponent
        recordURL = ReaderModel.recordURL(for: url)
        let record = (try? Data(contentsOf: recordURL)).flatMap { try? PaperRecord.decode($0) } ?? PaperRecord()
        state = ReaderState(text: PDFText.read(doc), record: record, environment: .iPhone)
    }

    static func recordURL(for pdf: URL) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = pdf.deletingPathExtension().lastPathComponent
        let url = docs.appendingPathComponent(name + ".pageside.json")
        // Notes saved before the rename used the old name; move them over once.
        let old = docs.appendingPathComponent(name + ".recto.json")
        if !FileManager.default.fileExists(atPath: url.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: url)
        }
        return url
    }

    // MARK: Changes from the views

    func setEnvironment(_ env: WindowEnvironment) {
        guard env != state.environment else { return }
        state.setEnvironment(env)
    }

    func scroll(to y: CGFloat) { state.scroll(to: y) }

    func finishStroke(_ points: [CGPoint]) {
        state.finishStroke(points)
        marksChanged()
    }

    func undo() { state.undoPaper(); marksChanged() }
    func redo() { state.redoPaper(); marksChanged() }

    func toggleWrite() { state.writeMode.toggle() }
    func setTool(_ t: PaperTool) { state.tool = t }
    func setColor(_ c: InkColor) { state.color = c }
    func swapSides() { state.swapSides(); save() }
    func setBandOpen(_ open: Bool) { state.setBandOpen(open) }
    func setFacing(_ f: FacingMode) { state.setFacing(f) }
    func setSingleShows(_ s: SinglePageShows) { state.setSingleShows(s) }
    func setView(_ v: PaperView?) { state.setView(v); save() }

    /// Until text selection lands, a quick way to try Quote cards: quote the line at the top.
    func quoteTopLine() {
        guard let id = state.position?.lineID else { return }
        state.quote(wordIDs: state.text.lines[id].wordIDs)
        save()
    }

    private func marksChanged() {
        marksVersion += 1
        save()
    }

    func save() {
        guard let data = try? state.record.encoded() else { return }
        try? data.write(to: recordURL, options: .atomic)
    }
}
