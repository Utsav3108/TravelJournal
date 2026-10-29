#if os(macOS)
/// Instructions and `@Guide` text for `VoiceStopDraft`, tuned with an on-device harness (see results.md).
/// IMPORTANT: with the current Optional enum/Int shape the model almost never returns nil. The measured-good
/// configuration pairs these strings with presence flags (has* Bools) in VoiceStopDraft, plus keyword gating.
enum VoiceExtractionPrompts {
    static let instructions = """
    Extract journal fields from one spoken sentence (raw speech recognition: lowercase, no punctuation, fillers). Output null for every field the sentence does not explicitly state. Most sentences state only one or two things, so most fields must be null. Never guess, never use a default such as 0, 1, walk, other or an invented time.

    Examples (field: value, unlisted fields are null):
    "so we reached amber palace around 11 15 took a cab it was 90 rupees about 2 hours three stars" -> placeName: amber palace, arrival: 11:15, travelMode: taxi, cost: 90, minutesSpent: 120, rating: 3, category: landmark
    "the museum ticket was free" -> cost: 0
    "i rate it 4" -> rating: 4
    "we hung around for 25 minutes" -> minutesSpent: 25
    "we pulled up at 8 20 am" -> arrival: 08:20
    "we hopped on the blue line metro" -> travelMode: metro (metro is not a place)
    "paid 75 rupees" -> cost: 75
    "uh okay testing one more time" -> all null
    "uh" -> all null
    "we booked room 118 and the wifi was bad" -> story only: I booked room 118 and the wifi was bad. (a room number is not a cost or rating)
    "this fort dates back to 1570 and has 9 gates" -> all null (years and counts are not times, ratings or costs)
    "i forgot what we paid" -> cost null, everything else null
    "the sea breeze at the pier felt great" -> story: The sea breeze at the pier felt great. highlight: Sea breeze at the pier. placeName null, category null

    Rules: placeName only for a proper noun naming a specific place (juhu beach, lodhi garden, colaba causeway). Never a generic word (place, temple, market, station, room, caves), a vehicle (bus, metro, ola, ferry), an item (tickets, souvenirs, food), a thing (rs, 6pm), or a person. A sentence that only gives a price, time, rating, vehicle or feeling has no place. Fields not mentioned stay null: do not add category, travelMode, rating, cost, minutes or arrival to fill gaps. Rating, cost, minutes and arrival must never be taken from room numbers, bus numbers, phone numbers, years, ages or counts. story and highlight only restate what was said; null for small talk, test phrases, or a sentence that only gives one number.
    """

    static let placeName = "Proper noun naming a specific place, exactly as spoken. null for generic words, vehicles, items, prices, or times."
    static let category = "Kind of place, only if a place is named or its type is stated. null if the sentence is about price, time, rating, transport, small talk or feelings only."
    static let arrival = "Arrival clock time as 24-hour HH:mm (2 30 pm = 14:30). null if no arrival time was spoken."
    static let story = "First-person retelling of what was said about the visit, at most 100 words, nothing added. null for small talk or pure numbers."
    static let highlight = "Best moment as a phrase under 60 characters. null unless one was described."
    static let rating = "Stars 1-5, only if a star count or score out of 5 was spoken. null otherwise."
    static let cost = "Money spent as a plain number, only if an amount was spoken; free or spent nothing = 0. null otherwise."
    static let minutes = "Minutes spent at the place, only if a duration was spoken (an hour = 60). null otherwise."
    static let travelMode = "Vehicle or walking, only if explicitly said (auto = autoRickshaw, cab or ola = taxi, train = localTrain). null otherwise."
}
#endif
