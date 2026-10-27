# TravelJournal: Status of Completion

_As of 2026-10-20, `main` at `a47119d`._

## Summary
v1 is feature-complete against the spec (`docs/task.pdf`) and decisions (`docs/decisions.md`). All 81 unit tests pass, and the story-viewer UI test passed on the iPhone 18 Pro simulator (iOS 27). **Nothing has been tested on a real iPhone yet.**

## Phases
| Phase | Scope | Status | Outcome |
|---|---|---|---|
| 0 | Research | Done | 5 research reports in `docs/research/`, PDF spike, 8 decisions recorded |
| 1 | Foundations | Done | Design system (Vintage Kraft tokens, fonts, components), SwiftData models, app shell, shelf, create-journey |
| 2 | Capture and edit | Done | Photo import, camera, clustering, place lookup, stop and leg editors, reorder/delete with leg sync |
| 3 | Story engine | Done | Shared page model, layout templates by photo count, seeded rotations, route continuity, map overview |
| 4 | Viewer and PDF | Done | Swipe viewer, pin/leg/photo taps, edit-from-viewer, A4 PDF export with share |
| 5 | Polish | Mostly done | Review fixes, camera in capture flow, cover photos, accessibility, editor fixes |

## Feature checklist
- [x] Add photos from library; take photos with camera
- [x] Auto-group photos into stops (150 m / 30 min); place detection and manual search
- [x] Stop editor (name, category, time, photos, highlight, rating, cost, story with 100-word limit)
- [x] Leg editor (transport mode, minutes, km, leg story); legs re-sync on reorder/delete
- [x] Story viewer: cover, route overview, stop pages (0-4 photos), leg cards, closing stats
- [x] A4 PDF export (36 pt margins, JPEG re-encoded to keep size down, about 4.4 MB worst case)
- [x] Shelf with cover photos; delete story also deletes its photo files
- [x] Add photos to an existing stop (picker works on saved stops; new stops must be saved first)
- [x] Travel rows show Add/Edit with a chevron
- Cut by decision: Mood, Tip, square export. A4 only, light appearance only.

## Open items
1. **Real-device testing** (camera, photo-library limited access, share sheet, MapKit rate limits).
2. **Camera location:** `CameraCaptureView` creates a fresh location manager and reads at once, so camera photos may lack GPS.
3. **Store failure:** `Schema.swift` silently falls back to an in-memory store; stories would vanish on relaunch with no warning.
4. **PDF temp files** are never cleaned up.
5. **Short stories** leave blank space on phone stop pages.
6. **TestFlight** needs your Apple developer account and signing.

## Run and test
- Simulator: iPhone 18 Pro, id `BAA262D0-39D8-41CA-B50A-116633D830A1`.
- Build: `xcodebuild -scheme TravelJournal -destination 'platform=iOS Simulator,id=BAA262D0-39D8-41CA-B50A-116633D830A1' build`
- Run tests serially; if `xcodebuild test` hangs after "Executed N tests", kill it.
- Debug launch args: `-openSample`, `-openSampleStop`, `-openSampleStory`, `-openSampleStoryPage N`, `-openSampleLegCard`. They open the first stored journey, so uninstall the app to reset stale data.

## References
`PLAN.md`, `docs/decisions.md`, `docs/research/`, `docs/task.pdf`.
