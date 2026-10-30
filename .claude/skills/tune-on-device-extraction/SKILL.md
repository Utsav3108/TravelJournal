---
name: tune-on-device-extraction
description: Use when writing or improving prompts, schemas or parsers that turn text into structured fields with Apple's on-device language model (FoundationModels @Generable), including speech-to-form extraction.
---

# Tuning on-device extraction

Findings from the voice-entry tuning run (107 cases; details and scores in `references/results.md`).

## Schema shape
- **Put a presence flag before every optional value** (`hasRating: Bool`, then `rating: Int`), and map a false flag to nil in code. With plain optionals the small model almost never returns nil for enums and numbers (it writes 1, 0, walk, other): about 60% invented fields. With flags: about 2%. See `references/VoiceStopDraft_presenceFlags.swift.txt`.
- Strings come back as nil, "" or the literal text "null"; clean them in the mapper.
- Keep the app-facing type a plain optional struct and map the model's output into it, so the applier and its tests do not depend on the model's shape.

## What the model is bad at
- Clock times and durations ("an hour and a half" became 60). Parse these with rules and let the rule result win; see `VoiceTimeParser`.
- Digits inside other numbers (room numbers, years, "5 star experience" read as a cost). A keyword gate per field drops values whose topic never appears in the transcript. The gate gain measured on the training set is optimistic.
- Category and ride-versus-stay durations are judgement calls; test them by hand.

## Method
1. Build a corpus of realistic speech-recognition text (lowercase, no punctuation, fillers, digits, local place names) with expected fields; `references/corpus.json` is a start.
2. Keep about 25% as a hold-out that you never inspect while tuning; report its score only at the end.
3. Score per field; count an invented field as three times worse than a miss; run each case several times and take the majority (output is nondeterministic, noise about plus or minus 0.1).
4. Run strictly serially: the on-device model is a shared resource and each call takes about 4 to 8 seconds.
5. Check `SystemLanguageModel.default.availability` first. If it is not `.available`, stop and say so; never invent scores.

Harness: `references/main.swift` (optional-shape) and `references/B/main.swift` (flag shape) call the real model; `references/score.py` and `references/gate.py` score and gate the outputs. They were run from a scratch folder with a compiled `harness` binary, so adapt paths.
