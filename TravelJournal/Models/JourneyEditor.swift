import Foundation
import SwiftData
import SwiftUI

/// All stop mutations go through here so `orderIndex` stays dense and legs stay in sync.
@MainActor
struct JourneyEditor {
    let context: ModelContext
    let photos: PhotoStoring

    init(context: ModelContext, photos: PhotoStoring) {
        self.context = context
        self.photos = photos
    }

    func addStop(_ stop: Stop, to journey: Journey, at index: Int? = nil) {
        var list = journey.orderedStops.filter { $0 !== stop }
        list.insert(stop, at: max(0, min(index ?? list.count, list.count)))
        if stop.modelContext == nil { context.insert(stop) }
        stop.journey = journey
        apply(list, in: journey)
    }

    func moveStops(in journey: Journey, from: IndexSet, to: Int) {
        var list = journey.orderedStops
        list.move(fromOffsets: from, toOffset: to)
        apply(list, in: journey)
    }

    func deleteStop(_ stop: Stop, in journey: Journey) {
        photos.removeFiles(for: stop.photos)
        let list = journey.orderedStops.filter { $0 !== stop }
        if let l = stop.outgoingLeg { stop.outgoingLeg = nil; context.delete(l) }
        if let l = stop.incomingLeg { stop.incomingLeg = nil; l.fromStop?.outgoingLeg = nil; context.delete(l) }
        journey.stops.removeAll { $0 === stop }
        context.delete(stop)
        apply(list, in: journey)
    }

    func deleteJourney(_ journey: Journey) {
        photos.removeAllFiles(forJourney: journey.id)
        context.delete(journey)
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
