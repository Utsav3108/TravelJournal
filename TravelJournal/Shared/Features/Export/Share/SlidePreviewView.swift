import SwiftUI

/// Preview of exported slides / frames before sharing or saving. Placeholder from Wave 1: agent H replaces the
/// body (swipeable pages, share, Save to Photos). Keep `init(images:format:title:)` stable; the Export sheet uses it.
struct SlidePreviewView: View {
    let images: [URL]
    let format: ExportFormat
    let title: String

    init(images: [URL], format: ExportFormat, title: String) {
        self.images = images
        self.format = format
        self.title = title
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled").font(.largeTitle)
            Text(title).font(.headline)
            Text("\(images.count) \(format.displayName) image\(images.count == 1 ? "" : "s")")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
    }
}
