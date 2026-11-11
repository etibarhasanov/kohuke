import SwiftUI

// The four shelves, one to a tab: the words, the grammar, the songs and the
// conversations. They are the four parts of the website's page — `wordsPart()`,
// `grammarPart()`, `songsPart()` and `talksPart()` in `assets/flashcard.js` —
// and each lists what the one answer of `/api/flashcard` gave the store.

/// The decks, under the site's four headings.
///
/// First words and At a restaurant are always open. Getting by opens at a
/// hundred words known and Going deeper at four hundred, and a stage that
/// has not opened is its heading and one line saying how far off it is: the
/// decks behind it are not in the answer at all. Above the headings stand
/// Start, which goes back to the deck in hand, and the two gathered decks —
/// what was missed and what is known — where there is anything in them.
/// Below them, the decks somebody wrote themselves.
struct WordsTab: View {
    fileprivate static let levels = [
        ("start", "flashLevelStart", "First words"),
        ("eat", "flashLevelEat", "At a restaurant"),
        ("more", "flashLevelMore", "Getting by"),
        ("deep", "flashLevelDeep", "Going deeper")
    ]

    var body: some View {
        Shelf(tab: 0, title: "Kohuke") {
            WordsShelf()
        }
    }

    /// The page itself, inside the stack, where it can push.
    private struct WordsShelf: View {
        @Environment(Store.self) private var store
        @Environment(\.push) private var push
        @State private var newName = ""
        @State private var problem: String?
        @State private var signingIn = false

        var body: some View {
            let shipped = store.decks.filter { $0.own != true && !$0.gathered }
            let gathered = store.decks.filter(\.gathered)
            let own = store.decks.filter { $0.own == true }

            VStack(alignment: .leading, spacing: 2) {
                Text(store.t("flashTitle", "Estonian, one card at a time"))
                    .foregroundStyle(Theme.muted)
                Text(store.t("flashLearned", "You know {n} Estonian words.", ["n": "\(store.words)"]))
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.ink)
                if store.daysRunning > 0 {
                    Text(store.t("flashDaysRun", "{n} days in a row.", ["n": "\(store.daysRunning)"]))
                        .foregroundStyle(Theme.muted)
                }
            }

            if !store.ready {
                Text(store.t("flashErrOff", "Nothing is being remembered on this copy of the site, so the decks below will not keep your place."))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }

            if let next = next(shipped) {
                NavigationLink(value: Route.deck(next.id)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.t("flashPartStart", "Start")).font(.headline)
                            Text("\(store.means(next.name)) · \(next.known) / \(next.cards)")
                                .font(.footnote)
                                .opacity(0.85)
                        }
                        Spacer()
                        Image(systemName: "arrow.right").font(.title3.weight(.semibold))
                    }
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            } else if !store.loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if shipped.isEmpty {
                Text(store.offline
                     ? store.t("appOffline", "Couldn’t reach tallinntastebuds.ee.")
                     : store.t("flashNoneShipped", "No decks here yet."))
                    .foregroundStyle(Theme.muted)
            }

            if !gathered.isEmpty {
                Rows { ForEach(gathered) { DeckShelfRow(deck: $0) } }
            }

            ForEach(WordsTab.levels, id: \.0) { level, key, english in
                let these = shipped.filter { $0.level == level }
                let gate = store.gate(level)
                if !these.isEmpty || gate > 0 {
                    Heading(text: store.t(key, english))
                    if gate > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: Double(min(store.words, gate)), total: Double(gate))
                                .tint(Theme.accent)
                            Text(store.t("flashOpens", "Opens at {n} words — {left} to go",
                                         ["n": "\(gate)", "left": "\(gate - store.words)"]))
                                .font(.footnote.monospaced())
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    if !these.isEmpty {
                        Rows { ForEach(these) { DeckShelfRow(deck: $0) } }
                    }
                }
            }

            Heading(text: store.t("flashYours", "Words you collected"))
            if store.signedIn {
                if own.isEmpty {
                    Text(store.t("flashYoursNone", "No decks of your own yet. Name one and start putting words in it."))
                        .foregroundStyle(Theme.muted)
                } else {
                    Rows { ForEach(own) { DeckShelfRow(deck: $0) } }
                }
                HStack(spacing: 10) {
                    TextField(store.t("flashNewDeck", "A new deck"), text: $newName,
                              prompt: Text(store.t("flashNewDeckHint", "Words from the market")))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: newName) { _, now in newName = String(now.prefix(60)) }
                        .onSubmit { Task { await make() } }
                    Button(store.t("flashMakeDeck", "Make the deck")) { Task { await make() } }
                        .buttonStyle(.prominent)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(Theme.again)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.t("flashKeepTitle", "Remember where you got to"))
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(store.t("appKeepWhy", "An account remembers which cards you know, on every phone and on tallinntastebuds.ee, and lets you write decks of your own."))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    Button { signingIn = true } label: {
                        Text(store.t("accountSignIn", "Sign in")).fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.prominent)
                    .controlSize(.large)
                }
                .card()
                .sheet(isPresented: $signingIn) { SignInView() }
            }
        }

        /// The deck Start goes to: the one last opened while it still has
        /// cards to learn, and otherwise the first on the shelf that has.
        private func next(_ shipped: [DeckRow]) -> DeckRow? {
            let unfinished = shipped.filter { $0.known < $0.cards }
            let last = UserDefaults.standard.string(forKey: "last")
            return unfinished.first { $0.id == last } ?? unfinished.first ?? shipped.first
        }

        private func make() async {
            let name = newName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            do {
                let deck = try await store.write(["action": "deck", "name": name])
                newName = ""
                problem = nil
                await store.refresh()
                if let deck { push(.deck(deck.id)) }
            } catch {
                problem = store.say(error)
            }
        }
    }
}

