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

    /// The beginnings of the keys of every string of the website's this app
    /// prints, which is all it asks the route for: `?ui=` in
    /// `functions/api/flashcard.js`. Without it every answer carried the
    /// site's twelve hundred strings, sixty-five KB, beside a deck of four.
    /// A screen that starts printing a key outside these gets its English
    /// until the prefix is added here.
    static let uiPrefixes = "flash,account,style,language,close,privacy"

    /// When the shelf was last asked for, and how long that answer is good
    /// for when all that has happened is the app coming back to the front.
    private var asked: Date?
    private static let shelfKeeps: TimeInterval = 5 * 60

    /// The app has come to the front: who this is and what is on the shelf,
    /// asked side by side — unless the shelf was asked for in the last five
    /// minutes, when a glance at a message and back is not a reason to ask
    /// again. A launch calls this twice, once for the window and once for
    /// becoming active, and the second finds the first already asking.
    /// Pulling the shelf down, the end of a run and a change of language
    /// ask whatever the clock says: they call `refresh()` themselves.
    func wake() async {
        if let asked, Date().timeIntervalSince(asked) < Self.shelfKeeps {
            if !unsent.isEmpty { await send() }
            return
        }
        async let who: Void = whoAmI()
        async let shelf: Void = refresh()
        _ = await (who, shelf)
    }

    /// The shelf, fresh. On a train it is the last one the phone was given.
    func refresh() async {
        asked = Date()
        do {
            let data = try await API.data("api/flashcard", ["lang": lang, "ui": Self.uiPrefixes])
            adopt(data, shelf: true)
            Disk.write(data, shelfFile)
            offline = false
            // The site is answering: the moment to send what it missed.
            if !unsent.isEmpty { Task { await send() } }
        } catch {
            offline = true
            // Nothing came, so the next time the app comes forward it asks.
            asked = nil
        }
        loaded = true
    }

    /// One deck, lesson, song or conversation, whole, asked for when it is
    /// opened and not before — and not at all where the phone's own copy is
    /// still right: `current()` below. It comes without strings (`ui=` and
    /// nothing after it): the shelf brought them. A 404 is an answer too —
    /// `error: not-found` — and the screens say the site's sentence for it.
    /// Off the network it is the copy kept from the last time it was opened.
    func open(_ id: String) async -> Answer? {
        let file = "one-\(id)-\(lang).json"
        if let kept = current(id, file) { return kept }
        if let made = await fromFiles(id, file) { return made }
        do {
            let (data, status) = try await API.fetch("api/flashcard", ["lang": lang, "deck": id, "ui": ""])
            guard let answer = adopt(data, shelf: false) else { return nil }
            if status == 200 { Disk.write(data, file) }
            offline = false
            return answer
        } catch {
            offline = true
            return Disk.read(file).flatMap { try? JSONDecoder().decode(Answer.self, from: $0) }
        }
    }

    /// How long a kept deck, lesson, song or conversation is read without
    /// asking. A card added or taken away shows in the shelf's count and is
    /// asked for at once; this is how long a word corrected in place on the
    /// website can take to reach a phone that already holds the deck.
    private static let contentKeeps: TimeInterval = 7 * 86400

    /// The phone's own copy of something, where it can be shown without
    /// asking the site. The words rarely change and what somebody knows of
    /// them changes with every card, so the copy is held to the shelf, which
    /// is asked for often and says both:
    ///
    /// - a deck the site ships, when it has as many cards and as many of
    ///   them known as its row on the shelf says. `answer()` marks each card
    ///   in the kept copy as it is answered, so a deck studied on this phone
    ///   still agrees with its row afterwards; one studied on the website
    ///   does not, and is asked for;
    /// - a lesson, a song or a conversation, with whether it has been read
    ///   taken from its row, since that is the one thing in it that is
    ///   somebody's.
    ///
    /// Never the two gathered decks, which are put together anew each time,
    /// nor a deck somebody wrote, whose words can change on the website
    /// without its count changing. And only against a shelf the site has
    /// just given: off the network `open()` falls back to the copy anyway.
    private func current(_ id: String, _ file: String) -> Answer? {
        guard loaded, !offline,
              let age = Disk.age(file), age < Self.contentKeeps,
              let data = Disk.read(file),
              var answer = try? JSONDecoder().decode(Answer.self, from: data) else { return nil }
        if let deck = answer.deck {
            guard deck.own != true, deck.review != true, deck.missed != true,
                  let row = decks.first(where: { $0.id == id }), !row.gathered, row.own != true,
                  deck.cards.count == row.cards,
                  deck.cards.filter({ $0.known == true }).count == row.known else { return nil }
            return answer
        }
        if answer.lesson != nil, let row = lessons.first(where: { $0.id == id }) {
            answer.lesson?.read = row.read
            return answer
        }
        if answer.song != nil, let row = songs.first(where: { $0.id == id }) {
            answer.song?.heard = row.heard
            return answer
        }
        if answer.talk != nil, let row = talks.first(where: { $0.id == id }) {
            answer.talk?.read = row.read
            return answer
        }
        return nil
    }

    // MARK: The words, from the site's files

    /// The names of every deck the site ships, by id, out of the site's
    /// index: asked for once, and only when a song or a conversation names a
    /// deck that is not on this person's shelf.
    private var shippedNames: [String: Any]?

    /// One of the files the website keeps its decks in, `data/decks/<name>.json`:
    /// a deck, a lesson, a song or a conversation, whole, or the index. They
    /// are files and not a Function, so asking for one runs nothing on the
    /// site and reads nothing from its database, and an unchanged one is
    /// answered from the phone's own cache after a word with the site.
    private func siteFile(_ name: String) async -> [String: Any]? {
        guard name.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil,
              let (data, status) = try? await API.fetch("data/decks/\(name).json"), status == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// A deck by its id and name, the way the route names one where the
    /// file only points at it: `named()` in `songAnswer()`.
    private func named(_ id: Any?, _ names: [String: Any]) -> [String: Any]? {
        guard let id = id as? String, let name = names[id] else { return nil }
        return ["id": id, "name": name]
    }

    /// The names of the decks these ids are, from the shelf where it has
    /// them all and from the site's index where it does not: the shelf
    /// leaves out the decks of a stage that has not opened.
    private func names(of ids: Set<String>) async -> [String: Any]? {
        var all: [String: Any] = [:]
        for row in decks { if let name = row.name { all[row.id] = name.raw } }
        if ids.allSatisfy({ all[$0] != nil }) { return all }
        if shippedNames == nil, let list = await siteFile("index")?["decks"] as? [[String: Any]] {
            var read: [String: Any] = [:]
            for one in list { if let id = one["id"] as? String, let name = one["name"] { read[id] = name } }
            shippedNames = read
        }
        return shippedNames
    }

    /// A deck, a lesson, a song or a conversation put together on the phone
    /// out of the site's file and what the shelf says of it, in the shape
    /// the route answers in, where that can be done without asking the
    /// route — which is the only part of opening something that costs the
    /// site a Function and its database. Nothing where it cannot, and then
    /// `open()` asks the route as it always did.
    ///
    /// A lesson, a song or a conversation always can: the words are the
    /// file, and whether it was read is on its row. A deck can when the
    /// phone can tell which of its cards are known:
    ///
    /// - none, where its row says none are, which is every deck a stranger
    ///   or a new account opens;
    /// - all, where its row says all are;
    /// - the ones the phone's last copy has known, where they are as many
    ///   as the row says.
    ///
    /// Otherwise somebody has answered cards somewhere else, and only the
    /// route knows which. The gathered decks, a deck somebody wrote and a
    /// deck that is not on the shelf are the route's as well.
    ///
    /// What the route does to a file on its way out is done here the same:
    /// `deckAnswer()`, `lessonAnswer()`, `songAnswer()` and `talkAnswer()` in
    /// `functions/api/flashcard.js`.
    private func fromFiles(_ id: String, _ file: String) async -> Answer? {
        guard loaded, !offline else { return nil }
        var made: [String: Any]

        if let row = decks.first(where: { $0.id == id }) {
            guard !row.gathered, row.own != true else { return nil }
            var knownIds: Set<String>?
            if row.known > 0 && row.known < row.cards {
                guard let kept = Disk.read(file).flatMap({ try? JSONDecoder().decode(Answer.self, from: $0) })?.deck
                else { return nil }
                knownIds = Set(kept.cards.filter { $0.known == true }.map(\.id))
            }
            guard var deck = await siteFile(id), let cards = deck["cards"] as? [[String: Any]],
                  cards.count == row.cards else { return nil }
            if let knownIds {
                guard cards.filter({ knownIds.contains($0["id"] as? String ?? "") }).count == row.known else { return nil }
            }
            let all = row.known >= row.cards && row.cards > 0
            deck["own"] = false
            deck["cards"] = cards.map { card -> [String: Any] in
                var card = card
                card["deck"] = id
                if (card["forms"] as? [Any])?.isEmpty != false { card.removeValue(forKey: "forms") }
                let sentence = card["sentence"] as? [String: Any]
                if (sentence?["et"] as? String ?? "").isEmpty || (sentence?["en"] as? String ?? "").isEmpty {
                    card.removeValue(forKey: "sentence")
                }
                let known = all || knownIds?.contains(card["id"] as? String ?? "") == true
                card["known"] = known
                card["due"] = !known
                return card
            }
            made = ["deck": deck]
        } else if let row = lessons.first(where: { $0.id == id }) {
            guard var lesson = await siteFile(id), lesson["body"] != nil else { return nil }
            lesson["read"] = row.read ?? false
            made = ["lesson": lesson]
        } else if let row = songs.first(where: { $0.id == id }) {
            guard let written = await siteFile(id), written["verses"] != nil,
                  var song = await pointed(written) else { return nil }
            song["heard"] = row.heard ?? false
            made = ["song": song]
        } else if let row = talks.first(where: { $0.id == id }) {
            guard let written = await siteFile(id), written["scenes"] != nil,
                  var talk = await pointed(written) else { return nil }
            talk["read"] = row.read ?? false
            made = ["talk": talk]
        } else {
            return nil
        }

        guard let data = try? JSONSerialization.data(withJSONObject: made),
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return nil }
        Disk.write(data, file)
        return answer
    }

    /// A song or a conversation with every deck it points at named: its own
    /// deck of words, and the deck each of its words is taught in.
    private func pointed(_ one: [String: Any]) async -> [String: Any]? {
        var words = one["words"] as? [String: [String: Any]] ?? [:]
        var ids = Set(words.values.compactMap { $0["deck"] as? String })
        if let its = one["deck"] as? String { ids.insert(its) }
        guard let titles = await names(of: ids) else { return nil }
        for key in words.keys {
            if let deck = named(words[key]?["deck"], titles) {
                words[key]?["deck"] = deck
            } else {
                words[key]?.removeValue(forKey: "deck")
            }
        }
        var next = one
        next["words"] = words
        if let deck = named(one["deck"], titles) { next["deck"] = deck } else { next.removeValue(forKey: "deck") }
        return next
    }

    /// Marks a card in the phone's copy of its deck the way the site will
    /// once it has the answer: known and not due, or the other way round —
    /// `stateOfRow()` in the route. Every card of the deck, and none known,
    /// where no card is named, which is Forget what I know.
    private func mark(deck: String, card: String?, knew: Bool) {
        Disk.edit("one-\(deck)-\(lang).json") { answer in
            guard var one = answer["deck"] as? [String: Any],
                  var cards = one["cards"] as? [[String: Any]] else { return }
            for at in cards.indices where card == nil || cards[at]["id"] as? String == card {
                cards[at]["known"] = knew
                cards[at]["due"] = !knew
            }
            one["cards"] = cards
            answer["deck"] = one
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
    /// does not wait: a card that hung on the network each time would be
    /// unusable. Signed in it is written down first (`unsent` below) and
    /// crossed off when the site has it, so an answer given in a tunnel, or
    /// on a day the site is refusing, goes out later instead of being lost.
    /// Signed out it is written down on the phone until there is an account.
    func answer(deck: String, card: String, knew: Bool) {
        noteDay()
        if !been { been = true }
        guard signedIn, ready else {
            var all = kept
            let key = "\(deck)/\(card)"
            if all[key] == nil && all.count >= Self.maxKept { return }
            all[key] = knew
            kept = all
            return
        }
        hold(deck: deck, card: card, knew: knew)
        mark(deck: deck, card: card, knew: knew)
        Task { await send() }
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
        hold(deck: shelf, card: id, knew: true)
        await send()
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
    /// it in: moved to the answers waiting to be sent, which keeps each one
    /// until the site has taken it.
    func sendKept() async {
        let all = kept
        guard signedIn, !all.isEmpty else { return }
        for (key, knew) in all {
            guard let slash = key.firstIndex(of: "/") else { continue }
            hold(deck: String(key[..<slash]), card: String(key[key.index(after: slash)...]), knew: knew)
        }
        kept = [:]
        await send()
    }

    /// Start a deck again: forget what is known of it, and what was still
    /// waiting to be sent of it, which would otherwise come back afterwards.
    func reset(_ deck: String) async throws {
        try await API.post("api/flashcard", ["action": "reset", "deck": deck])
        unsent.removeAll { $0.user == user && $0.deck == deck }
        mark(deck: deck, card: nil, knew: false)
    }

    // MARK: Answers not yet sent

    /// An answer the site has not taken yet, and whose it is: the phone may
    /// be signed in as somebody else by the time it can be sent.
    private struct Unsent: Codable, Equatable {
        let user: String
        let deck: String
        let card: String
        let knew: Bool
        let day: String
    }

    private static let unsentKey = "unsent"
    /// More than anybody answers in a day off the network; past it the
    /// oldest goes.
    private static let maxUnsent = 500

    /// The answers waiting, oldest first, kept in UserDefaults so that they
    /// outlive the app being closed.
    private var unsent: [Unsent] {
        get {
            UserDefaults.standard.data(forKey: Self.unsentKey)
                .flatMap { try? JSONDecoder().decode([Unsent].self, from: $0) } ?? []
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: Self.unsentKey)
            } else if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.unsentKey)
            }
        }
    }

    /// The one send that is going, so that two never send the same answer.
    private var sending: Task<Void, Never>?

    /// Writes an answer down to be sent. A card answered again before its
    /// first answer went out replaces it: the last word on a card is the one
    /// the site should have.
    private func hold(deck: String, card: String, knew: Bool) {
        guard let user else { return }
        var all = unsent.filter { !($0.user == user && $0.deck == deck && $0.card == card) }
        all.append(Unsent(user: user, deck: deck, card: card, knew: knew, day: Self.today()))
        if all.count > Self.maxUnsent { all.removeFirst(all.count - Self.maxUnsent) }
        unsent = all
    }

    /// Sends what is waiting, one at a time and in the order it was answered.
    /// Called by every answer, by every shelf that arrives — a launch, coming
    /// back to the app, the end of a run — and on signing in. It answers when
    /// the queue is empty or the site has stopped taking answers.
    func send() async {
        if let sending {
            await sending.value
            return
        }
        let task = Task { await self.drain() }
        sending = task
        await task.value
    }

    /// It stops at the first answer the site does not take, and does not try
    /// again by itself: the next answer or the next shelf does. So a site
    /// that is down is asked no more often than it was before there was a
    /// queue, once an answer.
    ///
    /// What the site said decides what becomes of the answer:
    /// - taken: crossed off;
    /// - the network failed, so the site said nothing: kept where it is;
    /// - 5xx, 429, 408 or 401 — the site is down, out of its day's
    ///   allowance, or no longer knows the session: kept, and moved to the
    ///   back, so that one answer the site chokes on does not hold up the
    ///   rest for ever;
    /// - any other refusal — a card that is no longer in its deck, a deck
    ///   that was deleted: dropped, since asking again will not change it.
    ///
    /// An answer sent twice, because the site took it and the phone never
    /// heard, does no harm: the site's totals count a card once however
    /// often it is answered the same way.
    private func drain() async {
        defer { sending = nil }
        while signedIn, ready, let next = unsent.first(where: { $0.user == user }) {
            do {
                try await API.post("api/flashcard", [
                    "action": next.knew ? "knew" : "again",
                    "deck": next.deck,
                    "card": next.card,
                    "day": next.day
                ])
                cross(next)
            } catch let refusal as API.Refusal {
                let later = refusal.status >= 500 || [401, 408, 429].contains(refusal.status)
                let waiting = unsent.contains(next)
                cross(next)
                if later {
                    if waiting { unsent.append(next) }
                    return
                }
            } catch {
                return
            }
        }
    }

    private func cross(_ one: Unsent) {
        var all = unsent
        if let at = all.firstIndex(of: one) {
            all.remove(at: at)
            unsent = all
        }
    }

    /// What was waiting is thrown away with the rest of what the phone held
    /// of somebody, when they sign out or delete the account.
    func forgetUnsent() {
        unsent = []
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

    // MARK: New, and where somebody left off

    /// Added in the last fourteen days: `NEW_DAYS` on the website.
    static func fresh(_ added: String?) -> Bool {
        guard let added, let day = ISO8601DateFormatter().date(from: added + "T12:00:00Z") else { return false }
        return Date().timeIntervalSince(day) < 14 * 86400
    }

    /// What this phone last had open — a deck, a lesson, a song or a
    /// conversation — as `deck:food`, `song:naera-naera`. The phone's and not
    /// the account's, the way the website keeps `ttb.flash.last` in the
    /// browser: a phone closed on one deck and a laptop closed on another
    /// were closed in two places.
    var last: Route? {
        get {
            _ = stamp
            guard let said = UserDefaults.standard.string(forKey: "last") else { return nil }
            let bits = said.split(separator: ":", maxSplits: 1).map(String.init)
            guard bits.count == 2 else { return .deck(said) }
            switch bits[0] {
            case "lesson": return .lesson(bits[1])
            case "song": return .song(bits[1])
            case "talk": return .talk(bits[1])
            default: return .deck(bits[1])
            }
        }
        set {
            let said: String? = newValue.map {
                switch $0 {
                case .deck(let id): return "deck:" + id
                case .lesson(let id): return "lesson:" + id
                case .song(let id): return "song:" + id
                case .talk(let id): return "talk:" + id
                }
            }
            UserDefaults.standard.set(said, forKey: "last")
            stamp += 1
        }
    }

    /// Whether this phone has answered a card here before. Until it has, the
    /// Words tab opens on the first card of Hello and goodbye rather than on
    /// a shelf of forty decks: the website's front door, `ttb.flash.been`.
    var been: Bool {
        get { _ = stamp; return UserDefaults.standard.bool(forKey: "been") }
        set { UserDefaults.standard.set(newValue, forKey: "been"); stamp += 1 }
    }

    /// The line the shelf opens with for somebody coming back: how long
    /// they have been away, or how many days they have run. `helloLine()` on
    /// the website, which adds how many words are known; the shelf prints
    /// that on a line of its own under this one.
    var hello: String {
        let days = signedIn ? self.days : localDays
        var said: [String] = []
        if let days {
            let gap = Self.daysBetween(days.last, Self.today())
            if gap > 1 {
                said.append(t("flashHelloAway", "Welcome back. You’ve been away {n} days.", ["n": "\(gap)"]))
            } else if days.run > 1 {
                said.append(t("flashHelloRun", "Welcome back — {n} days in a row.", ["n": "\(days.run)"]))
            } else {
                said.append(t("flashHelloBack", "Welcome back."))
            }
        }
        return said.joined(separator: " ")
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
