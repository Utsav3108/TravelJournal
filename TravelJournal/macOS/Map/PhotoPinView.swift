#if os(macOS)
import SwiftUI

/// A round photo with a white ring and a small pointer, used as a story's pin on the map. Falls back to the red
/// map pin when the story has no photo.
struct PhotoPinView: View {
    let photo: StopPhoto?
    var size: CGFloat = 46

    var body: some View {
        if let cg = StoredPhotos.image(photo: photo, maxPixel: Int(size * 3)) {
            VStack(spacing: -3) {
                Image(decorative: cg, scale: 1)
                    .resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 10)).foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        } else {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
        }
    }
}
#endif
