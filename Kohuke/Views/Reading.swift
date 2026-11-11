import SwiftUI
import WebKit

// The three things on the shelves that are not turned over: a lesson, which
// is read; a song, which is listened to; and a conversation, which is
// followed. Each is one answer of `/api/flashcard?deck=<id>`, whole, and
// each ends on one button that files it as done — the same `knew` a card
// gets, under `grammar`, `songs` or `talks`.

/// A grammar lesson: prose, headings, tables of forms and example sentences.
///
/// Estonian inside the prose comes between asterisks in the site's file and
/// is drawn in italics. Every form in a table is a button that says it, and
/// every example has a speaker. A lesson that has a deck of its own ends on
/// Got it — on to the cards, which opens that deck.
struct LessonView: View {
    @Environment(Store.self) private var store
    @Environment(\.push) private var push
    let id: String

    @State private var lesson: Lesson?
    @State private var missing = false

    var body: some View {
        Group {
            if let lesson {
                Page {
                    Text(store.means(lesson.name)).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                    ForEach(Array((lesson.body ?? []).enumerated()), id: \.offset) { _, block in
                        piece(block)
                    }
                    let read = store.done(Store.grammarDeck, lesson.id, lesson.read)
                    if let deck = lesson.deck {
                        Button {
                            Task { await store.finish(Store.grammarDeck, lesson.id) }
                            push(.deck(deck))
                        } label: {
                            Text(store.t("flashToCards", "Got it — on to the cards"))
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.prominent)
                        .controlSize(.large)
                    } else {
                        FinishButton(title: store.t("flashGotIt", "Got it"),
                                     doneTitle: store.t("flashRead", "Read"),
                                     done: read) {
                            await store.finish(Store.grammarDeck, lesson.id)
                        }
                    }
                }
            } else {
                Waiting(missing: missing)
            }
        }
        .navigationTitle(store.t(lesson?.underCases == true ? "flashCases" : "flashGrammar",
                                 lesson?.underCases == true ? "The cases, one by one" : "Grammar"))
        .task {
            guard lesson == nil else { return }
            lesson = await store.open(id)?.lesson
            missing = lesson == nil
        }
        .onDisappear { Voice.shared.hush() }
    }

    @ViewBuilder
    private func piece(_ block: Block) -> some View {
        if let say = block.say {
            Text(prose(store.means(say))).foregroundStyle(Theme.ink)
        } else if let head = block.head {
            Heading(text: store.means(head))
        } else if let table = block.table {
            paradigm(table)
        } else if let examples = block.examples {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(examples.enumerated()), id: \.offset) { _, one in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(one.et).fontWeight(.semibold).foregroundStyle(Theme.ink)
                            Spacer(minLength: 8)
                            Speaker(text: one.et)
                        }
                        Text(store.means(one)).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }
            }
            .card()
        }
    }

    /// The Estonian between asterisks, in italics: `prose()` on the website.
    private func prose(_ text: String) -> AttributedString {
        var out = AttributedString()
        for (i, part) in text.components(separatedBy: "*").enumerated() {
            var piece = AttributedString(part)
            if i % 2 == 1 {
                piece.font = .body.italic().weight(.medium)
                piece.foregroundColor = Theme.accent
            }
            out += piece
        }
        return out
    }

    /// A table of forms. It scrolls sideways when the forms are long, and a
    /// form given two ways (`leiba · leibu`) is said with a pause between.
    private func paradigm(_ table: Paradigm) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    ForEach(Array(table.heads.enumerated()), id: \.offset) { _, head in
                        Text(store.means(head)).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.et.enumerated()), id: \.offset) { _, form in
                            let said = form.replacingOccurrences(of: " · ", with: ", ")
                            Button { Voice.shared.say(said) } label: {
                                Text(form)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Voice.shared.saying(said) == .quiet ? Theme.ink : Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(store.means(row.means)).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hairline))
    }
}

/// A song: the recording, then every line with what it means, and every
/// word in it pressable.
struct SongView: View {
    @Environment(Store.self) private var store
    let id: String

    @State private var song: Song?
    @State private var missing = false

