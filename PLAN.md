# Story App (TravelJournal) — v1 Build Plan

## Context
`docs/task.pdf` is the "Story App — v1 Product & Design Spec": an iOS/SwiftUI app that turns a one-day trip into a scrapbook story (stops = chapters, legs = route thread), viewable interactively in-app and exported as an A4 PDF. Theme: Vintage Kraft. No backend; Apple frameworks only (SwiftData, PhotosPicker, MapKit, ImageRenderer). The repo is currently the empty Xcode SwiftUI/SwiftData template (`Item.swift`, `ContentView.swift`, `TravelJournalApp.swift`).

Goal of this plan: split the work into **phases** and decide **how many subagents** research the design system and the logic before and during the build.

## Summary
- **6 phases** (0 Research → 5 Polish/Release)
- **5 research subagents** in Phase 0, run in parallel (2 design, 3 logic)
- **3 build subagents** in Phases 1–4, each owning a disjoint folder, plus the main agent as integrator/reviewer
- Agent type: `Explore` for read-only research, `general-purpose` for build; max 3 concurrent at build time to avoid merge conflicts

## Decisions (confirmed by user)
- **PDF size:** A4 portrait only; square/Instagram export dropped from v1 and v1.1.
- **Mood and Tip:** cut from the Leg model and all UI.
- **Story length:** 100 words per stop (replaces the earlier 1000 figure). The editor shows a live counter and warns at the limit. A 100-word story fits one note card, so one stop = one page and no text pagination is needed.
- **App name:** TravelJournal (matches the existing Xcode project; no rename needed).
- **Parallel build isolation:** Phases 1–4 build agents each run in their own git worktree (`isolation: "worktree"`), then the main agent merges branches at each phase gate.

## Visual references (user-supplied, folded into D1/D2 scope)
1. **Hawaii bullet-journal spread** — text wraps tightly around photos, marker-highlighter captions with hand-drawn arrows, tropical washi tape on photo tops, coloured edge strips, a title in brush script with a framed date/place box. Takeaway: dense, text-wrapping stop pages and arrow-linked captions.
2. **Himachal trip journal** — a dashed route line with arrowheads that wanders from photo to photo across both pages, "Day N" flag banners, place names in handwriting beside pins, a bus icon and a home icon on the route. Takeaway: the route is a drawn path through the page content, matching the spec's "route is the spine".
3. **Japan vintage kraft spread** — closest to Vintage Kraft: torn-edge paper, polaroids with captions, a postage stamp, round postmark, wax seal, washi strips, pressed flowers, pins, ruled note cards, script title. Takeaway: the target look for assets and component list.
(Image 4 duplicates image 1.)

D1 should treat image 3 as the style target for textures/assets; D2 should use images 1–2 for text-wrap and route-through-page layout rules. Keep the spec's colour tokens as the source of truth.

## Phase 0 — Research & spikes (5 subagents, parallel)

