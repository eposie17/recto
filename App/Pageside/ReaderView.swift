import SwiftUI
import RectoCore

struct ReaderView: View {
    @State var model: ReaderModel
    /// Back to the library. It lives in the bar with the other buttons so it never covers the paper.
    var onClose: () -> Void = {}
    @State private var foldOverride: FoldOverride = .system
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let st = model.state
            ZStack(alignment: .topLeading) {
                SheetRepresentable(model: model, surface: st.surface, view: st.layout.view, scrollY: st.scrollY,
                                   marksVersion: model.marksVersion, writeMode: st.writeMode)
                facingPage(st)
                inkTabs(st)
                if let bar = st.surface.sideBar {
                    sideBar.frame(width: bar.width, height: bar.height).position(x: bar.midX, y: bar.midY)
                } else {
                    topBar.frame(width: geo.size.width, height: Surface.topBarHeight)
                }
            }
            .onAppear { relayout(geo.size) }
            .onChange(of: geo.size) { _, size in relayout(size) }
            .onChange(of: foldOverride) { _, _ in relayout(geo.size) }
        }
        .navigationBarHidden(true)
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.save() } }
    }

    private func relayout(_ size: CGSize) {
        model.setEnvironment(WindowEnvironment(size: size, fold: Fold.fold(in: size, override: foldOverride)))
    }

    // MARK: Facing page (when it is not the margin)

    @ViewBuilder private func facingPage(_ st: ReaderState) -> some View {
        if let page = st.surface.notebookPage {
            NotebookPageView(page: st.record.notebook.pages.last ?? NotebookPage())
                .frame(width: Surface.notebookPage.width, height: Surface.notebookPage.height)
                .scaleEffect(st.surface.notebookScale, anchor: .topLeading)
                .offset(x: page.minX, y: page.minY)
        } else if let face = st.surface.facing {
            Text(placeholder(for: st.settings.facing))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(width: face.width, height: face.height)
                .background(Color(.secondarySystemBackground))
                .offset(x: face.minX, y: face.minY)
        }
    }

    private func placeholder(for mode: FacingMode) -> String {
        switch mode {
        case .samePaper: return "Same paper comes in week 5."
        case .figures: return "Figures and tables come in week 5."
        case .anotherPaper: return "Another paper comes in weeks 6 and 7."
        default: return ""
        }
    }

    // MARK: Ink tabs for ink the view does not show

    @ViewBuilder private func inkTabs(_ st: ReaderState) -> some View {
        let paper = st.surface.paper
        ForEach(Array(st.inkTabs.enumerated()), id: \.offset) { _, tab in
            Button {
                if tab.kind == .ink { model.swapSides() } else { model.setSingleShows(.notes) }
            } label: {
                Text(tab.kind == .ink ? "ink" : "more").font(.caption2.bold())
                    .padding(.horizontal, 6).frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .position(x: tab.side == .right ? paper.maxX - 24 : paper.minX + 24, y: tab.screenY)
            .accessibilityLabel(tab.kind == .ink ? "Show notes on the other side" : "Show the whole margin")
        }
    }

    // MARK: Bars

    private var topBar: some View {
        // Scrolls sideways if a narrow phone cannot fit every button.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                barButtons(compact: false)
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var sideBar: some View {
        ScrollView {
            VStack(spacing: 2) { barButtons(compact: true) }.padding(.vertical, 6)
        }
        .background(.bar)
    }

    @ViewBuilder private func barButtons(compact: Bool) -> some View {
        let st = model.state
        let single = st.surface.arrangement == .single
        BarButton(title: "Library", icon: "books.vertical", compact: compact) {
            model.save()
            onClose()
        }
        BarButton(title: st.writeMode ? "Done" : "Write", icon: st.writeMode ? "checkmark" : "pencil.tip", compact: compact) {
            model.toggleWrite()
        }
        if st.writeMode {
            Menu { ForEach([PaperTool.pen, .highlighter, .eraser], id: \.self) { t in
                Button { model.setTool(t) } label: { Label(t.rawValue.capitalized, systemImage: st.tool == t ? "checkmark" : "") }
            } } label: { BarLabel(title: st.tool.rawValue.capitalized, icon: "scribble", compact: compact) }
            Menu { ForEach(InkColor.paperColors, id: \.self) { c in
                Button { model.setColor(c) } label: { Label(c.rawValue.capitalized, systemImage: st.color == c ? "checkmark" : "circle.fill") }
            } } label: { BarLabel(title: st.color.rawValue.capitalized, icon: "paintpalette", compact: compact) }
            BarButton(title: "Undo", icon: "arrow.uturn.backward", compact: compact) { model.undo() }
                .disabled(!st.paperHistory.canUndo)
            BarButton(title: "Redo", icon: "arrow.uturn.forward", compact: compact) { model.redo() }
                .disabled(!st.paperHistory.canRedo)
        }
        if single {
            BarButton(title: st.settings.singleShows == .paper ? "Notes" : "Paper",
                      icon: st.settings.singleShows == .paper ? "note.text" : "doc.text", compact: compact) {
                model.setSingleShows(st.settings.singleShows == .paper ? .notes : .paper)
            }
        } else {
            Menu {
                Button("Notes: Margin") { model.setFacing(.margin) }
                Button("Notes: Notebook") { model.setFacing(.notebook) }
                Button("Same paper") { model.setFacing(.samePaper) }
                Button("Figures and tables") { model.setFacing(.figures) }
                Button("Another paper") { model.setFacing(.anotherPaper) }
            } label: { BarLabel(title: "Facing", icon: "book", compact: compact) }
        }
        Menu {
            Button("Follow the width") { model.setView(nil) }
            Button("Columns") { model.setView(.columns) }
            Button("Page") { model.setView(.page) }
        } label: { BarLabel(title: st.layout.view == .columns ? "Columns" : "Page",
                            icon: st.layout.view == .columns ? "rectangle.split.2x1" : "doc", compact: compact) }
        Menu {
            if single {
                Button(st.settings.bandOpen ? "Close the margin band" : "Open the margin band (phone closed)") {
                    model.setBandOpen(!st.settings.bandOpen)
                }
                Button("Notes: Margin") { model.setFacing(.margin) }
                Button("Notes: Notebook") { model.setFacing(.notebook) }
            }
            Button("Swap sides") { model.swapSides() }
            Button("Quote the line at the top") { model.quoteTopLine() }
            Picker("Pretend fold (testing)", selection: $foldOverride) {
                ForEach(FoldOverride.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: { BarLabel(title: "More", icon: "ellipsis.circle", compact: compact) }
    }
}

struct BarLabel: View {
    let title: String
    let icon: String
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                VStack(spacing: 2) {
                    Image(systemName: icon).font(.system(size: 17))
                    Text(title).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(width: 52, height: 48)
            } else {
                Label(title, systemImage: icon).font(.subheadline).frame(minHeight: 44).padding(.horizontal, 6)
            }
        }
        .contentShape(Rectangle())
    }
}

struct BarButton: View {
    let title: String
    let icon: String
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { BarLabel(title: title, icon: icon, compact: compact) }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
    }
}

/// A fixed-size notebook page: typed blocks and Quote cards, each where it was placed.
struct NotebookPageView: View {
    let page: NotebookPage

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(.systemBackground)).shadow(radius: 1)
            ForEach(page.blocks) { block in
                Group {
                    switch block.kind {
                    case .typed(let t):
                        Text(t).font(.body)
                    case let .quote(excerpt, _, pageNumber):
                        VStack(alignment: .leading, spacing: 4) {
                            Text("“\(excerpt)”").font(.callout).lineLimit(3)
                            Text("p. \(pageNumber)").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                    }
                }
                .frame(width: block.frame.width, height: block.frame.height, alignment: .topLeading)
                .offset(x: block.frame.minX, y: block.frame.minY)
            }
        }
    }
}
