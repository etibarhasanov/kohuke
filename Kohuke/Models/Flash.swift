import Foundation

// What `/api/flashcard` answers, as the website's own page reads it. The
// shapes are `deckAnswer()`, `lessonAnswer()`, `songAnswer()` and
// `talkAnswer()` in `functions/api/flashcard.js` in the website's repository,
// and a field the route may leave out is optional here, so a phone that keeps
// this build for a year still reads an answer that has grown.

/// Words that come in the reader's language.
///
/// A deck the site ships carries its name, the line under it and the back of
/// every card as an object keyed by language — English, Azerbaijani, Russian,
/// and `et` beside them where the thing is a sentence. A deck somebody wrote
/// carries one plain string, in whatever language they typed. Both arrive in
/// the same field, so this reads either.
struct Said: Decodable, Hashable {
    private let plain: String?
    private let by: [String: String]

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if let text = try? box.decode(String.self) {
            plain = text
            by = [:]
        } else {
            plain = nil
            by = (try? box.decode([String: String].self)) ?? [:]
        }
    }

    /// In the language asked for, or English where there is none: `means()`
    /// in the website's `assets/flashcard.js`.
    func `in`(_ lang: String) -> String { plain ?? by[lang] ?? by["en"] ?? "" }

    /// The Estonian of a sentence, a line of a song or a turn of a talk.
    var et: String { by["et"] ?? "" }

    /// Whether this came keyed by language, which only the site's own words do.
    var shipped: Bool { plain == nil }
}

/// Every answer of the route, whichever it is: the shelf (`decks`, `lessons`,
/// `songs`, `talks`), or one deck, lesson, song or conversation.
struct Answer: Decodable {
    var ready: Bool?
    var user: String?
    var words: Int?
    var gates: [String: Int]?
    var days: Days?
    var lang: String?
    var langs: [Language]?
    var decks: [DeckRow]?
    var lessons: [Lesson]?
    var songs: [Song]?
    var talks: [Talk]?
    var deck: Deck?
    var lesson: Lesson?
    var song: Song?
    var talk: Talk?
    var error: String?
}

struct Language: Decodable, Hashable, Identifiable {
    let code: String
    let name: String
    var id: String { code }
}

/// The last day a card was answered and how many days ran into it.
struct Days: Codable {
    let last: String
    let run: Int
}

/// A deck as the shelf lists it: its counts, and none of its cards.
struct DeckRow: Decodable, Identifiable, Hashable {
    let id: String
    let name: Said?
    let why: Said?
    let level: String?
    let cards: Int
    let known: Int
    let due: Int?
    let own: Bool?
    /// The day it went in, `2026-09-18`, which is what New is judged by.
    let added: String?
    /// The two that are assembled rather than stored: every card somebody
    /// got wrong, and every card they know.
    let review: Bool?
    let missed: Bool?

    var gathered: Bool { review == true || missed == true }
}

struct Deck: Decodable {
    let id: String
    var name: Said?
    let why: Said?
    let level: String?
    let own: Bool?
    var cards: [Card]
    let review: Bool?
    let missed: Bool?
}

struct Card: Decodable, Identifiable, Hashable {
    /// The deck the card is really from, which differs from the one it is
    /// shown in only in the two gathered decks.
    let deck: String?
    let id: String
    let front: String
    let back: Said
    /// The second and third form of a noun: omastav and osastav.
    let forms: [String]?
    let sentence: Said?
    let build: Build?
    var known: Bool?
    var due: Bool?

    /// Only a card out of the site's own file can be said aloud or reported
    /// wrong: the voice reads nothing else, and a deck somebody typed has an
    /// editor instead of a report.
    var shipped: Bool { back.shipped }
}

/// How a case form on a card is made: the three forms, which of them the
/// ending goes on, and what comes out.
struct Build: Decodable, Hashable {
    let forms: [String]?
    let on: Int?
    let from: String?
    let end: String?
    let makes: String?
    let short: String?
    let `case`: Said?
}

/// A grammar lesson: on the shelf without its body, opened with it.
struct Lesson: Decodable, Identifiable, Hashable {
    let id: String
    let name: Said
    let why: Said?
    let taste: String?
    let added: String?
    /// The deck that follows the lesson, where it has one.
    let deck: String?
    /// `cases` for the lessons under "The cases, one by one".
    let heading: String?
    let body: [Block]?
    var read: Bool?

    var underCases: Bool { heading == "cases" }
}

/// One piece of a lesson. Exactly one of the four is there.
struct Block: Decodable, Hashable {
    let say: Said?
    let head: Said?
    let table: Paradigm?
    let examples: [Said]?
}

struct Paradigm: Decodable, Hashable {
    let heads: [Said]
    let rows: [Row]

    struct Row: Decodable, Hashable {
        let et: [String]
        let means: Said?
    }
}

/// A deck by its id and name, as a song or a word in one names it.
struct DeckRef: Decodable, Hashable {
    let id: String
    let name: Said?
}

/// What a word in a song or a conversation means.
struct Gloss: Decodable, Hashable {
    let base: String?
    let means: Said?
    let note: Said?
    let deck: DeckRef?
}

struct Song: Decodable, Identifiable, Hashable {
    let id: String
    let name: Said
    let why: Said?
    let taste: String?
    let added: String?
    var heard: Bool?
    /// The YouTube id of the recording.
    let video: String?
    let credit: Credit?
    /// The deck of the song's own words.
    let deck: DeckRef?
    let verses: [[Said]]?
    let words: [String: Gloss]?

    struct Credit: Decodable, Hashable {
        let words: String?
        let music: String?
    }
}

struct Talk: Decodable, Identifiable, Hashable {
    let id: String
    let name: Said
    let why: Said?
    let taste: String?
    let added: String?
    var read: Bool?
    let source: String?
    let scenes: [Scene]?
    let words: [String: Gloss]?

    struct Scene: Decodable, Hashable {
        let ask: Said?
        let turns: [Turn]?
    }

    struct Turn: Decodable, Hashable {
        let who: String?
        let lines: [Said]?
    }
}