| # | Agent | Area | Output (written to `docs/research/`) |
|---|-------|------|------|
| D1 | Design-Tokens | Vintage Kraft colour tokens (paper, kraft, ink, route…), Allura/Lora/Caveat/Special Elite bundling (OFL, `UIAppFonts`, Dynamic Type handling for non-system fonts), asset inventory (grain, torn edges ×3, washi ×3, polaroid, stamp frame, postmark, seal, clip, 6 category icons, 8 transport icons) and how to source/draw them (SwiftUI shapes vs. PNG/SVG) | `design-tokens.md`, asset checklist |
| D2 | Design-Components | Component specs (Polaroid, taped photo, note card, highlight strip, place ticket, postmark, rating stamp, leg connector, route map card, stats strip), 5 stop-page templates by photo count (0–4), seeded ±4° rotation, tape/seal limits, route entry/exit-side rule, phone 24pt vs PDF 36pt margins; calm editor-screen style | `component-specs.md`, template wireframes |
| L1 | Data & Persistence | SwiftData models Journey/Stop/Leg (fields, required/optional, cascade, ordering, Leg auto-sync on reorder/delete), photo files on disk + path refs, draft/offline behaviour, migration-safe design | `data-model.md` |
| L2 | Photo → Place pipeline | PhotosPicker + camera, PHAsset/EXIF GPS+time, clustering (~150 m / ~30 min), MKLocalPointsOfInterestRequest → reverse-geocode → MKLocalSearch fallback, permission-in-context flow, GPS-less photos ("Find this place") | `photo-place-pipeline.md` + threshold spike |
| L3 | Story engine, Map & PDF | One layout engine for both outputs, tap interactions (pins, segments, legs), MKMapSnapshotter + sepia/paper treatment + overlay drawing, `ImageRenderer` → multi-page PDF, interactive-vs-static parity, text overflow (soft ~120-word limit) | `story-engine.md`, throwaway one-page PDF spike (spec's own next step) |

**Exit gate:** all 5 reports reviewed by main agent; no open questions remain (all decided above). Prototype of one stop page + PDF export validates the look.

## Phase 1 — Foundations (3 build agents, parallel; disjoint folders)
- **B1 DesignSystem/** — tokens, fonts, `Theme` environment, reusable components (Polaroid, NoteCard, Tape, Highlight, Ticket, Postmark, RatingStamp), asset catalog.
- **B2 Models/** — SwiftData Journey/Stop/Leg (replace `Item.swift`), photo file store, seed/sample data (CST → Sardar Pav Bhaji → Siddhivinayak → hotel).
- **B3 App shell** — `TravelJournalApp` container setup, navigation, journey shelf (book-cover list), create-journey screen (title, date, city).

Gate: builds, shelf shows sample journey, component gallery preview renders.

## Phase 2 — Capture & edit flow (screens 2–6 of the 8-screen journey)
Add photos (camera/library) → auto-group into suggested stops → place detection/search → stop editor (all Stop fields) → leg editor (mode, km, minutes, leg story) → reorder/delete stops. Agents: **B1 editor UI**, **B2 photo/place services** (L2 pipeline), **B3 grouping + leg sync**.
Gate: a full journey can be created from real photos on device, with legs correctly regenerated after reorder/delete.

## Phase 3 — Story engine
Layout engine producing page models (cover, route overview, stop pages by template, leg connectors, closing "day in numbers"); seeded rotations; route continuity across pages; sepia map snapshot with numbered pins and stats strip. Agents: **B1 page views**, **B2 map overview + stats**, **B3 layout/template selection + seeding**.
Gate: all pages render in SwiftUI previews for 0–4 photo stops.

## Phase 4 — Viewer & PDF
Interactive viewer (horizontal page swipe, pin → stop jump, route segment/leg tap → card, full-screen photo, edit button → stop editor) and PDF export (A4, 36pt margins, leg stories as note cards, share sheet / Files). Agents: **B1 viewer**, **B2 PDF export**, **B3 tests**.
Gate: PDF matches in-app pages visually; edit→view loop works.

## Phase 5 — Polish & release
Offline/draft behaviour, permission-denied states, GPS-less photo path (WhatsApp images), Dynamic Type on UI controls, accessibility labels, performance with large photos, XCTest/UI tests, TestFlight build. Main agent only, with one review pass (`/code-review`).

## Out of scope (per spec)
v1.1: hero/layout picker, MKDirections prefill, square export. v2+: extra themes, multi-day, AI prose, web link, live mode, freeform editor, print, collaboration.

## Verification
- Phase 0: research docs exist, spike PDF opens and shows a polaroid + note card with Vintage Kraft fonts.
- Each phase gate above: `xcodebuild -scheme TravelJournal -destination 'platform=iOS Simulator,name=iPhone 16' build test` passes; manual run in simulator.
- End-to-end: create "A Day in Mumbai" from sample photos → 4 stops, 3 legs → view story → tap a leg card → export PDF → open in Files and compare against in-app pages.
