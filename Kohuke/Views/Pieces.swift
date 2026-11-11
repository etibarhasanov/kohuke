import SwiftUI

/// A screen that can be pushed onto a tab's stack. All four open at the same
/// kind of address on the website — `?deck=<id>` — and from the same route.
enum Route: Hashable {
    case deck(String)
    case lesson(String)
    case song(String)
    case talk(String)
}

/// Pushes a screen onto the tab's stack from anywhere inside it, for the
/// buttons that do something first and go somewhere after: Make the deck,
/// Got it — on to the cards.
private struct PushKey: EnvironmentKey {
    static let defaultValue: (Route) -> Void = { _ in }
}

extension EnvironmentValues {
    var push: (Route) -> Void {
        get { self[PushKey.self] }
        set { self[PushKey.self] = newValue }
    }
}

/// One tab: a titled, scrolling page on the paper, with a stack of its own
/// that the four kinds of screen are pushed onto.
struct Shelf<Content: View>: View {
    @Environment(Store.self) private var store
    let title: String
    @State private var path: [Route]
    @ViewBuilder let content: () -> Content

    init(tab: Int, title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
        _path = State(initialValue: LaunchScript.routes(tab: tab))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.offline {
                        Text(store.t("appOfflineNote", "Offline. This is what the phone saw last."))
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    content()
                }
                .padding(16)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle(title)
            .refreshable { await store.refresh() }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .deck(let id): RunView(id: id)
                case .lesson(let id): LessonView(id: id)
                case .song(let id): SongView(id: id)
                case .talk(let id): TalkView(id: id)
                }
            }
        }
        .environment(\.push) { path.append($0) }
    }
}

/// A pushed page: the same paper and the same measure as a tab's.
struct Page<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(16)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A heading over a group of rows, the size the website's shelf uses.
struct Heading: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.title3.weight(.bold))
            .foregroundStyle(Theme.ink)
            .padding(.top, 6)
    }
}

/// A group of rows as one card. Each row draws the hairline under itself,
/// and the last one's lies under the card's own edge.
struct Rows<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hairline))
    }
}

