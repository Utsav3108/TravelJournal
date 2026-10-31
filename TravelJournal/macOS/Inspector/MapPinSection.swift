#if os(macOS)
import SwiftUI

/// "Map pin" in the cover editor: which of the story's photos is shown as its pin on the map. The default follows
/// the cover photo.
struct MapPinSection: View {
    @Bindable var journey: Journey

    var body: some View {
        let photos = journey.allPhotos
        if !photos.isEmpty {
            let current = journey.mapPinPhoto?.id
            Section("Map pin") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photos) { photo in
                            Button { journey.mapPinPhotoID = photo.id } label: {
                                thumb(photo, selected: photo.id == current)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Use this photo as the map pin")
                        }
                    }
                    .padding(.vertical, 4)
                }
                if journey.mapPinPhotoID != nil {
                    Button("Use cover photo") { journey.mapPinPhotoID = nil }
                        .accessibilityIdentifier("mapPinReset")
                }
            }
        }
    }

    private func thumb(_ photo: StopPhoto, selected: Bool) -> some View {
        Group {
            if let cg = StoredPhotos.image(photo: photo, maxPixel: 120) {
                Image(decorative: cg, scale: 1).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay(Circle().stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
    }
}
#endif
