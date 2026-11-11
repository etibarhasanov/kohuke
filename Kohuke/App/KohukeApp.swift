import SwiftUI

/// Kohuke: Estonian, one card at a time.
///
/// The flashcards of Tallinn Tastebuds as an app of their own — the decks,
/// the grammar, the songs and the conversations of
/// `tallinntastebuds.ee/flashcard`, for people who read English, Azerbaijani
/// or Russian. It has no server: `Core/API.swift` says what it asks the
/// website for, and an account here is an account there.
@main
struct KohukeApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { await arrive() }
        }
        .onChange(of: phase) { _, now in
            // Coming back to the app is when a deck added on the website,
            // or a card answered there, should show up.
            if now == .active { Task { await arrive() } }
        }
    }

    /// Who this is and what is on the shelf, asked side by side.
    private func arrive() async {
        async let who: Void = store.whoAmI()
        async let shelf: Void = store.refresh()
        _ = await (who, shelf)
    }
}

/// The five tabs: the four shelves, and Me.
struct RootView: View {
    @Environment(Store.self) private var store
    @State private var tab = LaunchScript.tab

    var body: some View {
        TabView(selection: $tab) {
            WordsTab()
                .tabItem { Label(store.t("flashPartWords", "Words"), systemImage: "rectangle.on.rectangle.angled") }
                .tag(0)
            GrammarTab()
                .tabItem { Label(store.t("flashGrammar", "Grammar"), systemImage: "text.book.closed") }
                .tag(1)
            SongsTab()
                .tabItem { Label(store.t("flashSongs", "Songs"), systemImage: "music.note") }
                .tag(2)
            TalksTab()
                .tabItem { Label(store.t("flashTalks", "Conversations"), systemImage: "bubble.left.and.bubble.right") }
                .tag(3)
            MeTab()
                .tabItem { Label(store.t("appTabMe", "Me"), systemImage: "person.crop.circle") }
                .tag(4)
        }
        // The one line said when the voice does not answer, over whichever
        // screen asked for it, and gone by itself.
        .overlay(alignment: .bottom) {
            if Voice.shared.failed {
                Text(store.t("flashSayFail", "The voice isn’t answering just now. Try again in a moment."))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.ink, in: Capsule())
                    .padding(.bottom, 64)
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation { Voice.shared.failed = false }
                    }
            }
        }
        // The style chosen under Me: its accent on every control, and the
        // system's own dark drawing for the two night styles, so the bars
        // and the keyboard go dark with the page. Last, so the sheets above
        // are inside it.
        .tint(Theme.accent)
        .preferredColorScheme(Theme.dark ? .dark : .light)
    }
}
