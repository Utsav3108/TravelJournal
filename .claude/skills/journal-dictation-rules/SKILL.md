---
name: journal-dictation-rules
description: Use when changing or testing the Mac voice-to-form feature (hold to speak), or when deciding which stop field a spoken phrase should fill and what may be overwritten.
---

# How travellers dictate, and what each phrase fills

Code: `TravelJournal/macOS/Voice` (`VoiceTimeParser`, `VoiceDraftMapper` in `VoiceExtractor.swift`, `VoiceDraftApplier`, `VoiceDictationController`).

## What the transcript looks like
Speech recognition output is lowercase-ish with digits and little punctuation: "so we reached chatrapati shivaji terminus at some 1030 am", "i would give some 4 star rating", "1st". Rupees, auto-rickshaws, local trains and Indian place names are common. A bare "at 2" or "1030" without a colon is ambiguous; leave those to the model.

## Field rules
- **Arrival:** stated outright, so it may correct an existing stop's time (same day, in the journey's time zone). Times after "left", "until", "closes" are not arrivals.
- **Place name:** set only on a new stop (empty name and empty story). **Category:** set on a new stop, or when the stop has none.
- **Time spent:** a duration spent at the place. A walk, ride or "took an hour to reach" is travel, not time spent. "an hour and a half" is 90; "half an hour" is 30.
- **Story:** appended to the existing story, capped at 100 words. **Highlight:** at most 60 characters.
- **Rating:** 1 to 5. **Cost:** a plain number, "free" is 0, currency defaults to INR.
- **Got here by:** sets the stop's incoming leg; skipped on the first stop.
- Unchanged values are not reported as changes; one dictation is one undo step for the stop, and the card's Undo also restores the leg.

## Phrases to re-test by voice
"I arrived at 2 pm", "reached at 10:30 am", "spent an hour and a half", "spent half an hour", "walked 20 minutes to get there" (must not set time spent), "took an auto, 90 rupees, about 2 hours, three stars", "the ticket was free", a Hindi place name.

If a phrase misbehaves, reproduce it as a test first (`VoiceTimeParserTests`, `VoiceDraftMapperTests`), then fix the rule.