/// One row of a shelf: what it is, the line under it, and where it stands.
struct ShelfRow: View {
    let route: Route
    let title: String
    var subtitle: String = ""
    var figure: String = ""
    var done = false
    /// A row that follows the one above it: a lesson's deck, a song's words.
    var follows = false

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 10) {
                if follows {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if !figure.isEmpty {
                    Text(figure)
                        .font(.footnote.monospaced().weight(.medium))
                        .foregroundStyle(done ? Theme.knew : Theme.muted)
                        .fixedSize()
                }
                if done {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.knew)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

/// A deck's row, which reads the same on every shelf it stands on.
struct DeckShelfRow: View {
    @Environment(Store.self) private var store
    let deck: DeckRow
    var follows = false

    var body: some View {
        ShelfRow(route: .deck(deck.id),
                 title: name,
                 subtitle: why,
                 figure: deck.cards > 0 ? "\(deck.known) / \(deck.cards)" : "",
                 done: deck.cards > 0 && deck.known >= deck.cards,
                 follows: follows)
    }

    private var name: String {
        if deck.missed == true { return store.t("flashMissedName", "Words you missed") }
        if deck.review == true { return store.t("flashReviewName", "Words you know") }
        return store.means(deck.name)
    }

    private var why: String {
        if deck.missed == true { return store.t("flashMissedWhy", "Everything you pressed Show me again on, from every deck") }
        if deck.review == true { return store.t("flashReviewWhy", "Everything you have got right, from every deck, to go through whenever you like") }
        return store.means(deck.why)
    }
}

/// The speaker: press to hear the Estonian, press again to stop it.
struct Speaker: View {
    let text: String
    var label: String = ""

    var body: some View {
        let now = Voice.shared.saying(text)
        Button {
            Voice.shared.say(text)
        } label: {
            HStack(spacing: 6) {
                Group {
                    if now == .loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: now == .playing ? "speaker.wave.2.fill" : "speaker.wave.2")
                    }
                }
                .frame(width: 22, height: 22)
                if !label.isEmpty { Text(label).fontWeight(.semibold) }
            }
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
    }
}

/// A line of Estonian in which every word can be pressed for what it means,
/// with what the whole line means under it: a line of a song, a turn of a
/// conversation.
///
/// The words are links inside one piece of text rather than a row of
/// buttons, so the line wraps as a sentence does. `WORD` is the website's:
/// a run of Latin letters, which takes in õ, ä, ö, ü, š and ž.
struct GlossLine: View {
    @Environment(Store.self) private var store
    let line: Said
    let words: [String: Gloss]?
    /// The deck of the song's own words, which a gloss names differently.
    var home: DeckRef?
    var bold = false

    @State private var open: String?

    private static let word = try! NSRegularExpression(pattern: "[A-Za-z\\u00C0-\\u024F]+")

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(pressable)
                    .font(bold ? .title3.weight(.semibold) : .title3)
                    .tint(Theme.ink)
                    .environment(\.openURL, OpenURLAction { url in
                        let key = url.lastPathComponent
                        open = open == key ? nil : key
                        return .handled
                    })
                Spacer(minLength: 0)
                Speaker(text: line.et)
            }
            Text(store.means(line))
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            if let key = open, let gloss = words?[key] {
                box(key, gloss)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if let asked = LaunchScript.word, words?[asked] != nil, line.et.lowercased().contains(asked) { open = asked }
        }
    }

    /// The line with each word the answer explains made pressable. The word
    /// that is open is underlined.
    private var pressable: AttributedString {
        let et = line.et as NSString
        var out = AttributedString()
        var at = 0
        for found in Self.word.matches(in: line.et, range: NSRange(location: 0, length: et.length)) {
            if found.range.location > at {
                out += AttributedString(et.substring(with: NSRange(location: at, length: found.range.location - at)))
            }
            let text = et.substring(with: found.range)
            let key = text.lowercased()
            var piece = AttributedString(text)
            if words?[key] != nil, let link = URL(string: "kohuke://word/" + (key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")) {
                piece.link = link
                if open == key {
                    piece.underlineStyle = .single
                    piece.foregroundColor = Theme.accent
                }
            }
            out += piece
            at = found.range.location + found.range.length
        }
        if at < et.length { out += AttributedString(et.substring(from: at)) }
        return out
    }

    private func box(_ key: String, _ gloss: Gloss) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(Text(key).fontWeight(.bold)) — \(store.means(gloss.means))")
                .foregroundStyle(Theme.ink)
            if let base = gloss.base, base.lowercased() != key {
                Text(base).font(.footnote.monospaced()).foregroundStyle(Theme.muted)
            }
            if let note = gloss.note {
                Text(store.means(note)).font(.footnote).foregroundStyle(Theme.ink)
            }
            if let deck = gloss.deck {
                Text(deck.id == home?.id
                     ? store.t("flashInSongDeck", "In the song's deck")
                     : store.t("flashAlsoIn", "Also in {deck}", ["deck": store.means(deck.name)]))
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// What a pushed screen shows while it waits, and when there is nothing by
/// that name.
struct Waiting: View {
    @Environment(Store.self) private var store
    let missing: Bool

    var body: some View {
        Group {
            if missing {
                EmptyNote(title: store.t("flashGoneTitle", "Nothing by that name"),
                          text: store.offline
                              ? store.t("appOffline", "Couldn’t reach tallinntastebuds.ee.")
                              : store.t("flashErrGone", "There is no deck or lesson by that name."),
                          systemImage: "questionmark.folder")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
    }
}

/// The button a lesson, a song and a conversation end on: Got it, Heard it,
/// Read it. Pressed, it says so and stays said.
struct FinishButton: View {
    let title: String
    let doneTitle: String
    let done: Bool
    let action: () async -> Void
    @State private var working = false

    var body: some View {
        if done {
            Label(doneTitle, systemImage: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.knew)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        } else {
            Button {
                working = true
                Task {
                    await action()
                    working = false
                }
            } label: {
                Text(title).fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.prominent)
            .controlSize(.large)
            .disabled(working)
        }
    }
}
