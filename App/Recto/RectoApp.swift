import SwiftUI
import UniformTypeIdentifiers

@main
struct RectoApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
    }
}

/// A first, plain library: the sample paper and any PDF you import from Files.
struct LibraryView: View {
    @State private var papers: [URL] = LibraryView.load()
    @State private var importing = false
    @State private var open: ReaderModel?

    var body: some View {
        NavigationStack {
            List {
                ForEach(papers, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) { open = ReaderModel(url: url) }
                        .frame(minHeight: 44)
                }
            }
            .navigationTitle("Recto")
            .toolbar {
                Button { importing = true } label: { Label("Import PDF", systemImage: "plus") }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
                guard case let .success(url) = result else { return }
                if let copy = LibraryView.copyIn(url) { papers = LibraryView.load(); open = ReaderModel(url: copy) }
            }
            .fullScreenCover(item: $open) { model in
                ReaderView(model: model, onClose: { open = nil })
            }
        }
    }

    static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func load() -> [URL] {
        var urls: [URL] = []
        if let sample = Bundle.main.url(forResource: "Sample-Paper", withExtension: "pdf") { urls.append(sample) }
        let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        urls += files.filter { $0.pathExtension.lowercased() == "pdf" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return urls
    }

    static func copyIn(_ url: URL) -> URL? {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let dest = docs.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.copyItem(at: url, to: dest); return dest } catch { return nil }
    }
}

extension ReaderModel: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(self) }
}