/// The lessons, each followed by its deck where it has one, and the cases
/// under a heading of their own.
struct GrammarTab: View {
    @Environment(Store.self) private var store

    var body: some View {
        Shelf(tab: 1, title: store.t("flashGrammar", "Grammar")) {
            let grammar = store.lessons.filter { !$0.underCases }
            let cases = store.lessons.filter(\.underCases)
            Text(store.t("flashGrammarSay", "Short lessons on why the words change, and the fourteen cases one at a time."))
                .foregroundStyle(Theme.muted)
            if store.lessons.isEmpty {
                BareShelf()
            }
            if !grammar.isEmpty { steps(grammar) }
            if !cases.isEmpty {
                Heading(text: store.t("flashCases", "The cases, one by one"))
                steps(cases)
            }
        }
    }

    private func steps(_ lessons: [Lesson]) -> some View {
        Rows {
            ForEach(lessons) { lesson in
                let read = store.done(Store.grammarDeck, lesson.id, lesson.read)
                ShelfRow(route: .lesson(lesson.id),
                         title: store.means(lesson.name),
                         subtitle: store.means(lesson.why),
                         figure: read ? store.t("flashRead", "Read") : "",
                         done: read)
                if let deck = store.decks.first(where: { $0.id == lesson.deck }) {
                    DeckShelfRow(deck: deck, follows: true)
                }
            }
        }
    }
}

/// The songs, each followed by the deck of its own words.
struct SongsTab: View {
    @Environment(Store.self) private var store

    var body: some View {
        Shelf(tab: 2, title: store.t("flashSongs", "Songs")) {
            Text(store.t("flashSongHow", "Listen once, then again with the words. Tap any word for what it means."))
                .foregroundStyle(Theme.muted)
            if store.songs.isEmpty {
                BareShelf()
            } else {
                Rows {
                    ForEach(store.songs) { song in
                        let heard = store.done(Store.songDeck, song.id, song.heard)
                        ShelfRow(route: .song(song.id),
                                 title: store.means(song.name),
                                 subtitle: store.means(song.why),
                                 figure: heard ? store.t("flashHeard", "Heard") : "",
                                 done: heard)
                        // A song's deck shares the first word of its id:
                        // naera-naera and naera-words.
                        ForEach(store.decks.filter { $0.level == "song" && first($0.id) == first(song.id) }) {
                            DeckShelfRow(deck: $0, follows: true)
                        }
                    }
                }
            }
        }
    }

    private func first(_ id: String) -> Substring { id.prefix { $0 != "-" } }
}

/// The conversations.
struct TalksTab: View {
    @Environment(Store.self) private var store

    var body: some View {
        Shelf(tab: 3, title: store.t("flashTalks", "Conversations")) {
            Text(store.t("flashTalksSay", "Everyday questions, a dinner out and a trip to the shops, in Estonian, with every sentence translated and every word explained."))
                .foregroundStyle(Theme.muted)
            if store.talks.isEmpty {
                BareShelf()
            } else {
                Rows {
                    ForEach(store.talks) { talk in
                        let read = store.done(Store.talkDeck, talk.id, talk.read)
                        ShelfRow(route: .talk(talk.id),
                                 title: store.means(talk.name),
                                 subtitle: store.means(talk.why),
                                 figure: read ? store.t("flashRead", "Read") : "",
                                 done: read)
                    }
                }
            }
        }
    }
}

/// A shelf with nothing on it: still loading, off the network, or bare.
private struct BareShelf: View {
    @Environment(Store.self) private var store

    var body: some View {
        if !store.loaded {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
        } else {
            Text(store.offline
                 ? store.t("appOffline", "Couldn’t reach tallinntastebuds.ee.")
                 : store.t("flashNoneShipped", "No decks here yet."))
                .foregroundStyle(Theme.muted)
        }
    }
}
