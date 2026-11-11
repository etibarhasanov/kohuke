import SwiftUI

/// A deck, one card at a time.
///
/// The card shows the Estonian. A tap turns it over to what it means — with
/// the three forms where the word has them, how a case form is made, and the
/// word in a sentence — and then it is one of two answers: Knew it, or Show
/// me again. Either can be given by button or by pushing the card off to the
/// right or the left, on either face.
///
/// What stands in place of a card, in the order they are checked: a deck in
/// a stage that has not opened says what it opens at; a deck of your own
/// with nothing in it says so and offers the editor; a signed-out phone that
/// has answered its five words is asked for an account; a deck with nothing
/// due offers to go through it anyway; and a run that has ended shows the
/// score.
struct RunView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: String

    @State private var run: Run?
    @State private var missing = false
    @State private var editing = false
    @State private var signingIn = false
    @State private var reported: Set<String> = []
    @State private var problem: String?
    /// How far the card has been pushed sideways.
    @State private var lean: CGFloat = 0
    @State private var flying = false

    var body: some View {
        Group {
            if let run {
                Page { content(run) }
            } else {
                Waiting(missing: missing)
            }
        }
        .navigationTitle(run.map { name($0.deck) } ?? "")
        .toolbar {
            if let run, run.deck.own == true {
                ToolbarItem(placement: .primaryAction) {
                    Button(store.t("flashEdit", "Edit the words")) { editing = true }
                }
            } else if let run, run.deck.review != true && run.deck.missed != true {
                // A deck somebody wrote is theirs alone, and the two gathered
                // decks are made of one person's answers: none of the three
                // has an address anybody else could open.
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: API.link(run.deck.id, lang: store.lang))
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let run {
                DeckEditor(deck: run.deck) { changed in
                    run.replace(changed)
                } dropped: {
                    editing = false
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $signingIn) {
            SignInView(reason: store.t("flashFirstTitle", "The rest of the deck needs an account"))
        }
        .task { await load() }
        .onChange(of: store.signedIn) { _, signedIn in
            // Signed in from the gate: the five words went along, and the
            // run carries on from the card it stopped at.
            if signedIn { run?.gated = false }
        }
        .onDisappear {
            run?.flush(store)
            Voice.shared.hush()
            Task { await store.refresh() }
        }
    }

    private func load() async {
        guard run == nil else { return }
        guard let deck = await store.open(id)?.deck else {
            missing = true
            return
        }
        let made = Run(deck: deck, words: store.words)
        if LaunchScript.turned { made.turned = true }
        run = made
        store.last = .deck(id)
    }

    private func name(_ deck: Deck) -> String {
        if deck.missed == true { return store.t("flashMissedName", "Words you missed") }
        if deck.review == true { return store.t("flashReviewName", "Words you know") }
        return store.means(deck.name)
    }

    // MARK: What is on the page

    @ViewBuilder
    private func content(_ run: Run) -> some View {
        let gate = run.deck.own == true ? 0 : store.gate(run.deck.level)
        if gate > 0 {
            notice(title: store.t("flashLockedTitle", "This deck opens at {n} words", ["n": "\(gate)"]),
                   text: store.t("flashLockedWhy",
                                 "You know {known} so far — {left} to go. Every card you say you knew in an open deck counts, and the decks page says which are open.",
                                 ["known": "\(store.words)", "left": "\(gate - store.words)"]))
        } else if run.deck.cards.isEmpty {
            notice(title: name(run.deck),
                   text: store.t("flashEditNone", "Nothing in this deck yet. The first word goes below."))
            if run.deck.own == true {
                Button { editing = true } label: {
                    Text(store.t("flashEdit", "Edit the words")).fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.prominent)
                .controlSize(.large)
            }
        } else if run.gated {
            notice(title: store.t("flashFirstTitle", "The rest of the deck needs an account"),
                   text: store.t("flashFirstWhy",
                                 "Flashcards only work if something remembers which ones you knew — that is what brings a word back tomorrow, and again next week."))
            Button { signingIn = true } label: {
                Text(store.t("accountSignIn", "Sign in")).fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.prominent)
            .controlSize(.large)
        } else if let card = run.current {
            // The front door's one line, over a stranger's first card, gone
            // once a card has been answered.
            if !store.been && run.deck.id == WordsTab.firstDeck {
                Text(store.t("flashHelloFirst", "Estonian, one card at a time. Here’s the first."))
                    .font(.title3)
                    .foregroundStyle(Theme.ink)
            }
            study(run, card)
        } else if run.queue.isEmpty {
            rested(run)
        } else {
            done(run)
        }
    }

    private func notice(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
            Text(text).foregroundStyle(Theme.muted)
        }
        .card()
    }

    // MARK: A card

    @ViewBuilder
    private func study(_ run: Run, _ card: Card) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(store.t("flashAt", "{at} / {n}", ["at": "\(run.at + 1)", "n": "\(run.queue.count)"]))
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.muted)
                ProgressView(value: Double(run.at), total: Double(max(run.queue.count, 1)))
                    .tint(Theme.accent)
            }
            HStack {
                tally(run.again, store.t("flashLearning", "Still learning"), Theme.again, leading: true)
                Spacer()
                tally(run.knew, store.t("flashKnow", "Know"), Theme.knew, leading: false)
            }
        }

        face(run, card)
            .offset(x: lean)
            .rotationEffect(.degrees(Double(lean) / 22))
            .opacity(flying ? 0 : 1)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) { run.turned.toggle() }
            }
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { lean = $0.translation.width }
                    .onEnded { end in
                        if abs(end.translation.width) > 90 {
                            answer(run, card, knew: end.translation.width > 0)
                        } else {
                            withAnimation(.spring(duration: 0.25)) { lean = 0 }
                        }
                    }
            )
            .accessibilityAddTraits(.isButton)

        if run.turned {
            HStack(spacing: 12) {
                Button { answer(run, card, knew: false) } label: {
                    Text(store.t("flashAgain", "Show me again"))
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.again)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
                }
                Button { answer(run, card, knew: true) } label: {
                    Text(store.t("flashKnew", "Knew it"))
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.dark ? Theme.paper : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.knew, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .buttonStyle(.plain)
            .disabled(flying)
        }

        // Only what the site ships can be said aloud: the voice reads the
        // site's own file and nothing anybody typed.
        if card.shipped {
            HStack(spacing: 18) {
                if run.turned {
                    Speaker(text: card.front, label: store.t("flashSayWord", "The word"))
                    if let sentence = card.sentence, !sentence.et.isEmpty {
                        Speaker(text: sentence.et, label: store.t("flashSaySentence", "The sentence"))
                    }
                } else {
                    Speaker(text: card.front, label: store.t("flashSay", "Hear it"))
                }
            }
            .frame(maxWidth: .infinity)
        }

        VStack(spacing: 12) {
            if !run.turned && !run.hint && !Run.hint(store.means(card.back)).isEmpty {
                quiet(store.t("flashHint", "Give me a hint")) {
                    withAnimation { run.hint = true }
                }
            }
            if run.canUndo {
                quiet(store.t("flashUndo", "Undo")) {
                    withAnimation { run.undo(store: store) }
                }
            }
            if run.turned && card.shipped {
                let mine = (card.deck ?? run.deck.id) + "/" + card.id
                if reported.contains(mine) {
                    Text(store.t("flashWrongDone", "Reported. Thank you"))
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                } else {
                    quiet(store.t("flashWrong", "Something is wrong here")) {
                        Task { await report(card, in: run.deck.id, as: mine) }
                    }
                }
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(Theme.again)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tally(_ count: Int, _ label: String, _ colour: Color, leading: Bool) -> some View {
        HStack(spacing: 6) {
            if !leading { Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted) }
            Text("\(count)").font(.title3.weight(.bold)).foregroundStyle(colour)
            if leading { Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted) }
        }
    }

    /// One of the quiet presses under the card: underlined words, no box.
    private func quiet(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.medium)).underline().foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
    }

    /// The card itself, front or back.
    private func face(_ run: Run, _ card: Card) -> some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            if run.turned {
                if card.forms == nil {
                    Text(card.front).font(.headline).foregroundStyle(Theme.muted)
                }
                Text(store.means(card.back))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if let forms = card.forms {
                    Text(([card.front] + forms).joined(separator: " · "))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
                if let build = card.build { made(build) }
                if let sentence = card.sentence, !sentence.et.isEmpty {
                    VStack(spacing: 3) {
                        Text(sentence.et).font(.callout.weight(.semibold)).foregroundStyle(Theme.ink)
                        Text(store.means(sentence)).font(.footnote).foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 8)
                }
            } else {
                Text(card.front)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.5)
                if run.hint {
                    Text(Run.hint(store.means(card.back)))
                        .font(.title3.monospaced())
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
            Text(run.turned ? store.t("flashTurned", "Did you know it?") : store.t("flashTurn", "Tap to turn it over"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 320)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(lean == 0 ? Theme.hairline : (lean > 0 ? Theme.knew : Theme.again),
                                                          lineWidth: lean == 0 ? 1 : 2))
        .shadow(color: .black.opacity(Theme.dark ? 0.3 : 0.1), radius: 12, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    /// How a case form is made: the three forms, then stem + ending → form,
    /// and the name of the case.
    @ViewBuilder
    private func made(_ build: Build) -> some View {
        VStack(spacing: 3) {
            if let forms = build.forms {
                Text(forms.joined(separator: " · ")).font(.callout.weight(.medium)).foregroundStyle(Theme.accent)
            }
            if let from = build.from, let end = build.end, let makes = build.makes {
                let short = build.short.map { " = " + $0 } ?? ""
                (Text(from + " + ") + Text(end).fontWeight(.bold) + Text(" → " + makes + short))
                    .font(.callout)
                    .foregroundStyle(Theme.ink)
            }
            if let named = build.case {
                Text("\(named.et) · \(store.means(named))").font(.footnote).foregroundStyle(Theme.muted)
            }
        }
    }

    /// An answer: the card leaves to the side it was answered on, and the
    /// next one is there when it has gone.
    private func answer(_ run: Run, _ card: Card, knew: Bool) {
        guard !flying else { return }
        flying = true
        problem = nil
        Voice.shared.hush()
        withAnimation(.easeIn(duration: 0.2)) { lean = knew ? 420 : -420 }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            run.mark(card, knew: knew, store: store)
            lean = 0
            flying = false
            if run.current == nil { run.flush(store) }
        }
    }

    private func report(_ card: Card, in deck: String, as key: String) async {
        do {
            try await store.report(deck: card.deck ?? deck, card: card.id)
            reported.insert(key)
            problem = nil
        } catch {
            problem = store.say(error)
        }
    }

    // MARK: The two ends

    /// Nothing is due: every card in the deck is known.
    @ViewBuilder
    private func rested(_ run: Run) -> some View {
        score(run)
        Text(store.t("flashNothingDue",
                     "You know every card in this deck. A card you have got right stays known — go through them again whenever you like."))
            .foregroundStyle(Theme.muted)
        Button { run.start(all: true) } label: {
            Text(store.t("flashAnyway", "Go through it anyway")).fontWeight(.semibold).frame(maxWidth: .infinity)
        }
        .buttonStyle(.prominent)
        .controlSize(.large)
    }

    @ViewBuilder
    private func done(_ run: Run) -> some View {
        let all = run.deck.cards.count
        let mine = run.knownCount
        score(run)
        Text(mine >= all
             ? store.t("flashAllKnown", "You knew every card in this deck.")
             : store.t("flashSomeLeft", "{n} still to learn. They come round first next time.", ["n": "\(all - mine)"]))
            .foregroundStyle(Theme.muted)
        ForEach(opened(run), id: \.self) { stage in
            Text(store.t("flashOpened", "{stage} is open now.", ["stage": stage]))
                .fontWeight(.semibold)
                .foregroundStyle(Theme.knew)
        }
        Button { run.start(all: true) } label: {
            Text(store.t("flashGoAgain", "Go through it again")).fontWeight(.semibold).frame(maxWidth: .infinity)
        }
        .buttonStyle(.prominent)
        .controlSize(.large)
        if store.signedIn && store.ready && run.deck.review != true && (mine > 0 || run.deck.missed == true) {
            Button(role: .destructive) {
                Task { await forget(run) }
            } label: {
                Text(store.t("flashForget", "Forget what I know")).frame(maxWidth: .infinity)
            }
            .tint(Theme.again)
        }
        if let problem {
            Text(problem).font(.footnote).foregroundStyle(Theme.again)
        }
    }

    private func score(_ run: Run) -> some View {
        Text(store.t("flashKnownOf", "{known} / {n}", ["known": "\(run.knownCount)", "n": "\(run.deck.cards.count)"]))
            .font(.system(size: 44, weight: .heavy).monospacedDigit())
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }

    /// The stages this run opened: the count stood under the gate when it
    /// began and stands at or over it now.
    private func opened(_ run: Run) -> [String] {
        let stages = [("more", "flashLevelMore", "Getting by"), ("deep", "flashLevelDeep", "Going deeper")]
        return stages.compactMap { (stage: (String, String, String)) -> String? in
            let (level, key, english) = stage
            guard store.ready, let gate = store.gates[level], run.wordsAtStart < gate, store.words >= gate else { return nil }
            return store.t(key, english)
        }
    }

    private func forget(_ run: Run) async {
        do {
            try await store.reset(run.deck.id)
            await store.refresh()
            // The deck of what was missed is empty now, so there is nothing
            // here to go through again.
            if run.deck.missed == true { dismiss() } else { run.forgetAll() }
        } catch {
            problem = store.say(error)
        }
    }
}
