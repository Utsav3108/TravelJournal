# Resolved decisions (Phase 0 review)

1. Phone layout: pages REFLOW on phone (match PDF in components, rotation seeds, route continuity); not a scaled A4 canvas. PDF uses the A4 595x842pt layout with 36pt margins; phone uses 24pt.
2. Light appearance only for v1 (`UIUserInterfaceStyle` Light / `.preferredColorScheme(.light)`).
3. Stats "total time" = time spent at stops + travel time; strip also shows travel time separately.
4. A leg with no transport mode does NOT block export; connector shows distance/time only.
5. Deployment target stays as in the Xcode project (iOS 27.0).
6. Add an "other" category icon (generic pin); draw the auto-rickshaw icon in-house.
7. 100 words per stop (WordLimit), A4 only, Mood/Tip cut, app name TravelJournal.
8. Special Elite is Apache-2.0 (not OFL): acceptable to bundle; keep its LICENSE file with the font.
