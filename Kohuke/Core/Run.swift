import Foundation
import Observation

/// One sitting with one deck: the cards still to come, which is up, and what
/// has been said about the ones gone by.
///
/// It is `startRun()`, `mark()`, `flush()` and `undo()` in the website's
/// `assets/flashcard.js`, kept to the same rules so a deck runs the same on
/// the phone as on the page:
///
/// - A deck the site ships keeps its own order, because that order is a
///   progression somebody wrote on purpose. A deck of your own sorts by card
///   id, minted at random, so the word you added last is not always last.
/// - The cards not yet known come first, then the known ones.
/// - A card got wrong comes round once more at the end of the same run.
/// - An answer is written when the next one is given rather than when it is
///   pressed, so the last answer can be taken back with nothing to unsend.
@MainActor
@Observable
final class Run {
    private(set) var deck: Deck
    private(set) var queue: [Card] = []
    private(set) var at = 0
    var turned = false
    var hint = false
    private(set) var knew = 0
    private(set) var again = 0
    /// Up once the phone has answered its free words signed out.
    var gated = false
    /// How many words were known when the run began, to say at the end
    /// which stage it opened.
    let wordsAtStart: Int

    private var back: Set<String> = []
    private var said: [String: Bool] = [:]
    private var pending: (deck: String, card: String, knew: Bool)?
    private var last: Undo?

    private struct Undo {
        let card: Card
        let knew: Bool
        let wasKnown: Bool
        let at: Int
        let turned: Bool
        let hint: Bool
        let length: Int
        let hadBack: Bool
        let said: Bool?
        let tallyKnew: Int
        let tallyAgain: Int
    }

    init(deck: Deck, words: Int) {
        self.deck = deck
        wordsAtStart = words
        start(all: false)
    }

    /// Lays the run out. `all` goes through every card, due or not, which is
    /// Go through it again and Go through it anyway.
    func start(all: Bool) {
        var cards = deck.cards
        if deck.own == true { cards.sort { $0.id < $1.id } }
        // `due != false`, not `due == true`: a card that arrives without the
        // field is due. A card wrongly called due is asked twice; one wrongly
        // called resting silently leaves the deck.
        let due = cards.filter { all || $0.due != false }
        queue = due.filter { $0.known != true } + due.filter { $0.known == true }
        at = 0
        turned = false
        hint = false
        knew = 0
        again = 0
        back = []
        said = [:]
        last = nil
    }

    var current: Card? { at < queue.count ? queue[at] : nil }
    var knownCount: Int { deck.cards.filter { $0.known == true }.count }
    var canUndo: Bool { last != nil }

    /// Which deck a card is really from, which differs only in the two
    /// gathered decks: everything said about a card names where it came from.
    private func home(_ card: Card) -> String { card.deck ?? deck.id }
    private func key(_ card: Card) -> String { home(card) + "/" + card.id }

    private func setKnown(_ card: Card, _ value: Bool) {
        let mine = key(card)
        for i in deck.cards.indices where key(deck.cards[i]) == mine { deck.cards[i].known = value }
        for i in queue.indices where key(queue[i]) == mine { queue[i].known = value }
    }

    /// Knew it, and its opposite. The card in hand changes before any write
    /// goes out, and nothing waits for one.
    func mark(_ card: Card, knew: Bool, store: Store) {
        flush(store)
        let mine = key(card)
        let wasKnown = card.known == true
        last = Undo(card: card, knew: knew, wasKnown: wasKnown, at: at, turned: turned, hint: hint,
                    length: queue.count, hadBack: back.contains(mine), said: said[mine],
                    tallyKnew: self.knew, tallyAgain: again)

        // The count of words is the site's words: a deck somebody typed is
        // not in it.
        if deck.own != true && knew != wasKnown { store.nudge(words: knew ? 1 : -1) }
        setKnown(card, knew)
        pending = (home(card), card.id, knew)

        if !knew && !back.contains(mine) {
            back.insert(mine)
            queue.append(card)
        }
        if let before = said[mine] {
            if before { self.knew -= 1 } else { again -= 1 }
        }
        said[mine] = knew
        if knew { self.knew += 1 } else { again += 1 }

        at += 1
        turned = false
        hint = false

        if current != nil && store.spends(deck: home(card), card: card.id) {
            gated = true
            flush(store)
        }
    }

    /// Sends the answer that was waiting. Called by the next answer, at the
    /// end of the run and on the way out of the deck.
    func flush(_ store: Store) {
        guard let p = pending else { return }
        pending = nil
        last = nil
        store.answer(deck: p.deck, card: p.card, knew: p.knew)
    }

    /// Takes the last answer back, whole: the card, the count and the tally.
    func undo(store: Store) {
        guard let u = last else { return }
        last = nil
        pending = nil
        let mine = key(u.card)
        if deck.own != true && u.knew != u.wasKnown { store.nudge(words: u.knew ? -1 : 1) }
        queue.removeLast(max(0, queue.count - u.length))
        setKnown(u.card, u.wasKnown)
        at = u.at
        turned = u.turned
        hint = u.hint
        if u.hadBack { back.insert(mine) } else { back.remove(mine) }
        said[mine] = u.said
        knew = u.tallyKnew
        again = u.tallyAgain
        gated = false
    }

    /// After Forget what I know: nothing in the deck is known any more.
    func forgetAll() {
        for i in deck.cards.indices { deck.cards[i].known = false }
        start(all: true)
    }

    /// The deck as the editor left it, with the run laid out again.
    func replace(_ next: Deck) {
        deck = next
        start(all: false)
    }

    /// The first letters of what a card means, for the hint: `hintOf()` on
    /// the website. Short leading words — "a", "to" — are given whole, since
    /// two letters of "to eat" would be no hint at all.
    static func hint(_ meaning: String) -> String {
        var words = meaning.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return "" }
        var lead = ""
        while words.count > 1 && words[0].count <= 2 { lead += words.removeFirst() + " " }
        let first = words[0]
        var take = first.count >= 6 ? 3 : 2
        if words.count == 1 && lead.isEmpty { take = min(take, first.count / 2) }
        guard take >= 1 else { return "" }
        return lead + first.prefix(take) + "…"
    }
}
