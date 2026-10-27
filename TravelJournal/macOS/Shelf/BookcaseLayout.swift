#if os(macOS)
import SwiftUI

/// Places one subview per `BookcaseReflow` item at its slot. A custom `Layout` (not `.position`) so that a resize
/// animates each book sliding to its new shelf, hit-testing stays on the book, and `scrollTo` finds real frames.
struct BookcaseLayout: Layout {
    var reflow: BookcaseReflow
    var minHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: max(reflow.contentHeight, minHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() where index < reflow.items.count {
            let c = reflow.center(ofItem: index, width: bounds.width)
            subview.place(at: CGPoint(x: bounds.minX + c.x, y: bounds.minY + c.y), anchor: .center,
                          proposal: ProposedViewSize(BookcaseReflow.bookSize))
        }
    }
}
#endif
