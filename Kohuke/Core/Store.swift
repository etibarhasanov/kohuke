import Foundation
import Observation

/// Everything the app knows: who is signed in, the language it is read in,
/// the shelf, and the answers a signed-out phone is holding.
///
/// One store rather than several, because one request answers all of it.
/// `GET /api/flashcard` comes back with the decks, the lessons, the songs and
/// the conversations, how many words this person knows, who they are, and
/// the words every screen is printed with in the language asked for. The
/// website's page boots from that one answer, and so does this.
///
/// THE WORDS ON THE SCREENS are the website's own. The answer carries the
/// site's `ui` block for the language, and every screen asks for its strings
/// by the site's keys — `flashKnew`, `flashOpens`, `accountSignIn` — with the
/// English written beside the key for the first launch on a plane. A sentence
/// fixed in the site's `data/ui.json` is fixed here on the next launch. The
/// few strings only an app needs are in `Seed/app-strings.json`, in the same
/// three languages the cards are turned over into.
///
/// SIGNED OUT, five words. The decks can be read by anybody, and the first
/// five cards a phone answers are kept on the phone (`kept` below); after
/// that the run asks for an account, the way the website's does, and signing
/// in sends the five along so they are not answered twice.
@MainActor
@Observable
final class Store {
    // MARK: Who

    var user: String?
    /// Whether the site has said yet who this is.
    var checked = false
    /// Whether the site can finish a Google or an Apple sign-in for an app.
    #if DEBUG
    var googleOffered = LaunchScript.doors
    var appleOffered = LaunchScript.doors
    #else
    var googleOffered = false
    var appleOffered = false
    #endif

    var signedIn: Bool { user != nil }

    // MARK: The shelf

    private(set) var decks: [DeckRow] = []
    private(set) var lessons: [Lesson] = []
    private(set) var songs: [Song] = []
    private(set) var talks: [Talk] = []
    /// How many of the site's words this person knows, which is what the two
    /// stages open on.
    private(set) var words = 0
    private(set) var gates: [String: Int] = ["more": 100, "deep": 400]
    private(set) var days: Days?
    /// False where the site has no database to remember anything in.
    private(set) var ready = true
    /// Whether the shelf has been asked for at least once.
    private(set) var loaded = false
    /// Whether the last thing asked for came from the phone rather than the site.
    private(set) var offline = false

    // MARK: Language

    static let fallbackLanguages = [
        Language(code: "az", name: "Azərbaycan"),
        Language(code: "en", name: "English"),
        Language(code: "ru", name: "Русский")
    ]

    private(set) var lang: String
    private(set) var languages = Store.fallbackLanguages
    private var ui: [String: String] = [:]
    private let own: [String: [String: String]]

    init() {
        let kept = UserDefaults.standard.string(forKey: "lang")
        let device = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        let codes = Store.fallbackLanguages.map(\.code)
        lang = kept.flatMap { codes.contains($0) ? $0 : nil } ?? (codes.contains(device) ? device : "en")
        own = Disk.seed("app-strings")
            .flatMap { try? JSONDecoder().decode([String: [String: String]].self, from: $0) } ?? [:]
        if let data = Disk.read(shelfFile) { adopt(data, shelf: true) }
    }

    /// The site's sentence for a key, in the language being read, with the
    /// English to fall back on and `{n}`-style gaps filled.
    func t(_ key: String, _ english: String, _ gaps: [String: String] = [:]) -> String {
        var text = ui[key] ?? own[key]?[lang] ?? english
        for (name, value) in gaps { text = text.replacingOccurrences(of: "{\(name)}", with: value) }
        return text
    }

    func means(_ said: Said?) -> String { said?.in(lang) ?? "" }

    func choose(language code: String) async {
        guard code != lang else { return }
        lang = code
        UserDefaults.standard.set(code, forKey: "lang")
        if let data = Disk.read(shelfFile) { adopt(data, shelf: true) }
        await refresh()
    }

    // MARK: Asking

    private var shelfFile: String { "shelf-\(lang).json" }

    /// The shelf, fresh. On a train it is the last one the phone was given.
    func refresh() async {
        do {
            let data = try await API.data("api/flashcard", ["lang": lang])
            adopt(data, shelf: true)
            Disk.write(data, shelfFile)
            offline = false
        } catch {
            offline = true
        }
        loaded = true
    }

