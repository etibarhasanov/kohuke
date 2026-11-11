import SwiftUI

/// The words of a deck of your own: add one, change one, remove one, rename
/// the deck, delete it.
///
/// Estonian on the front, what it means on the back, and nobody else can
/// read it. Every write answers the deck whole, and the editor redraws from
/// that rather than patching the row it just changed. The two lengths are
/// the route's `MAX_NAME` and `MAX_SIDE`, restated here so a field stops
/// somebody at the keystroke rather than at the round trip.
struct DeckEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var deck: Deck
    let changed: (Deck) -> Void
    let dropped: () -> Void

    @State private var name: String
    @State private var front = ""
    @State private var back = ""
    /// The card being changed, where the two fields are not for a new one.
    @State private var editing: String?
    @State private var working = false
    @State private var problem: String?
    @State private var sure = false

    private static let maxName = 60
    private static let maxSide = 60

    init(deck: Deck, changed: @escaping (Deck) -> Void, dropped: @escaping () -> Void) {
        _deck = State(initialValue: deck)
        _name = State(initialValue: deck.name?.in("en") ?? "")
        self.changed = changed
        self.dropped = dropped
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(store.t("flashNewDeck", "A new deck"), text: $name)
                        .onChange(of: name) { _, now in name = String(now.prefix(Self.maxName)) }
                        .onSubmit { Task { await rename() } }
                        .submitLabel(.done)
                } footer: {
                    Text(store.t("flashEditWhy", "Estonian on the front, what it means on the back. Nobody else can read this deck."))
                }

                Section {
                    TextField(store.t("flashFront", "Estonian"), text: $front,
                              prompt: Text(store.t("flashFrontHint", "Rukkileib")))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: front) { _, now in front = String(now.prefix(Self.maxSide)) }
                    TextField(store.t("flashBack", "What it means"), text: $back,
                              prompt: Text(store.t("flashBackHint", "Rye bread")))
                        .onChange(of: back) { _, now in back = String(now.prefix(Self.maxSide)) }
                    Button(editing == nil ? store.t("flashAdd", "Add the card") : store.t("flashSaveCard", "Save the card")) {
                        Task { await save() }
                    }
                    .disabled(working || front.trimmingCharacters(in: .whitespaces).isEmpty
                              || back.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editing != nil {
                        Button(store.t("flashCancelEdit", "Cancel")) { clear() }
                    }
                } footer: {
                    if let problem { Text(problem).foregroundStyle(Theme.again) }
                }

                Section {
                    if deck.cards.isEmpty {
                        Text(store.t("flashEditNone", "Nothing in this deck yet. The first word goes below."))
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(deck.cards) { card in
                        Button {
                            editing = card.id
                            front = card.front
                            back = card.back.in(store.lang)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.front).fontWeight(.semibold).foregroundStyle(Theme.ink)
                                Text(card.back.in(store.lang)).font(.footnote).foregroundStyle(Theme.muted)
                            }
                        }
                        .swipeActions {
                            Button(store.t("flashRemove", "Remove"), role: .destructive) {
                                Task { await send(["action": "uncard", "card": card.id]) }
                            }
                        }
                    }
                }

                Section {
                    Button(store.t("flashDropDeck", "Delete this deck"), role: .destructive) { sure = true }
                }
            }
            .paperBackground()
            .navigationTitle(store.t("flashEdit", "Edit the words"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("flashDone", "Done editing")) {
                        Task {
                            await rename()
                            dismiss()
                        }
                    }
                }
            }
            .confirmationDialog(store.t("flashDropSure", "Delete this deck and every word in it? This cannot be undone."),
                                isPresented: $sure, titleVisibility: .visible) {
                Button(store.t("flashDropDeck", "Delete this deck"), role: .destructive) {
                    Task { await drop() }
                }
            }
        }
        .tint(Theme.accent)
    }

    private func clear() {
        editing = nil
        front = ""
        back = ""
        problem = nil
    }

    private func save() async {
        var body: [String: Any] = ["front": front, "back": back]
        if let editing {
            body["action"] = "editcard"
            body["card"] = editing
        } else {
            body["action"] = "card"
        }
        if await send(body) { clear() }
    }

    private func rename() async {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty, wanted != deck.name?.in("en") else { return }
        await send(["action": "rename", "name": wanted])
    }

    /// One write to this deck, and the deck redrawn from what came back.
    @discardableResult
    private func send(_ fields: [String: Any]) async -> Bool {
        working = true
        defer { working = false }
        var body = fields
        body["deck"] = deck.id
        do {
            if let next = try await store.write(body) {
                deck = next
                changed(next)
            }
            problem = nil
            return true
        } catch {
            problem = store.say(error)
            return false
        }
    }

    private func drop() async {
        do {
            _ = try await store.write(["action": "drop", "deck": deck.id])
            await store.refresh()
            dropped()
        } catch {
            problem = store.say(error)
        }
    }
}
