import Foundation
import SwiftData
import SwiftUI

/// All stop mutations go through here so `orderIndex` stays dense and legs stay in sync.
@MainActor
struct JourneyEditor {
    let context: ModelContext
    let photos: PhotoStoring
    /// When set (the Mac journey window), add / move / delete register undo steps with it. iPhone passes nil.
    let undoManager: UndoManager?

    init(context: ModelContext, photos: PhotoStoring, undoManager: UndoManager? = nil) {
        self.context = context
        self.photos = photos
        self.undoManager = undoManager
    }

    func addStop(_ stop: Stop, to journey: Journey, at index: Int? = nil) {
        insert(stop, into: journey, at: index)
        registerUndo(target: journey, name: "Add Stop") { $0.deleteStop(stop, in: journey) }
    }

    func moveStops(in journey: Journey, from: IndexSet, to: Int) {
        var list = journey.orderedStops
        let before = list.map(\.id)
        let legs = LegContentMap(journey)
        list.move(fromOffsets: from, toOffset: to)
        apply(list, in: journey)
        registerUndo(target: journey, name: "Move Stop") { $0.restoreOrder(before, legs: legs, in: journey) }
    }

    func deleteStop(_ stop: Stop, in journey: Journey) {
        let snapshot = StopSnapshot(stop, index: stop.orderIndex)
        undoManager?.removeAllActions(withTarget: stop)   // edits to a stop that is about to be rebuilt as a new object
        let list = journey.orderedStops.filter { $0 !== stop }
        if let l = stop.outgoingLeg { stop.outgoingLeg = nil; context.delete(l) }
        if let l = stop.incomingLeg { stop.incomingLeg = nil; l.fromStop?.outgoingLeg = nil; context.delete(l) }
        journey.stops.removeAll { $0 === stop }
        context.delete(stop)
        apply(list, in: journey)
        registerUndo(target: journey, name: "Delete Stop") { $0.restoreStop(snapshot, in: journey) }
    }

    func deleteJourney(_ journey: Journey) {
        context.delete(journey)
    }

    // MARK: Undo

    private func insert(_ stop: Stop, into journey: Journey, at index: Int?) {
        var list = journey.orderedStops.filter { $0 !== stop }
        list.insert(stop, at: max(0, min(index ?? list.count, list.count)))
        if stop.modelContext == nil { context.insert(stop) }
        stop.journey = journey
        apply(list, in: journey)
    }

    /// Registers `action` as the undo step; running it registers the inverse, so redo works the same way.
    private func registerUndo(target: AnyObject, name: String, _ action: @escaping @MainActor (JourneyEditor) -> Void) {
        guard let undoManager else { return }
        let editor = self
        undoManager.registerUndo(withTarget: target) { _ in MainActor.assumeIsolated { action(editor) } }
        if !undoManager.isUndoing && !undoManager.isRedoing { undoManager.setActionName(name) }
    }

    /// Rebuilds a deleted stop (same id, fields, photos with bytes) at its old position, then puts its legs' content back.
    @discardableResult
    private func restoreStop(_ snapshot: StopSnapshot, in journey: Journey) -> Stop {
        let stop = Stop(placeName: "")
        stop.id = snapshot.id
        snapshot.content.apply(to: stop)
        context.insert(stop)
        for p in snapshot.photos {
            let photo = p.makePhoto()
            context.insert(photo)
            photo.stop = stop
        }
        insert(stop, into: journey, at: snapshot.index)
        if let c = snapshot.incoming, let leg = stop.incomingLeg { c.apply(to: leg) }
        if let c = snapshot.outgoing, let leg = stop.outgoingLeg { c.apply(to: leg) }
        registerUndo(target: journey, name: "Delete Stop") { $0.deleteStop(stop, in: journey) }
        return stop
    }

    private func restoreOrder(_ ids: [UUID], legs: LegContentMap, in journey: Journey) {
        let current = journey.orderedStops.map(\.id)
        let currentLegs = LegContentMap(journey)
        let byID = Dictionary(uniqueKeysWithValues: journey.orderedStops.map { ($0.id, $0) })
        apply(ids.compactMap { byID[$0] }, in: journey)
        legs.restore(in: journey)
        registerUndo(target: journey, name: "Move Stop") { $0.restoreOrder(current, legs: currentLegs, in: journey) }
    }

    private func apply(_ list: [Stop], in journey: Journey) {
        for (i, s) in list.enumerated() where s.orderIndex != i { s.orderIndex = i }
        LegSync.reconcile(stops: list, context: context)
        journey.updatedAt = .now
    }
}

/// Idempotent: keeps exactly one leg per consecutive (from, to) pair, drops all others.
enum LegSync {
    @MainActor
    static func reconcile(stops: [Stop], context: ModelContext) {
        // 1. Drop legs whose pair is no longer consecutive.
        for (i, s) in stops.enumerated() {
            let next: Stop? = i + 1 < stops.count ? stops[i + 1] : nil
            if let l = s.outgoingLeg, next == nil || l.toStop !== next {
                s.outgoingLeg = nil
                l.toStop?.incomingLeg = nil
                context.delete(l)
            }
            if let l = s.incomingLeg {
                let prev: Stop? = i > 0 ? stops[i - 1] : nil
                if prev == nil || l.fromStop !== prev {
                    s.incomingLeg = nil
                    l.fromStop?.outgoingLeg = nil
                    context.delete(l)
                }
            }
        }
        // 2. Create missing legs.
        for (a, b) in zip(stops, stops.dropFirst()) where a.outgoingLeg == nil {
            let leg = Leg()
            context.insert(leg)
            leg.fromStop = a
            leg.toStop = b
        }
    }

    /// Legs with user content that `reconcile` would drop if `stops` became the new order.
    static func legsLost(whenOrderBecomes stops: [Stop]) -> [Leg] {
        var wanted = Set<String>()
        for (a, b) in zip(stops, stops.dropFirst()) { wanted.insert("\(a.id)>\(b.id)") }
        var lost: [Leg] = []
        for s in stops {
            if let l = s.outgoingLeg, l.hasContent {
                if let t = l.toStop, wanted.contains("\(s.id)>\(t.id)") { continue }
                lost.append(l)
            }
        }
        return lost
    }

    /// True when invariant holds: n-1 legs, leg i joins stop i and i+1.
    static func isConsistent(_ stops: [Stop]) -> Bool {
        for (i, s) in stops.enumerated() {
            if i + 1 < stops.count {
                guard let l = s.outgoingLeg, l.fromStop === s, l.toStop === stops[i + 1] else { return false }
            } else if s.outgoingLeg != nil { return false }
        }
        return true
    }
}
