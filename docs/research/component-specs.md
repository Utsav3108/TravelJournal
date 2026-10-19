# D2 Component and Layout Specs (TravelJournal, Vintage Kraft)

Sources: task.pdf tokens/rules, PLAN.md decisions (A4 only, no Mood/Tip, 100 words/stop), reference images 1-3.
Colour tokens (paper, paperDeep, kraft, kraftDark, ink, inkSoft, route, sealRose, stampTeal, highlight) are used by name; D1 owns hex values and fonts.
Two derived values are proposed here and should be confirmed by D1: `polaroidWhite` = #FBF7EE (paper lightened; spec has no white) and `numeral` = Special Elite 28 pt for closing-page numbers.

## 0. Cross-cutting construction rules

- One view tree for both outputs. Every page view takes `PageMetrics { size, margin, target }`. Phone: width = screen, margin 24. PDF: 595x842, margin 36. `target` is `.screen` or `.pdf`; it may only toggle interaction (taps, edit button, animations). It must never change geometry, fonts, rotation, tape, or text.
- Geometry in pt only, no `GeometryReader`-dependent randomness. Any measured value (note card height) comes from the same `Text` layout at the same width.
- Z-order, bottom to top: paper grain, route underlay, photos/polaroids, tape, note card, highlight, ticket, rating stamp, postmark/seal, route label (leg connector badge), UI overlays (screen only).
- Route is drawn under content (as in image 2: it shows only in gaps). Only the leg badge and pins sit above content, so they are always legible.
- PDF fidelity: avoid `.blur`, `.blendMode`, live `.shadow` radii above 6, and SwiftUI `Material`. These get rasterised by `ImageRenderer` or vary by target. Use `.shadow(color: ink.opacity(0.18), radius: 4, y: 2)` only on photo frames (spike in L3 to confirm it renders in PDF context). Grain is a tiled PNG at 0.06-0.10 opacity (rasterised, identical in both). Photos are downsampled `UIImage`s (max 1600 px long edge) so PDF size stays under ~25 MB for 20 photos.
- Fonts only via D1's `Theme.font(...)`; text that must not reflow uses `.fixedSize(horizontal:false, vertical:true)` and explicit `lineLimit`. Story pages ignore Dynamic Type (fixed pt per spec); editor screens honour it.
- Accessibility (screen only): each component gets a combined `accessibilityLabel` (e.g. "Photo: caption"); decorative tape/seal/grain are `accessibilityHidden(true)`.

## 1. Components

All sizes pt at 1x. "A4" and "phone" differ only where noted. Rotation = seeded value from section 3 unless stated.

### 1.1 Polaroid (hero)
- Anatomy: frame `polaroidWhite`, photo window, caption strip.
- Size A4: 230 x 285 (window 210x210, side/top padding 10, bottom strip 65... see below). Phone: width = 0.62 x content width (212 at 390), height = width x 1.24. Rule: window is square, side/top pad = 5% of width, bottom strip = 22% of width.
- Caption: Caveat 18, inkSoft, 1 line, centred, truncation tail; from `Photo.caption` else place name. Empty caption keeps the strip (polaroid look).
- Build: `VStack(spacing:0){ Photo.scaledToFill().frame(w,w).clipped(); Text(caption)...frame(height: strip) }.padding(pad).background(Rectangle().fill(polaroidWhite))`, then `.rotationEffect(deg)` last, then `.shadow`. Photo gets a 0.5 pt `kraftDark` inner stroke at 30% for definition.
- Rating stamp and wax seal may overlap its lower-right corner (see templates).

