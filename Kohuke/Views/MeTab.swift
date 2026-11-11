import SwiftUI

/// Who is signed in, and the three choices the app keeps on the phone: the
/// language the cards are turned over into, the colour, and nothing else.
///
/// The language is one of the three the decks are written in — English,
/// Azerbaijani, Russian — and the list comes from the site with every
/// answer, so a fourth added there appears here without a release. The
/// colours are the website's four styles.
struct MeTab: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var signingIn = LaunchScript.sheet == "signin"
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            Form {
                account

                Section(store.t("language", "Language")) {
                    Picker(store.t("appReadIn", "I read in"), selection: Binding(
                        get: { store.lang },
                        set: { code in Task { await store.choose(language: code) } }
                    )) {
                        ForEach(store.languages) { Text($0.name).tag($0.code) }
                    }
                    .foregroundStyle(Theme.ink)
                }
                .listRowBackground(Theme.card)

                Section(store.t("styleLabel", "Colour")) {
                    HStack(spacing: 14) {
                        ForEach(Style.allCases) { style in
                            let key = style.nameKey
                            Button { StyleStore.shared.choose(style) } label: {
                                Swatch(style: style, selected: StyleStore.shared.style == style)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(store.t(key.0, key.1))
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    link(store.t("appOnTheWeb", "The flashcards on the web"), "safari", API.site)
                    link(store.t("privacyLink", "Privacy"), "hand.raised", API.privacy)
                    if store.signedIn {
                        Button(store.t("accountDelete", "Delete account"), role: .destructive) { deleting = true }
                    }
                } footer: {
                    Text(version)
                }
                .listRowBackground(Theme.card)
            }
            .paperBackground()
            .navigationTitle(store.t("appTabMe", "Me"))
            .sheet(isPresented: $signingIn) { SignInView() }
            .sheet(isPresented: $deleting) { DeleteAccountView() }
        }
    }

    @ViewBuilder
    private var account: some View {
        if let user = store.user {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.t("accountSignedIn", "Signed in as {name}", ["name": user]))
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(store.t("flashLearned", "You know {n} Estonian words.", ["n": "\(store.words)"]))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                Button(store.t("accountSignOut", "Sign out")) { Task { await store.signOut() } }
            }
            .listRowBackground(Theme.card)
        } else if store.checked {
            Section {
                VStack(alignment: .leading, spacing: 10) {
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
                .padding(.vertical, 4)
            }
            .listRowBackground(Theme.wash)
        }
    }

    private func link(_ title: String, _ icon: String, _ url: URL) -> some View {
        Button { openURL(url) } label: {
            HStack {
                Label(title, systemImage: icon).foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(Theme.muted)
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "Kohuke \(v) (\(b))"
    }
}

/// One of the four styles as the website draws its swatch: the style's own
/// ground with its accent in the middle, and a ring when it is the one in use.
struct Swatch: View {
    let style: Style
    let selected: Bool

    var body: some View {
        let palette = style.palette
        Circle()
            .fill(palette.paper)
            .overlay(Circle().fill(palette.accent).padding(7))
            .overlay(Circle().stroke(selected ? Theme.ink : Theme.hairline, lineWidth: selected ? 2.5 : 1))
            .frame(width: 32, height: 32)
            // A finger is wider than the swatch.
            .padding(.vertical, 6)
            .contentShape(Rectangle())
    }
}

/// Deleting the account, which App Review asks every app that makes accounts
/// to offer. The site asks for the password once more before it does it. The
/// account is the website's, so what goes is everything under that name
/// there too, and the sheet says so in the site's own words.
struct DeleteAccountView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var working = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(store.t("accountDeleteWhy",
                                 "This takes {name} off the site: your saves, your lists, your page and your decks. Numbers about visits stay, with no name on them.",
                                 ["name": store.user ?? ""]))
                        .foregroundStyle(Theme.ink)
                    Text(store.t("accountDeleteCosts", "There is no undo. Links to your profile and lists stop working straight away."))
                        .foregroundStyle(Theme.ink)
                }
                Section {
                    SecureField(store.t("accountCurrentPassword", "Current password"), text: $confirmation)
                        .textContentType(.password)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("appDeleteNoPassword", "An account made with Google or Apple and no password: type your username instead."))
                        if let problem { Text(problem).foregroundStyle(Theme.again) }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        Task { await go() }
                    } label: {
                        HStack {
                            Text(store.t("accountDeleteGo", "Delete for good")).fontWeight(.semibold)
                            if working { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(confirmation.isEmpty || working)
                }
            }
            .paperBackground()
            .navigationTitle(store.t("accountDelete", "Delete account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("close", "Close")) { dismiss() } }
            }
        }
        .tint(Theme.accent)
    }

    private func go() async {
        working = true
        defer { working = false }
        do {
            try await store.deleteAccount(confirmation: confirmation)
            dismiss()
        } catch {
            problem = store.say(error)
        }
    }
}
