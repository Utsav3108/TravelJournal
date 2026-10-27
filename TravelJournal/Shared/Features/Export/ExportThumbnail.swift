import SwiftUI
import SwiftData

/// Live preview of the first slice (the cover) at the chosen format's aspect. Redrawn after a short pause whenever the
/// format, the privacy or a stop's visibility changes; the render runs off the critical path of the sheet.
struct ExportThumbnail: View {
    let journey: Journey
    let options: ExportOptions
    /// Changes whenever a stop's visibility does.
    let stopSignature: [Bool?]

    @State private var image: CGImage?
    @State private var failed = false

    private struct Key: Hashable {
        var format: ExportFormat
        var privacy: ExportPrivacy
        var stops: [Bool?]
    }

    var body: some View {
        let aspect = options.format.spec.sliceSize
        ZStack {
            Rectangle().fill(KraftColor.paper)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable().scaledToFit()
                    .transition(.opacity)
            } else if failed {
                Image(systemName: "photo").foregroundStyle(KraftColor.inkSoft)
            } else {
                ProgressView()
            }
        }
        .aspectRatio(aspect.width / aspect.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(KraftColor.inkSoft.opacity(0.3)))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .animation(.easeInOut(duration: 0.2), value: image == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the first \(options.format == .pdf ? "page" : "slide")")
        .accessibilityIdentifier("exportThumbnail")
        .task(id: Key(format: options.format, privacy: options.privacy, stops: stopSignature)) {
            try? await Task.sleep(for: .milliseconds(300))   // debounce rapid toggling
            guard !Task.isCancelled else { return }
            await redraw()
        }
    }

    private func redraw() async {
        let spec = options.format.spec
        let snapshot = options.snapshot(for: journey)
        guard !snapshot.stops.isEmpty else { failed = true; image = nil; return }
        let model = snapshot.coverModel
        let provider = PDFImageProvider(source: journey.modelContext.map(ModelPhotoSource.init(context:)), maxPixel: 600)
        try? await provider.preload([model.heroPhotos])
        guard !Task.isCancelled else { return }
        let page = CoverPage(model: model, metrics: PageMetrics(size: spec.sliceSize, margin: spec.margins.left, mode: spec.mode))
            .environment(\.storyImageProvider, provider)
        let drawn = SliceImageRenderer.thumbnail(page, size: spec.sliceSize, maxPixel: 700)
        guard !Task.isCancelled else { return }
        image = drawn
        failed = drawn == nil
    }
}