    /// One deck, lesson, song or conversation, whole. A 404 is an answer too
    /// — `error: not-found` — and the screens say the site's sentence for it.
    /// Off the network it is the copy kept from the last time it was opened.
    func open(_ id: String) async -> Answer? {
        let file = "one-\(id)-\(lang).json"
        do {
            let (data, status) = try await API.fetch("api/flashcard", ["lang": lang, "deck": id])
            guard let answer = adopt(data, shelf: false) else { return nil }
            if status == 200 { Disk.write(data, file) }
            offline = false
            return answer
        } catch {
            offline = true
            return Disk.read(file).flatMap { try? JSONDecoder().decode(Answer.self, from: $0) }
        }
    }

    /// Reads an answer into the store. Every answer carries who is asking,
    /// how many words they know and the screen's words; only the shelf's
    /// carries the rows.
    @discardableResult
    private func adopt(_ data: Data, shelf: Bool) -> Answer? {
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return nil }
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let block = object["ui"] as? [String: Any] {
            let strings = block.compactMapValues { $0 as? String }
            if !strings.isEmpty { ui = strings }
        }
        if let known = answer.words { words = known }
        if let both = answer.gates { gates = both }
        if let list = answer.langs, !list.isEmpty { languages = list }
        ready = answer.ready ?? true
        if shelf {
            user = answer.user
            days = answer.days
            decks = answer.decks ?? []
            lessons = answer.lessons ?? []
            songs = answer.songs ?? []
            talks = answer.talks ?? []
        }
        return answer
    }

    /// What a stage opens at, or nought once it is open: `shutAt()` in the route.
    func gate(_ level: String?) -> Int {
        guard ready, let level, let gate = gates[level], gate > words else { return 0 }
        return gate
    }

    // MARK: Answering

    /// The deck ids a lesson read, a song heard and a conversation read are
    /// filed under: `GRAMMAR_DECK`, `SONG_DECK` and `TALK_DECK` in the route.
    static let grammarDeck = "grammar"
    static let songDeck = "songs"
    static let talkDeck = "talks"

    /// How many words a phone may answer signed out: `FREE_WORDS` on the site.
    static let freeWords = 5
    private static let keptKey = "kept"
    private static let maxKept = 200

    /// The answers a signed-out phone is holding, by `deck/card`.
    private var kept: [String: Bool] {
        get { UserDefaults.standard.dictionary(forKey: Self.keptKey) as? [String: Bool] ?? [:] }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.keptKey)
            stamp += 1
        }
    }

    /// Goes up whenever `kept` changes. The answers live in UserDefaults,
    /// which a screen cannot watch, so the screens that read them watch this.
    private var stamp = 0

    /// How many cards, as opposed to lessons, songs and conversations, the
    /// phone has answered signed out. Reading and listening spend nothing.
    private var answered: Int {
        kept.keys.filter { key in
            ![Self.grammarDeck, Self.songDeck, Self.talkDeck].contains { key.hasPrefix($0 + "/") }
        }.count
    }

    /// Whether answering this card signed out would use up the free words.
    func spends(deck: String, card: String) -> Bool {
        guard !signedIn, ready else { return false }
        return answered + (kept["\(deck)/\(card)"] == nil ? 1 : 0) >= Self.freeWords
    }

    /// One answer: a card known or missed, a lesson read, a song heard. It
    /// does not wait and a failure is silent — what a lost write costs is the
    /// card coming round again, and a card that hung on the network each time
    /// would be unusable. Signed out it is written down on the phone instead.
    func answer(deck: String, card: String, knew: Bool) {
        noteDay()
        guard signedIn, ready else {
            var all = kept
            let key = "\(deck)/\(card)"
            if all[key] == nil && all.count >= Self.maxKept { return }
            all[key] = knew
            kept = all
            return
        }
        let body: [String: Any] = ["action": knew ? "knew" : "again", "deck": deck, "card": card, "day": Self.today()]
        Task { _ = try? await API.post("api/flashcard", body) }
    }

    /// A lesson read, a song heard or a conversation read: the same answer a
    /// card gets, filed under one of the three ids above. This one waits for
    /// the write, because the shelf is asked for again straight after and
    /// should come back saying Read.
    func finish(_ shelf: String, _ id: String) async {
        guard signedIn, ready else {
            answer(deck: shelf, card: id, knew: true)
            return
        }
        _ = try? await API.post("api/flashcard", ["action": "knew", "deck": shelf, "card": id, "day": Self.today()])
        await refresh()
    }

    /// Whether one of those is done: the site's word for it, or, signed out,
    /// the phone's own note.
    func done(_ shelf: String, _ id: String, _ said: Bool?) -> Bool {
        _ = stamp
        return said == true || kept["\(shelf)/\(id)"] == true
    }

    /// The count the shelf prints, kept in step with a run while it is going.
    func nudge(words by: Int) { words = max(0, words + by) }

    /// Everything the phone was holding, now that there is an account to put
    /// it in. Cleared before the writes go out: a failure halfway loses the
    /// rest rather than sending them all twice.
    func sendKept() async {
        let all = kept
        guard signedIn, !all.isEmpty else { return }
        kept = [:]
        for (key, knew) in all {
            guard let slash = key.firstIndex(of: "/") else { continue }
            _ = try? await API.post("api/flashcard", [
                "action": knew ? "knew" : "again",
                "deck": String(key[..<slash]),
                "card": String(key[key.index(after: slash)...]),
                "day": Self.today()
            ])
        }
    }

    /// Start a deck again: forget what is known of it.
    func reset(_ deck: String) async throws {
        try await API.post("api/flashcard", ["action": "reset", "deck": deck])
    }

    /// Say a card the site ships is wrong. The one write that needs nobody.
    func report(deck: String, card: String) async throws {
        try await API.post("api/flashcard", ["action": "report", "deck": deck, "card": card, "lang": lang])
    }

    // MARK: Decks of your own

    /// Every write to a deck of your own answers the deck, whole.
    func write(_ body: [String: Any]) async throws -> Deck? {
        let data = try await API.post("api/flashcard", body)
        return (try? JSONDecoder().decode(Answer.self, from: data))?.deck
    }

    // MARK: Days in a row

    /// The reader's own calendar day, not Tallinn's: somebody revising at
    /// eleven at night should not lose a day to a midnight they are not in.
    static func today() -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func daysBetween(_ from: String, _ to: String) -> Int {
        let read = ISO8601DateFormatter()
        guard let a = read.date(from: from + "T12:00:00Z"), let b = read.date(from: to + "T12:00:00Z") else { return 0 }
        return Int((b.timeIntervalSince(a) / 86400).rounded())
    }

    /// Signed out, the two facts are the phone's own, written on every answer.
    private func noteDay() {
        guard !signedIn else { return }
        let now = Self.today()
        let was = localDays
        if was?.last == now { return }
        let run = was.map { Self.daysBetween($0.last, now) == 1 ? $0.run + 1 : 1 } ?? 1
        if let data = try? JSONEncoder().encode(Days(last: now, run: run)) {
            UserDefaults.standard.set(data, forKey: "days")
        }
    }

    private var localDays: Days? {
        UserDefaults.standard.data(forKey: "days").flatMap { try? JSONDecoder().decode(Days.self, from: $0) }
    }

    /// How many days in a row, where it is more than one and still going.
    var daysRunning: Int {
        guard let days = signedIn ? days : localDays else { return 0 }
        return Self.daysBetween(days.last, Self.today()) <= 1 && days.run > 1 ? days.run : 0
    }
}

