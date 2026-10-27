import SwiftUI

/// "Made with TravelJournal" brand stamp, in the double-ruled teal stamp style of `RouteEndMarker`.
/// Drawn on the PDF closing page, the last carousel slide and the closing Story frame when
/// `ExportPrivacy.showBrandStamp` is on. Fills exactly `size` (text shrinks to fit), so composers can reserve a rect.
struct MadeWithStamp: View {
    /// Natural size at 1x; scale it for larger slices.
    static let defaultSize = CGSize(width: 210, height: 40)
    static let text = "Made with TravelJournal"

    var size: CGSize = MadeWithStamp.defaultSize
    var seed: String = "made-with"

    var body: some View {
        let fontSize = min(14, size.height * 0.36)
        Text(Self.text)
            .font(KraftFont.label(fontSize))
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(KraftColor.stampTeal)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 10)
            .frame(width: size.width - 8, height: size.height - 8)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 5).stroke(KraftColor.stampTeal, lineWidth: 1.6)
                    RoundedRectangle(cornerRadius: 5).stroke(KraftColor.stampTeal.opacity(0.6), lineWidth: 0.7).padding(3)
                }
            )
            .opacity(0.9)
            .seededRotation(seed, limit: 2)
            .frame(width: size.width, height: size.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.text)
    }
}

#Preview {
    MadeWithStamp().padding().background(KraftColor.paper)
}
