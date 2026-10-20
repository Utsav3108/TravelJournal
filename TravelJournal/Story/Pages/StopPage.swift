import SwiftUI

/// One stop = one page. Templates T0...T4 (by photo count) are resolved by `StopLayout`; this view only draws.
struct StopPage: View {
    var model: StopPageModel
    var metrics: PageMetrics
    var callbacks: StoryPageCallbacks = .none
    var entryY: CGFloat?

    @Environment(\.storyImageProvider) private var provider

    private var interactive: Bool { metrics.mode == .interactive }

    var body: some View {
        let layout = StopLayout.make(model, metrics: metrics, entryY: entryY)
        let page = canvas(layout)
            .frame(width: layout.pageSize.width, height: layout.pageSize.height, alignment: .topLeading)
            .background(PaperBackground())
            .clipped()
        if interactive && layout.pageSize.height > metrics.size.height + 0.5 {
            ScrollView(.vertical, showsIndicators: false) { page }
                .frame(width: metrics.size.width, height: metrics.size.height)
        } else {
            page
        }
    }

    // swiftlint:disable:next function_body_length
    private func canvas(_ L: StopLayout) -> some View {
        let loader = StoryPhotoLoader(provider: provider, interactive: interactive)
        let id = model.stopID
        let photos = Array(model.photos.prefix(4))
        return ZStack(alignment: .topLeading) {
            // 1. Route underlay.
            StopRouteLayer(plan: L.route, isLast: model.exit == nil, pageSize: L.pageSize,
                           holes: L.rating.map { [(rect: $0, degrees: PageSeed.rotation(id: "\(id)/rating"))] } ?? [])

            // 2. Photos.
            if let hero = L.hero, let p = photos.first {
                Polaroid(photo: loader.image(p), caption: model.name, width: hero.width, seed: "\(id)/hero")
                    .placed(hero)
                    .photoTap(p, callbacks: callbacks, interactive: interactive)
            }
            ForEach(Array(L.taped.enumerated()), id: \.offset) { i, rect in
                let idx = i + 1
                if idx < photos.count {
                    let p = photos[idx]
                    let tapes = L.photoCount == 2 ? 2 : (L.photoCount == 3 && i == 0 ? 2 : 1)
                    TapedPhoto(photo: loader.image(p), size: CGSize(width: rect.width - 8, height: rect.height - 8),
                               tapes: tapes, seed: "\(id)/photo/\(p.id)")
                        .placed(rect)
                        .photoTap(p, callbacks: callbacks, interactive: interactive)
                }
            }

            // 3. Note card.
            noteCard(L)
                .placed(L.card, alignment: .topLeading)

            // 4. Highlight, cost, ticket, rating.
            if let r = L.highlight, let h = model.highlight {
                HighlightStrip(text: h, seed: "\(id)/highlight", showsArrow: L.highlightArrow)
                    .placed(r, alignment: .leading)
            }
            if let r = L.cost, let t = StopLayout.chipText(model) {
                Text(t)
                    .stampLabel()
                    .foregroundStyle(KraftColor.ink)
                    .lineLimit(1)
                    .frame(width: r.width, height: r.height)
                    .background(KraftColor.paper)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(KraftColor.kraftDark, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .rotationEffect(.degrees(PageSeed.rotation(id: "\(id)/cost", limit: 2)))
                    .placed(r)
            }
            PlaceTicket(number: model.index + 1, name: model.name, category: KraftCategory(rawValue: model.categoryRaw) ?? .other,
                        arrived: PageFormat.time(model.arrival), spentMinutes: nil,
                        width: L.ticket.width, height: L.ticket.height, seed: "\(id)/ticket")
                .placed(L.ticket)
            if let r = L.rating, let stars = model.rating {
                RatingStamp(rating: stars, review: model.review, seed: "\(id)/rating")
                    .placed(r)
            }

            // 5. Postmark (T0) and wax seal.
            if let r = L.postmark {
                StoryPostmark(top: "STOP \(model.index + 1)", bottom: "OF \(model.total)",
                         center: PageFormat.time(model.arrival) ?? "", size: r.width, seed: "\(id)/postmark")
                    .placed(r)
            }
            if let r = L.seal {
                WaxSeal(glyph: String(model.name.first.map { String($0).uppercased() } ?? "T"), size: r.width, seed: "\(id)/seal")
                    .placed(r)
            }

            // 6. Leg connector badge (and, in print, the leg story card). Sits above content so it is always legible.
            if let leg = model.outLeg, L.route.exitPoint != nil, let center = L.route.badgeCenter {
                legConnector(leg, center: center, layout: L)
            }

            // 7. UI overlay (interactive only).
            if interactive, let edit = callbacks.onEdit {
                Button { edit(model.stopID) } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KraftColor.ink)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(KraftColor.polaroidWhite))
                        .overlay(Circle().stroke(KraftColor.kraftDark.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(model.name)")
                .placed(L.edit)
            }
        }
    }

    @ViewBuilder private func noteCard(_ L: StopLayout) -> some View {
        let variant = L.photoCount == 0 ? 2 : Int(model.seed % 3)
        NoteCard(variant: variant, seed: "\(model.stopID)/note", inset: L.cardInset) {
            if L.cardClipped {
                // Last resort (A4 only): shrink the type rather than spill into the connector slot.
                Text(model.story).storyBody().foregroundStyle(KraftColor.ink)
                    .minimumScaleFactor(0.75)
                    .frame(maxHeight: L.card.height - 2 * L.cardInset, alignment: .topLeading)
            } else {
                Text(model.story).storyBody().foregroundStyle(KraftColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: L.card.width, height: L.card.height, alignment: .topLeading)
    }

    @ViewBuilder private func legConnector(_ leg: StoryLeg, center: CGPoint, layout L: StopLayout) -> some View {
        let transport = leg.modeRaw.flatMap { KraftTransport(rawValue: $0) }
        let label = KraftFormat.legLabel(mode: transport, minutes: leg.minutes, km: leg.km).uppercased()
        let showLabel = LegConnectorMetrics.showsLegLabel(interactive: interactive) && !label.isEmpty
        let labelW = PageText.width(label, fontName: PageFont.elite, size: 11, tracking: 1.5)
        let W = L.pageSize.width
        let labelCenterX = min(max(center.x, labelW / 2 + 6), W - labelW / 2 - 6)
        let hitSide = LegConnectorMetrics.hitSide
        ZStack(alignment: .topLeading) {
            if !interactive, let story = leg.story, !story.isEmpty {
                let cardW: CGFloat = 210
                let textH = PageText.height(story, fontName: PageFont.caveat, size: 18, lineSpacing: 0, width: cardW - 24)
                let h = min(textH, 4 * 23) + 20
                NoteCard(variant: 0, seed: "\(leg.id)/note", inset: 10) {
                    Text(story).font(KraftFont.note()).foregroundStyle(KraftColor.inkSoft).lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: cardW, height: h, alignment: .topLeading)
                .rotationEffect(.degrees(PageSeed.rotation(id: "\(leg.id)/note", limit: 2.5)))
                .placed(CGRect(x: center.x - 18 - 10 - cardW, y: center.y - h / 2, width: cardW, height: h), alignment: .topLeading)
            }
            ZStack {
                Circle().fill(KraftColor.polaroidWhite)
                Circle().stroke(KraftColor.route, lineWidth: 1.5)
                if let transport { TransportIcon(mode: transport, size: 22) }
                else { Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(KraftColor.route) }
            }
            .frame(width: 36, height: 36)
            .placed(CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36))
            if showLabel {
                Text(label).stampLabel().foregroundStyle(KraftColor.ink).fixedSize()
                    .padding(.horizontal, 4)
                    .background(KraftColor.paper.opacity(0.85))
                    .position(x: labelCenterX, y: center.y + 18 + 12)
            }
            if interactive, let onLeg = callbacks.onLegTap {
                Color.clear
                    .frame(width: hitSide, height: hitSide)
                    .contentShape(Rectangle())
                    .position(x: center.x, y: center.y)
                    .onTapGesture { onLeg(leg) }
                    .accessibilityLabel(label.isEmpty ? "Leg" : "Leg: \(label)")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(width: L.pageSize.width, height: L.pageSize.height, alignment: .topLeading)
    }
}

/// Leg connector layout rules: the text label is PDF-only (the viewer shows details in the leg sheet).
enum LegConnectorMetrics {
    static let hitSide: CGFloat = 44
    static func showsLegLabel(interactive: Bool) -> Bool { !interactive }
}

private extension View {
    @ViewBuilder func photoTap(_ photo: StoryPhoto, callbacks: StoryPageCallbacks, interactive: Bool) -> some View {
        if interactive, let tap = callbacks.onPhotoTap {
            contentShape(Rectangle()).onTapGesture { tap(photo) }
        } else {
            self
        }
    }
}

// MARK: Route underlay

/// Dashed route (entry stub + exit run), arrowhead, and an end flag on the last stop.
struct StopRouteLayer: View {
    var plan: RoutePlan
    var isLast: Bool
    var pageSize: CGSize
    /// Transparent stamps (rating) knock the route out underneath them (vector clip, no blend modes).
    var holes: [(rect: CGRect, degrees: Double)] = []

    private static let style = StrokeStyle(lineWidth: PageRouteGeometry.lineWidth, lineCap: .round, lineJoin: .round,
                                           dash: [PageRouteGeometry.dash, PageRouteGeometry.gap], dashPhase: PageRouteGeometry.phase)

    var body: some View {
        ZStack {
            if plan.entryPoly.count > 1 {
                StoryPolyline(points: plan.entryPoly, trimToDash: true)
                    .stroke(KraftColor.route, style: Self.style)
            }
            if plan.exitPoly.count > 1 {
                StoryPolyline(points: plan.exitPoly, trimToDash: true)
                    .stroke(KraftColor.route, style: Self.style)
            }
            if let tip = plan.arrowTip, let d = plan.arrowDir {
                ArrowheadShape(base: tip, direction: d).fill(KraftColor.route)
            }
            if isLast {
                // Route ends on the last stop: small flag planted just above the pin.
                Path { p in
                    let a = plan.anchor
                    p.move(to: CGPoint(x: a.x, y: a.y - 12)); p.addLine(to: CGPoint(x: a.x, y: a.y - 30))
                }
                .stroke(KraftColor.route, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Path { p in
                    let a = plan.anchor
                    p.move(to: CGPoint(x: a.x, y: a.y - 30)); p.addLine(to: CGPoint(x: a.x + 14, y: a.y - 25))
                    p.addLine(to: CGPoint(x: a.x, y: a.y - 20)); p.closeSubpath()
                }
                .fill(KraftColor.route)
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .clipShape(KnockoutShape(holes: holes), style: FillStyle(eoFill: true))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// The whole layer rect with rounded holes; fill with even-odd to clip the holes out.
struct KnockoutShape: Shape {
    var holes: [(rect: CGRect, degrees: Double)]

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        for h in holes {
            let r = h.rect.insetBy(dx: -6, dy: -6)
            var hole = Path(roundedRect: r, cornerRadius: 10)
            let c = CGPoint(x: r.midX, y: r.midY)
            hole = hole.applying(CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(h.degrees * .pi / 180)).translatedBy(x: -c.x, y: -c.y))
            p.addPath(hole)
        }
        return p
    }
}

/// A polyline (already in page coordinates) optionally trimmed to end on a whole dash.
struct StoryPolyline: Shape {
    var points: [CGPoint]
    var trimToDash = false

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let f = points.first else { return p }
        p.move(to: f)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        if trimToDash {
            let frac = PageRouteGeometry.trimFraction(length: PageRouteGeometry.polylineLength(points))
            if frac < 1 { return p.trimmedPath(from: 0, to: frac) }
        }
        return p
    }
}

struct ArrowheadShape: Shape {
    var base: CGPoint
    var direction: CGVector
    var length: CGFloat = 12
    var halfWidth: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        let tip = CGPoint(x: base.x + direction.dx * length, y: base.y + direction.dy * length)
        let nx = -direction.dy, ny = direction.dx
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: base.x + nx * halfWidth, y: base.y + ny * halfWidth))
        p.addLine(to: CGPoint(x: base.x - nx * halfWidth, y: base.y - ny * halfWidth))
        p.closeSubpath()
        return p
    }
}