### 1.2 Taped photo
- Photo with no frame, white 4 pt border (`polaroidWhite`) so it reads as a print. Sizes: A4 small 150x112 (landscape) or 112x150 (portrait, chosen by photo aspect > 1); phone scale x0.8.
- Tape: Shape `TapeStrip` 64x22 (phone 52x18), serrated short ends (triangle zig-zag with 3 teeth, 2 pt deep), fill by variant: kraft (kraft at 85%), pink grid (sealRose 35% + 0.5 pt grid lines via `Canvas`), floral (D1 PNG, else Canvas dots in stampTeal 40%). Variant = seeded pick of 3.
- Placement: 1 strip = centred on top edge, overlapping 8 pt outward; 2 strips = top-left and bottom-right corners, each rotated +/-4 total from absolute (not relative to photo; keep inside the spec's +/-4 by clamping `photoRot + tapeJitter` to [-4,4]). Max 2 per photo (enforced in the `TapedPhoto` initialiser: `precondition(tapes <= 2)`, clamp in release). Hero polaroid gets 0 tape (image 3 pairs polaroids with a clip/tape only occasionally; v1: none, to save the budget).
- Build: `ZStack{ photo; tapes.overlay(alignment:) }`, tape offset by seeded +/-6 pt on the free axis.

### 1.3 Note card
- Torn-edge paper holding the story. Fill `paperDeep`, grain overlay, 0.5 pt `kraftDark` 25% hairline is NOT used on torn edges (let the tear read).
- Shape `TornEdgeShape(variant 0...2, seed)`: rectangle path whose chosen edges are replaced by jagged segments (step 5-9 pt, amplitude 1.5-3 pt, from the seeded stream). Variants: 0 = bottom torn, 1 = top and bottom torn, 2 = all four, left/right amplitude 1.5. Use as `.background(TornEdgeShape(...).fill(paperDeep))` plus `.shadow` radius 3. Same Shape for the in-app and PDF; no bitmap mask, so it stays vector.
- Text: Lora 16 / 24 line height (`lineSpacing(24 - 19.2)` ~ 4.8; verify with Lora's natural line height 1.28 em = 20.5 -> `lineSpacing(3.5)`), ink, inset 16 (A4 18).
- Capacity (100 words ~ 600 chars, Lora avg 7.4 pt/char = ~4440 pt of line length, worst case +10% for long words):

| Card inner width | chars/line | lines (100 w) | text height | card height (+32 pad) |
|---|---|---|---|---|
| A4 full 523 -> 487 | ~66 | 10 | 240 | 272 |
| A4 three-quarter 400 -> 364 | ~49 | 13 | 312 | 344 |
| A4 half 255 -> 219 | ~30 | 21 | 504 | 536 (too tall, never use) |
| Phone full 342 -> 310 | ~42 | 15 | 360 | 392 |

  Conclusion: 100 words fits only as a full-width card on A4 (about 272, budget 290 for the 110% worst case) and as a full-width card on phone. Therefore all templates put the note card full-width under the photo band (no side-by-side text/photo columns, no wrap-around; see section 7).
- Overflow safety: editor hard-stops at 100 words and 700 characters; the engine measures the card and, if over budget, applies tiers: (a) shrink photo band to 85%, (b) Lora 15/22. A stop that still overflows is a bug, not a layout case.

### 1.4 Highlight strip
- Caveat 18, ink, on a band `highlight` (#F2D06B at 70%). Max 2 lines, 60 characters (editor enforces).
- Shape `MarkerBand`: rounded rect radius 3 with left and right ends cut by 3-4 pt seeded jaggedness (a 12-point path). Padding 10 h, 3 v. Height 32 (1 line) / 56 (2 lines). Rotation seeded, clamp +/-2.5 (reads as hand-laid).
- Optional hand arrow (image 1): a 40x24 quadratic-curve `Path` with arrowhead in `inkSoft`, 1.5 pt stroke, from strip toward the hero polaroid centre. Included when stop has >=1 photo; omitted otherwise. Max 1 arrow.
- Placed overlapping the note card's top edge by 10 pt when space is tight (4-photo template) otherwise on its own row.

### 1.5 Place ticket
- A4 280x72, phone 250x64. Fill `kraft`, text ink. Shape `TicketShape`: rounded rect with two semicircle notches (r 7) on the left and right at the perforation line x = 64 and a dashed vertical perforation (`StrokeStyle(lineWidth:1, dash:[3,3])`, kraftDark).
- Left stub (64 wide): category stamp icon 34 pt in `stampTeal` (outlined circle 40 + icon from D1; "other" uses a generic pin) and the numbered pin (route circle 26, Special Elite 13 white-ish `polaroidWhite`) sits overlapping the stub's top-left corner. The pin is the route anchor point.
- Right: place name Allura 30 (1 line, `minimumScaleFactor(0.6)`, then 2 lines max at 22 pt), below it Special Elite 11 uppercase +1.5 tracking "ARRIVED 12:40 - SPENT 45 MIN" (parts omitted if nil, inkSoft).
- Rotation seeded, clamp +/-3 (ticket stays readable).

### 1.6 Postmark
- Round stamp, `stampTeal` at 85% opacity. Sizes: stop page 84, cover 120, closing 96.
- Anatomy: outer ring 2 pt, inner ring 1 pt at r-7, centre text, arc text, two wavy cancel lines (cover only) extending right.
- Stop page: arc top "STOP 2" and bottom place city (Special Elite 9 uppercase, +1.5 tracking, never below 9), centre time "12:40" Special Elite 15. Cover: arc "ARRIVED - 19 OCT 2026 - MUMBAI" (spec string), centre airplane? No: centre = plain "ARRIVED" and a date. Keep spec text; arc text capped at 28 chars (truncate city).
- Build: `ArcText` view placing each glyph with `rotationEffect` along a `Circle` radius; glyph advance from `NSString.size(withAttributes:)` using the bundled font so layout is deterministic. Ink-bleed look: overlay a grain PNG with `.mask`; rasterises in PDF, fine.

### 1.7 Rating stamp
- 150x64 rounded rect (r 6), 2 pt `stampTeal` border, double-struck look via second 0.8 pt outline offset 2 pt. Inside: 5 star `Shape`s 18 pt (filled stampTeal for rating, outline for the rest; do not use SF Symbols, to guarantee PDF parity), below them review in Caveat 18 inkSoft, 1 line (A4 2 lines allowed, 64 -> 84 high), max 48 characters.
- Rotation seeded, clamp +/-4. Omitted if no rating. If rating nil but review exists, show review only as highlight-style text? No: review needs a rating; editor enforces "add rating to add review" (or treat a review without rating as a 1-line caption inside the note card footer; pick the former for v1).

### 1.8 Wax seal
- 56 pt circle, `sealRose`, irregular edge (`SealShape`: 14 lobes, seeded radius jitter +/-2), radial gradient (lighter highlight at top-left), embossed centre glyph (journey initial, Allura 30, `polaroidWhite` 70%). Max 1 per page (templates below place it on cover and on one stop type only).

### 1.9 Leg connector (route segment plus badge)
- Not a separate page: it is the outgoing tail of the route on stop page N, ending at the page edge, plus the badge on it (spec item 4, "between stop pages, dashed route continues off one page and onto the next").
- Dashed route: stroke `route`, 3 pt, round cap, dash [9, 7], arrowhead 12 pt filled `route` near the exit edge (placed 14 pt before the edge). Wobble: path is a cubic with seeded control offsets (+/-18 pt).
- Badge (placed at the path point t=0.55 of the last segment, always inside the connector slot, section 4): circle 36 in `polaroidWhite` with 1.5 pt `route` border, transport icon 22 ink-line (D1). Label right/left of circle: Special Elite 11 uppercase +1.5, ink: "TAXI - 18 MIN - 5.2 KM" (missing km/min parts omitted).
- Screen: whole badge area is one 44x44-min tap target opening the leg card (mode, km, min, leg story). PDF: same position, plus leg story printed as a small note card (A4 width 190, Caveat 18 inkSoft, `lineLimit(4)`, torn variant 0, rotation seeded) sitting above/beside the badge. Leg story is soft-limited to 25 words in the leg editor to fit the 4 lines.

### 1.10 Route map card
- Frame like a taped photo: `polaroidWhite` 6 pt border, 2 tape strips. A4 size 523 x 340; phone 342 x 260.
- Content: pre-composited `UIImage` (MKMapSnapshotter at 2x, CISepiaTone 0.8, multiply `paperDeep`, grain, route polyline and numbered pins drawn into the bitmap by one `UIGraphicsImageRenderer`) so screen/PDF are identical. Pins as an extra interactive overlay on screen only, aligned using `snapshot.point(for:)` (must be the same coordinate mapping; hit areas 44x44). Pin: route-colour circle 26, number Special Elite 13.
- Stops without location are excluded from the map and listed in the page's legend as "not on map".

### 1.11 Stats strip
- One typewriter row inside a `paperDeep` band, height 36, dashed top and bottom hairlines. Special Elite 11 uppercase +1.5, ink: "4 STOPS - 8.4 KM - 5 H 20 MIN - WALK, TAXI". Separator = " - " (a middle dot "·" if font has the glyph; D1 to verify). Phone: `ViewThatFits` falls back to 2 lines (height 52). Modes list is deduplicated, ordered by distance descending, max 3 then "+N".

## 2. Stop-page templates

Common: page canvas A4 595x842, content 523x770 (margin 36). Route pin = ticket pin. Connector slot (section 4) reserved at bottom: A4 100 pt tall (badge + leg note card), phone 64 pt. Last stop has no slot (page gets +100 pt of free space and ends with a "THE END" mini postmark? no; the closing page follows, so the route continues to the next page as a final leg to the closing page's flag).
Element order is identical on phone, stacked in one column with widths scaled: phone hero polaroid width 212, taped photos scale 0.8, ticket 250x64, note card full width 342. Phone page height = max(640, measured content); overflow scrolls vertically inside the page.

Common budget (A4): connector slot 100, gaps 12 each, note card 272 (budget 290), highlight 32 or overlap, rating stamp overlays.

### T0: no photos
```
+--------------------------------------+  36pt margin
| [pin]TICKET  280x72           POSTMARK|  postmark 84, rotated, top-right
|                                      |
|  ..route underlay..                  |
|  +--NOTE CARD 523 x 290 (torn v2)--+ |  larger type allowed? no: same 16/24
|  |  story (100 words, 10 lines)    | |
|  +---------------------------------+ |
|   [highlight strip ~~~~]  [RATING]   |  rating 150x64 right
|           (WAX SEAL 56, if allowed)  |
|                         [leg badge]--> exit
+--------------------------------------+
```
Fills ~460 of 770; spare space becomes a decorative zone for the route and the seal. Seal only here (max 1) and when rating = 5 on any template (never both).

### T1: one photo (hero)
```
| [HERO POLAROID 230x285 rot]  [pin]TICKET 280x72 |  y 0..285
|                              [highlight ~~~~~>] |  arrow toward polaroid
|                              [RATING 150x64]    |
| +--------NOTE CARD 523 x 290----------------+   |  y 297..587
| +-------------------------------------------+   |
|                                    [badge]--> exit  y 670..770
```
Height used: 285+12+290 = 587, plus slot 100 = 687 (83 free: increase polaroid to 250x310 allowed).

### T2: two photos
```
| [HERO 230x285]  [TAPED 150x112 landscape, 2 tape] [pin]TICKET
|                 overlapping hero by 20pt          [highlight]
|                                                   [RATING]
| +--------NOTE CARD 523 x 290--------------------+
|                                      [badge]-->
```
Taped photo sits right of the hero with its top aligned 40 pt below the hero top; ticket and highlight right column starts below it (column width 523-230-12 = 281).

### T3: three photos
```
| [HERO 230x285]  [TAPED A 134x100]  [TAPED B 134x100]
|                 [pin]TICKET 280x72 (under taped row)
|                 [highlight] [RATING 150x64]
| +--------NOTE CARD 523 x 290-----------------+
|                                   [badge]-->
```
Right column 281 wide: taped photos side by side (2x134 + 12), ticket below at 280 wide. Height 285+12+290+100 = 687.

### T4: four photos (tightest)
```
| [HERO 230x250]   [pin]TICKET 280x72
|                  [highlight ~~~~] overlaps card top by 10
|                  [RATING 150x64] overlays hero corner
| [T1 160x100] [T2 160x100] [T3 160x100]  (3 taped, 12 gap)
| +--------NOTE CARD 523 x 290------------+
|                                   [badge]-->
```
Budget: 250 + 12 + 100 + 12 + 290 + 100 = 764 <= 770 (6 pt spare). Fallback tier (a) already built in: photo band x0.85. Mark as the highest layout risk.

Rules applied to all templates: max 2 tape strips per photo, hero has 0 tape; at most 1 wax seal per page (T0 or 5-star stops, never both, never a second); rating stamp overlaps polaroid corner at most 24 pt and never covers a face region (can't know: keep to the bottom-right of the polaroid caption strip). Hero = the photo flagged hero else first. v1.1 hero/layout picker is out of scope; the template is purely `photoCount`.

## 3. Deterministic seeded rotation

Never `Hasher`/`hashValue` (per-launch randomised). Use FNV-1a 64 + splitmix64 finalizer over a stable string key.

```swift
enum Seed {
    static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }
    static func mix(_ x: UInt64) -> UInt64 {          // splitmix64 finalizer
        var z = x &+ 0x9e3779b97f4a7c15
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
struct SeededStream {
    private var state: UInt64
    init(_ id: String, _ salt: String) { state = Seed.mix(Seed.fnv1a(id + "|" + salt)) }
    mutating func next() -> UInt64 { state = Seed.mix(state); return state }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }   // [0,1)
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
}
func rotation(id: String, limit: Double = 4) -> Double {      // degrees
    var s = SeededStream(id, "rot"); return s.range(-limit, limit)
}
```
- Keys use persisted UUID strings (`uuid.uuidString`, uppercase, never regenerated), element path style: `"<stopID>/hero"`, `"<stopID>/photo/<photoID>"`, `"<stopID>/ticket"`, `"<stopID>/note"`, `"<stopID>/rating"`, `"<legID>/badge"`. Photos use their own id, not index, so reordering photos does not re-roll the others.
- Other randomness (tape variant, tape offset, torn-edge pattern, wobble) uses the same stream with different salts ("tape", "torn", "wobble"), never `Double.random`.
- Component clamps: global +/-4 (spec). Tickets +/-3, highlights +/-2.5. Optional dead zone: if |r| < 0.6, scale to +/-0.6 so tilt reads intentional.
- Golden test: unit test asserts fixed ids map to fixed outputs (e.g. `rotation(id:"00000000-0000-0000-0000-000000000001/hero")`) on every run; PDF and screen call the same function, so parity is guaranteed by construction.
- Caveat: changing the key format or constants changes every journey's look. Freeze them in v1 (`Seed.version = 1` in docs).

## 4. Route continuity rule and algorithm

Interpretation: book flows left to right, swipe moves right-to-left. The route leaves page N through its right edge at height `y` and enters page N+1 through its left edge at the same `y`. Spec's "enters from the previous page's exit side" is read as "same exit/entry height at the shared gutter, continuing in the same direction". Exit side is always `.right` in v1; model it as `enum Side { left, right }` so a future vertical or alternating book is possible.

Page-local coordinates, y in [0, H]. For stop page i of n:
1. `exitY(i)` (shared by page i exit and page i+1 entry):
   `s = SeededStream(stop_i.id, "exit")`; `base = H - margin - slot/2` (slot 100 A4, 64 phone; centre of the connector slot); `exitY = base + s.range(-12, +12)`.
2. `entryY(i) = exitY(i-1)`. First stop: entry from the overview page exit: `exitY(overview) = 0.62*H + seeded(journey.id,"overview") * 24` (stays in the lower half where the overview has free space). Page 0 cover has no route.
3. Anchor: pin point P_i = centre of the numbered pin on the ticket (known from the template, deterministic).
4. Route path on page i: polyline E(0, entryY) -> P_i -> X(W, exitY) rendered as two cubic Beziers; control points: entry segment c1 = E + (0.35*P.x, seed offset +/-18), c2 = P - (60, seeded +/-18); exit segment c1 = P + (60, seeded), c2 = X - (0.3*(W-P.x), seeded). Because entry and exit are both lower than the pin (ticket is near the top), the path swings up to the pin and back down; it is under all content so only gaps show it.
5. Entry stub: at E draw the incoming 40 pt dashed run plus no arrowhead; arrowhead sits on the exit side (14 pt before the edge) so direction is clear. Both ends are clipped to the page rect with `.clipped()` and hit exactly x=0 / x=W so a spread preview (two pages side by side) lines up.
6. Leg connector slot: rectangle `W - margin - slotW .. W` x `exitY +/- slotH/2` (A4 slotW 280 x slotH 100, phone 190 x 64). The badge is placed at path point t=0.55 of the exit Bezier, then snapped so its bounding box stays in the slot; the PDF leg note card sits above-left of the badge in the slot. Templates never place content in the slot (that is why T4 budgets 100 pt).
7. Last stop: no exit; the route ends at P_n with a "flag" end mark (closing page route entry continues? decided: route ends on the stop page, closing page has none, avoids dangling lines). First leg label never appears on the cover.
8. Stop without location: still has a pin; the map omits it but the story route (illustrated) is unaffected.
- Leg count: n-1; so `exitY` exists for all but the last page. Reordering stops changes ids order, not ids; `exitY` depends on stop id so adjacent pages stay mutually consistent (entryY always reads the previous page's value from the page list, never recomputed).
- Screen vs PDF: identical; screen adds the tap target.

## 5. Cover, route overview, closing

### Cover (A4 and phone)
```
|  [clip]          Journey title (Allura 44, 2 lines, scale>=0.7)
|                  19 OCT 2026 - MUMBAI  (Special Elite 11)
|  [POLAROID hero1 300x360 rot]  [TAPED 2 190x230, 2 tape]
|                                [TAPED 3 190x230, 1 tape]
|            [POSTMARK 120 ARRIVED - 19 OCT 2026 - MUMBAI]  [WAX SEAL 56]
|  +--intro note card (Lora 16, <=2 lines) torn v1 --+
```
- 3 hero photos = hero of first 3 stops with photos (repeat or fewer if less; with 0 photos use kraft block with a big postmark). Seed ids: `"cover/photo/<photoID>"`. Cover owns the seal for the journey (T0/T5 rule is per page, so no conflict).
- No route lines on the cover.

### Route overview
```
|  THE ROUTE (Special Elite 11) + title (Allura 30)
|  [ROUTE MAP CARD 523x340, 2 tapes]
|  [STATS STRIP 523x36]
|  1 Chhatrapati Shivaji Terminus   (numbered ticket list, Caveat 18,
|  2 Sardar Pav Bhaji               two columns if >5 stops)
|  3 Siddhivinayak Temple      route exits right at lower half ->
```
- Pins tappable (screen) jump to stop page. Dashed route segments over the map are tappable to open the leg card; hit width 44 around each segment. Up to ~12 stops fit the list (2 cols x 6, 14 pt rows); beyond that the list is dropped and pins carry the numbers.

### Closing
```
|  The day in numbers (Allura 30)
|  [5 stat tiles: STOPS | KM | MIN | SPENT | PHOTOS]   numeral 28 over label 11
|  +--closing note card (Lora, torn v2) ----+      [POSTMARK 96 "THE END"? no: date+city]
|  [route end flag / home icon at bottom-left, dashed tail from left edge]
```
- Tiles: `paperDeep` 96x84 with kraftDark dashed border, rotation seeded, 3+2 grid on A4 (width 523: 3 per row 160 + 2 per row). Money: per-currency sums "₹180 + $12", no conversion. Closing note has no word cap beyond 100 words to match stops (editor consistency).
- The route entry: closing page has no entry stub (route ended on last stop, rule 7).

## 6. Editor style (calm)

- Scrapbook is the output, not the UI: no textures, no rotation, no Allura/Caveat in editor chrome, no tape. Only Vintage Kraft touch: background and accent colours.
- Background `paper` (#F3EBDD) full-screen; `Form`/`List` with `.scrollContentBackground(.hidden)`, row backgrounds `paperDeep` at 60% or plain. Text `ink`, secondary `inkSoft`. System font (SF Pro) with Dynamic Type; use `Theme.font` only for the live page thumbnail.
- Controls: system `TextField`, `Picker`, `Stepper`, `PhotosPicker`, `DatePicker`; tint `route` for links/toggles, primary button `.borderedProminent` with `sealRose` tint (check white text contrast; fall back to `ink` text).
- Story field: `TextEditor` with Lora 16 preview? No, keep SF body in editor, show counter "73 / 100" (caption, `inkSoft`; turns `route` at >=90, hard stops at 100 with a haptic).
- Navigation: system `NavigationStack`, standard toolbar; leg editor as a sheet with the mode picker as a segmented/menu of icons (D1 transport icons, 28 pt, `.accessibilityLabel`).
- Force `.preferredColorScheme(.light)` for v1 (tokens are light only); flag dark mode as future.
- Min tap target 44; use `Label`s and VoiceOver labels everywhere; keep animations to system defaults.

## 7. Borrow vs skip from references

Borrow:
- Image 1: arrow-linked handwritten highlight captions (one per stop, arrow to hero); photos slightly overlapping with tape; coloured edge strips as a page-edge accent (optional: 6 pt kraft strip on page left edge, cheap).
- Image 2: dashed route as a line threaded between photos with arrowheads, route labels beside pins in handwriting; stop pin + name; bus/home icon on the route (our mode badge and end flag).
- Image 3: torn paper note cards, polaroid with Caveat caption, postage-stamp frame (use on cover for category/city stamp), postmark, single wax seal, washi strips, paper clip, ruled lines on note card (optional lines at 24 pt matching the line height, 8% ink).

Skip:
- Text wrapping around photos (image 1): SwiftUI has no exclusion-path text layout for `Text`; TextKit 2 work, breaks PDF parity and 100-word fit analysis. Keep photo band above a full-width card.
- Dense multi-photo clusters of 6+ and freeform sticker placement (Later per spec). Day flags (single-day trips), pressed flowers, pins/thumbtacks, kanji labels, multi-page spreads.
- Coloured edge strips on all four sides, multi-font mixing, jagged photo cut-outs (image 2).

## Open risks
1. A4 T4 (4 photos) has only ~6 pt spare; any Lora metrics difference breaks it. Needs a prototype with the real font and a worst-case 100-word text (long words) before freezing sizes.
2. Phone vs PDF parity: phone pages reflow and may scroll vertically, so "same pages printed flat" holds for components, rotation and route, not pixel layout. Needs product acceptance; alternative is scaling the A4 canvas to width (text drops to ~10.5 pt).
3. Route-side interpretation: exit right to entry left at the same y is my reading of "enters from the previous page's exit side"; confirm. Also whether pages are shown as spreads (then gutter alignment must be visibly continuous).
4. Route under content may be mostly hidden; if it feels lost, add a 2 pt margin-lane route or raise the stub length.
5. `ImageRenderer` PDF fidelity: shadows, masks and blend modes may rasterise or differ; L3 spike must verify shadow, grain and `ArcText`.
6. Bundled fonts: `Special Elite` glyph coverage for the middle dot and rupee (₹ in Special Elite/Lora/Caveat?) is unverified; need fallback.
7. Star/seal/ticket/postmark are drawn in code; if D1 chooses PNG assets, torn/ticket shapes must still be vector for the PDF.
8. `polaroidWhite` and `numeral` are not in the spec token table.
9. Sepia map is pre-composited; pin hit-testing alignment relies on `MKMapSnapshotter.Snapshot.point(for:)` in the same scale.
10. Light-only editor skipped dark mode and Dynamic Type on story pages (fixed pt per spec) is an accessibility gap.
11. Seeded constants and key format must be frozen; changing them restyles every saved journey.
