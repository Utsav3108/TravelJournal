import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// The Export sheet and everything that follows it for `model`: the over-20 alert, the stop picker, progress,
    /// errors and the result (share sheet or Save panel for a PDF, slide preview for images). Attach once.
    func exportFlowPresentations(_ model: ExportFlowModel) -> some View {
        modifier(ExportFlowPresentations(model: model))
    }
}

extension ExportFlowModel {
    /// Steps shown inside the one sheet (the content swaps as the flow moves on).
    var showsSheet: Bool {
        switch step {
        case .idle, .pdfSave: false
        case .pdfReady: !savesPDFWithPanel
        default: true
        }
    }
}

private struct ExportFlowPresentations: ViewModifier {
    @Bindable var model: ExportFlowModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { model.showsSheet },
                                        set: { if !$0, model.showsSheet { model.dismiss() } })) {
                ExportFlowSheet(model: model)
            }
            #if os(macOS)
            .fileExporter(isPresented: Binding(get: { if case .pdfSave = model.step { true } else { false } },
                                               set: { if !$0 { model.saveFinished() } }),
                          document: pdfDocument, contentType: .pdf,
                          defaultFilename: pdfName) { model.saveFinished($0) }
            #endif
    }

    #if os(macOS)
    private var pdfDocument: PDFFileDocument? {
        if case .pdfSave(let data, _) = model.step { PDFFileDocument(data: data) } else { nil }
    }

    private var pdfName: String {
        if case .pdfSave(_, let name) = model.step { name } else { "Journey" }
    }
    #endif
}

/// The sheet's content for the current step. The alerts sit on the content, so they appear over the sheet.
private struct ExportFlowSheet: View {
    @Bindable var model: ExportFlowModel

    var body: some View {
        Group {
            switch model.step {
            case .options, .askingCarousel:
                NavigationStack {
                    ExportSheet(model: model)
                        .navigationTitle("Export")
                        .inlineNavigationTitle()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { model.dismiss() }.accessibilityIdentifier("exportCancelSheet")
                            }
                        }
                }
            case .picking:
                NavigationStack { StopPickerView(model: model) }
            case .exporting:
                ExportProgressView(model: model)
            case .pdfReady(let url):
                #if os(iOS)
                PDFReadyView(url: url, note: model.note) { model.dismiss() }
                #else
                EmptyView()
                #endif
            case .slides(let urls):
                SlidePreviewView(images: urls, format: model.format, title: model.journey.title)
            case .idle, .pdfSave:
                Color.clear
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 520, idealHeight: 680)
        #endif
        .presentationDetents(detents)
        .interactiveDismissDisabled(model.isExporting)
        .alert("Instagram carousel", isPresented: Binding(
            get: { if case .askingCarousel = model.step { true } else { false } },
            set: { if !$0, case .askingCarousel = model.step { model.backToOptions() } })) {
            Button("Yes") { model.chooseCarouselAnyway() }
            Button("No") { model.declineCarousel() }
        } message: {
            Text("This journey needs \(slides) slides. Instagram allows \(model.maxSlices) per post. "
                 + "Make an Instagram carousel anyway?")
        }
        .alert("Couldn't export", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var slides: Int { if case .askingCarousel(let n) = model.step { n } else { 0 } }

    private var detents: Set<PresentationDetent> {
        switch model.step {
        case .exporting: [.height(240)]
        case .pdfReady: [.height(300), .medium]
        default: [.large]
        }
    }
}

private struct ExportProgressView: View {
    let model: ExportFlowModel

    var body: some View {
        let p = model.progress
        VStack(spacing: 16) {
            Text("Making your export").font(.headline)
            ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
            Text(p.done == 0 ? "Preparing map and photos" : "\(min(p.done, p.total)) of \(p.total)")
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("exportProgressText")
            Button("Cancel", role: .cancel) { model.cancel() }
                #if os(macOS)
                .keyboardShortcut(.cancelAction)
                #endif
                .accessibilityIdentifier("exportCancel")
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 320)
        #endif
    }
}

/// Which stops go into the carousel, with the live slide count. Export only works at or under the limit.
private struct StopPickerView: View {
    @Bindable var model: ExportFlowModel

    var body: some View {
        let count = model.pickerCount
        let over = count > model.maxSlices
        List {
            Section {
                ForEach(model.visibleStops) { stop in
                    Button {
                        model.togglePicked(stop)
                    } label: {
                        HStack {
                            Image(systemName: model.pickerSelection.contains(stop.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.pickerSelection.contains(stop.id) ? KraftColor.ink : KraftColor.inkSoft)
                            Text(stop.placeName.isEmpty ? "Untitled stop" : stop.placeName)
                                .foregroundStyle(KraftColor.ink).lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pickStop-\(stop.id.uuidString)")
                }
            } header: {
                Text("Choose stops")
            } footer: {
                Text("Stops hidden for privacy aren't listed.")
            }
        }
        .navigationTitle("Choose stops")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { model.backToOptions() }.accessibilityIdentifier("pickerBack")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Divider()
                Text("\(count)/\(model.maxSlices) slides")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(over ? Color.red : KraftColor.ink)
                    .accessibilityIdentifier("pickerCount")
                if over {
                    Text("Instagram allows \(model.maxSlices) per post. Deselect some stops.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    model.exportPicked()
                } label: {
                    Text("Export").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!model.canPickerExport)
                .accessibilityIdentifier("pickerExport")
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
            .background(.bar)
        }
    }
}

#if os(iOS)
/// Shown when the PDF is ready. `ShareLink` replaces the UIKit activity sheet; it needs one tap, so the sheet offers it.
private struct PDFReadyView: View {
    let url: URL
    let note: String?
    let done: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Your PDF is ready").font(.headline)
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .accessibilityIdentifier("exportPDFNote")
            }
            ShareLink(item: url) {
                Label("Share PDF", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .accessibilityIdentifier("sharePDF")
            Button("Done", action: done).accessibilityIdentifier("shareDone")
        }
        .padding(24)
    }
}
#endif