    var body: some View {
        Group {
            if let song {
                Page {
                    Text(store.means(song.name)).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                    if let video = song.video {
                        Video(id: video)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                    }
                    if let credit = song.credit {
                        VStack(alignment: .leading, spacing: 2) {
                            if let who = credit.words {
                                Text(store.t("flashSongWordsBy", "Words: {who}", ["who": who]))
                            }
                            if let who = credit.music {
                                Text(store.t("flashSongMusicBy", "Music: {who}", ["who": who]))
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    }
                    Text(store.t("flashSongHow", "Listen once, then again with the words. Tap any word for what it means."))
                        .foregroundStyle(Theme.muted)

                    ForEach(Array((song.verses ?? []).enumerated()), id: \.offset) { n, verse in
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: store.t("flashVerse", "Verse {n}", ["n": "\(n + 1)"]))
                            ForEach(Array(verse.enumerated()), id: \.offset) { _, line in
                                GlossLine(line: line, words: song.words, home: song.deck)
                            }
                        }
                        .card()
                    }

                    if let deck = song.deck {
                        NavigationLink(value: Route.deck(deck.id)) {
                            Label(store.t("flashSongCards", "The words, as cards"), systemImage: "rectangle.on.rectangle")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.wash, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    FinishButton(title: store.t("flashHeardIt", "Heard it"),
                                 doneTitle: store.t("flashHeard", "Heard"),
                                 done: store.done(Store.songDeck, song.id, song.heard)) {
                        await store.finish(Store.songDeck, song.id)
                    }
                }
            } else {
                Waiting(missing: missing)
            }
        }
        .navigationTitle(store.t("flashSongs", "Songs"))
        .task {
            guard song == nil else { return }
            song = await store.open(id)?.song
            missing = song == nil
        }
        .onDisappear { Voice.shared.hush() }
    }
}

/// A conversation: a question, and the turns that answer it, a sentence at
/// a time with what each means under it.
struct TalkView: View {
    @Environment(Store.self) private var store
    let id: String

    @State private var talk: Talk?
    @State private var missing = false

    var body: some View {
        Group {
            if let talk {
                Page {
                    Text(store.means(talk.name)).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                    Text(store.t("appTalkHow", "Read it in Estonian, a sentence at a time, with what each means under it. Tap any word for what it means, and the speaker to hear the sentence."))
                        .foregroundStyle(Theme.muted)
                    if let source = talk.source {
                        Text(store.t("flashTalkFrom", "From {who}, a B1 course", ["who": source]))
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }

                    ForEach(Array((talk.scenes ?? []).enumerated()), id: \.offset) { _, scene in
                        VStack(alignment: .leading, spacing: 14) {
                            if let ask = scene.ask {
                                GlossLine(line: ask, words: talk.words, bold: true)
                            }
                            ForEach(Array((scene.turns ?? []).enumerated()), id: \.offset) { _, turn in
                                VStack(alignment: .leading, spacing: 10) {
                                    if let who = turn.who { SectionLabel(text: who) }
                                    ForEach(Array((turn.lines ?? []).enumerated()), id: \.offset) { _, line in
                                        GlossLine(line: line, words: talk.words)
                                    }
                                }
                            }
                        }
                        .card()
                    }

                    FinishButton(title: store.t("flashReadIt", "Read it"),
                                 doneTitle: store.t("flashRead", "Read"),
                                 done: store.done(Store.talkDeck, talk.id, talk.read)) {
                        await store.finish(Store.talkDeck, talk.id)
                    }
                }
            } else {
                Waiting(missing: missing)
            }
        }
        .navigationTitle(store.t("flashTalks", "Conversations"))
        .task {
            guard talk == nil else { return }
            talk = await store.open(id)?.talk
            missing = talk == nil
        }
        .onDisappear { Voice.shared.hush() }
    }
}

/// The recording of a song, from YouTube, in the player YouTube gives a page
/// to embed: the same `youtube-nocookie.com` frame the website draws.
///
/// The frame is loaded as a page of tallinntastebuds.ee so that YouTube is
/// told who is embedding it, which it asks of every embed and refuses to
/// play without.
private struct Video: UIViewRepresentable {
    let id: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard context.coordinator.loaded != safe else { return }
        context.coordinator.loaded = safe
        let page = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style>
        <iframe src="https://www.youtube-nocookie.com/embed/\(safe)?rel=0&playsinline=1"
          allow="encrypted-media; picture-in-picture; fullscreen" allowfullscreen
          referrerpolicy="strict-origin-when-cross-origin"></iframe>
        """
        view.loadHTMLString(page, baseURL: API.base)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loaded = ""
    }
}
