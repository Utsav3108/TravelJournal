#if os(macOS)
import SwiftUI

/// Sizing for the photo popover: as large as the window allows (the leg card is 340 x 280), with a sensible floor and ceiling.
enum PhotoCardLayout {
    static let minSide: CGFloat = 420
    static let maxWidth: CGFloat = 1100
    static let maxHeight: CGFloat = 820
    /// Room the popover arrow and the window chrome take around the card.
    static let margin: CGFloat = 80

    nonisolated static func size(viewport: CGSize) -> CGSize {
        CGSize(width: min(max(viewport.width - margin, minSide), maxWidth),
               height: min(max(viewport.height - margin, minSide), maxHeight))
    }
}

/// A tapped photo, opened large in a popover like the leg card. The image is fitted, never cropped, on the same paper as the story.
struct PhotoCardView: View {
    let photo: StoryPhoto
    let size: CGSize

    @Environment(\.storyImageProvider) private var provider
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        content
            .padding(20)
            .frame(width: size.width, height: size.height)
            .background(PaperBackground())
            .accessibilityIdentifier("photoCard")
    }

    @ViewBuilder private var content: some View {
        if let cg = provider.image(for: photo, preferThumbnail: false,
                                   maxPixel: ImageDecoding.maxPixel(forPoints: max(size.width, size.height), scale: displayScale)) {
            Image(photo: cg, scale: displayScale, label: "Photo")
                .resizable().scaledToFit()
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        } else {
            KraftPhotoPlaceholder().aspectRatio(4.0 / 3.0, contentMode: .fit)
                .accessibilityLabel("Photo placeholder")
        }
    }
}
#endif
