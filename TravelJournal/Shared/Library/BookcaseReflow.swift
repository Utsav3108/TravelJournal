import Foundation
import CoreGraphics

/// Pure layout for the Mac bookcase: how many face-out books fit per shelf, how many shelves fit the window, and
/// where the "+N books" / "Show less" tile goes. Views place their slots with `center(ofItem:width:)`.
struct BookcaseReflow: Equatable, Sendable {
    enum Item: Equatable, Sendable {
        case book(Int)              // index into the (searched, sorted) story list
        case more(hidden: Int)      // "+N books": the last slot of the last visible shelf
        case less                   // "Show less": after the last book when expanded
    }

    enum Direction: Sendable { case left, right, up, down }

    static let bookSize = CGSize(width: 160, height: 220)
    static let columnGap: CGFloat = 28
    static let sideInset: CGFloat = 32
    static let roomAbove: CGFloat = 28
    static let plankHeight: CGFloat = 16
    /// One shelf: room above the book, the book, and the plank it stands on.
    static let shelfHeight: CGFloat = roomAbove + bookSize.height + plankHeight

    let perShelf: Int
    static let maxShelves = 3           // the collapsed bookcase never grows past this; the rest hide behind "+N books"

    let fitShelves: Int                 // shelves the collapsed bookcase may use: fits the window, 1...maxShelves (2 when one book per shelf)
    /// Space above the first shelf so a bookcase that is shorter than the window sits in its vertical centre.
    let topInset: CGFloat
    let items: [Item]
    let canExpand: Bool                 // more journeys than the collapsed bookcase shows

    var rows: Int { items.isEmpty ? 0 : (items.count + perShelf - 1) / perShelf }
    /// Planks drawn on the wall: only the shelves in use (one when the library is empty). The bookcase grows a shelf
    /// at a time as books are added, up to `fitShelves`.
    var wallRows: Int { max(rows, 1) }
    var contentHeight: CGFloat { CGFloat(wallRows) * Self.shelfHeight + 2 * topInset }
    /// Books you can select and open (tiles excluded).
    var visibleBookCount: Int { items.reduce(0) { if case .book = $1 { $0 + 1 } else { $0 } } }

    static func layout(count: Int, size: CGSize, expanded: Bool) -> BookcaseReflow {
        let usable = max(size.width - 2 * sideInset, bookSize.width)
        let perShelf = max(1, Int((usable + columnGap) / (bookSize.width + columnGap)))
        var fit = min(maxShelves, max(1, Int(size.height / shelfHeight)))
        if perShelf * fit < 2 { fit = 2 }       // never a bookcase whose only slot is the tile
        let capacity = perShelf * fit
        let overflow = count > capacity

        let items: [Item]
        if count == 0 {
            items = []
        } else if !overflow {
            items = (0..<count).map { .book($0) }
        } else if expanded {
            items = (0..<count).map { .book($0) } + [.less]
        } else {
            items = (0..<(capacity - 1)).map { .book($0) } + [.more(hidden: count - (capacity - 1))]
        }
        let rows = items.isEmpty ? 1 : (items.count + perShelf - 1) / perShelf
        let inset = max(0, (size.height - CGFloat(rows) * shelfHeight) / 2)
        return BookcaseReflow(perShelf: perShelf, fitShelves: fit, topInset: inset, items: items, canExpand: overflow)
    }

    /// Centre of slot `index` in a bookcase `width` wide (origin top-left). Rows are centred as a group.
    func center(ofItem index: Int, width: CGFloat) -> CGPoint {
        let row = index / perShelf, column = index % perShelf
        let rowWidth = CGFloat(perShelf) * Self.bookSize.width + CGFloat(perShelf - 1) * Self.columnGap
        let left = max(0, (width - rowWidth) / 2)
        let x = left + CGFloat(column) * (Self.bookSize.width + Self.columnGap) + Self.bookSize.width / 2
        let y = topInset + CGFloat(row) * Self.shelfHeight + Self.roomAbove + Self.bookSize.height / 2
        return CGPoint(x: x, y: y)
    }

    /// Arrow-key selection over the visible books. No selection yet: any arrow selects the first book.
    static func moveSelection(from index: Int?, direction: Direction, perShelf: Int, bookCount: Int) -> Int? {
        guard bookCount > 0 else { return nil }
        guard let i = index, (0..<bookCount).contains(i) else { return 0 }
        switch direction {
        case .left: return max(0, i - 1)
        case .right: return min(bookCount - 1, i + 1)
        case .up: return i - perShelf >= 0 ? i - perShelf : i
        case .down:
            let lastRow = (bookCount - 1) / perShelf
            guard i / perShelf < lastRow else { return i }
            return min(bookCount - 1, i + perShelf)
        }
    }
}