/// The website's own sentence for a refusal, in the reader's language.
extension Store {
    func say(_ error: Error) -> String {
        guard let refusal = error as? API.Refusal else {
            return t("appOffline", "Couldn’t reach tallinntastebuds.ee.")
        }
        switch refusal.code {
        case "username": return t("accountErrUsername", "Use 3 to 24 letters, numbers, dots, dashes or underscores.")
        case "password": return t("accountErrPassword", "Password must be at least 8 characters.")
        case "taken": return t("accountErrTaken", "That username is taken.")
        case "no-match": return t("accountErrNoMatch", "Wrong username or password.")
        case "google", "ticket": return t("accountErrGoogle", "Google sign-in did not finish. Try again.")
        case "apple": return t("appErrApple", "Apple sign-in did not finish. Try again.")
        case "slow-down": return t("accountErrSlow", "Too many tries. Wait a few minutes.")
        case "current": return t("accountErrCurrent", "That is not the password you use now.")
        case "confirm": return t("accountErrDeleteConfirm", "Type your username exactly as it is.")
        case "signed-out": return t("accountErrSignedOut", "You have been signed out. Sign in again.")
        case "name": return t("flashErrName", "Give the deck a name.")
        case "front": return t("flashErrFront", "Write the Estonian side.")
        case "back": return t("flashErrBack", "Write what it means.")
        case "too-many": return t("flashErrTooMany", "An account can hold only so many decks.")
        case "full": return t("flashErrFull", "This deck is full.")
        case "often": return t("flashErrOften", "That is a lot in an hour. Give it a little while.")
        case "not-found": return t("flashErrGone", "There is no deck or lesson by that name.")
        default: return t("flashErrGeneric", "That did not work. Try again in a moment.")
        }
    }
}
