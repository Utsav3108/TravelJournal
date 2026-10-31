# TravelJournal

SwiftUI travel journal for iPhone and Mac (SwiftData). Light appearance only. iOS and macOS deployment target 27.0.
Specs: `docs/task.pdf`, `docs/Mac-Task.pdf`; decisions: `docs/decisions.md`; status and run notes: `docs/STATUS.md`.

## Layout
- `TravelJournal/Shared` (models, services, shared forms), `TravelJournal/iOS`, `TravelJournal/macOS`; tests in `TravelJournalTests`.
- The Xcode project uses file-system-synchronized groups: new `.swift` files need no project edits.
- Mac-only code is wrapped in `#if os(macOS)`. The Mac voice feature lives in `TravelJournal/macOS/Voice`.

## Swift conventions
- Default actor isolation is MainActor. Pure helper types and enums are marked `nonisolated` (see `StopCategory`).
- Keep logic in small testable enums (like `EditorLogic`, `VoiceDraftApplier`); views stay thin.
- Undo is explicit: value snapshots (`StopContent`, `LegContent`) plus `undoTracked`. Never attach SwiftData's own undo manager (it crashed on cascade delete).
- Stop story is capped at 100 words, highlight at 60 characters (`WordLimit`, `EditorLogic`).

## Commands (run from the repo root)
- Build Mac: `xcodebuild -project TravelJournal.xcodeproj -scheme TravelJournal -destination 'platform=macOS' build`
- Build iOS: same with `-destination 'generic/platform=iOS Simulator'`
- One test class: `... -destination 'platform=macOS' test -only-testing:TravelJournalTests/<ClassName>`
- Full unit suite, serially: `... test -only-testing:TravelJournalTests -parallel-testing-enabled NO`. If it hangs after "Executed N tests", kill it.
- `xcodebuild` output does not show XCTest failure messages. Add `-resultBundlePath X.xcresult`, then read them with `xcrun xcresulttool get test-results tests --path X.xcresult` (walk the JSON for nodes of type "Failure Message").
- macOS has no `timeout` command. Redirect long builds to a log file instead.
- Mac debug launch arguments: `-showInspector`, `-selectStop N` (0-based).

## Known baseline failure
`CarouselRendererTests.testBrandStampOnTheClosingSlideOnly` fails on a clean checkout. It is not caused by your change; don't chase it. Everything else should pass.

## Testing
Code-based tests only. Never write UI tests or drive the running app. For a visual bug, host the view off screen in a test (see `JourneyWindowLayoutTests`).

## Git
- One commit per fix or feature; commit and push only when asked. End commit messages with the attribution line from the session.
- Never stage `default.store`, the runtime folders under `.claude/` (`shots`, `worktrees`), or `design_handoff_hold_to_text/` unless asked.

## Skills (`.claude/skills`)
- `reproduce-and-bisect`: any bug report. `verify-apple-api`: before using an Apple framework API.
- `tune-on-device-extraction`: prompts, schemas or parsers for the on-device language model.
- `journal-dictation-rules`: how travellers dictate and which field each phrase fills.
