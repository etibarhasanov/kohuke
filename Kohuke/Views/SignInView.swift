import SwiftUI

/// Signing in, or making an account: Apple or Google where the site offers
/// them, or a username and a password, the same two fields the website asks
/// for and nothing more. The account is the website's, so one made on
/// tallinntastebuds.ee signs in here and one made here signs in there.
struct SignInView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// What the sheet was opened for, said over the form: "Sign in to save this list".
    var reason: String?

    @State private var creating = false
    @State private var username = ""
    @State private var password = ""
    @State private var working = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                if let reason {
                    Section { Text(reason).font(.subheadline).foregroundStyle(Theme.ink) }
                        .listRowBackground(Theme.wash)
                }
                if store.appleOffered || store.googleOffered {
                    Section {
                        VStack(spacing: 10) {
                            if store.appleOffered {
                                Button { Task { await social(apple: true) } } label: {
                                    door(store.t("appApple", "Continue with Apple")) {
                                        Image(systemName: "apple.logo").font(.system(size: 19, weight: .medium))
                                    }
                                    // Apple's own button: black by day, white by night.
                                    .foregroundStyle(Theme.dark ? Color.black : Color.white)
                                    .background(Theme.dark ? Color.white : Color.black,
                                                in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            if store.googleOffered {
                                Button { Task { await social(apple: false) } } label: {
                                    door(store.t("accountGoogle", "Continue with Google")) {
                                        Image("GoogleMark").resizable().frame(width: 18, height: 18)
                                    }
                                    // Google's: its mark on white, in both.
                                    .foregroundStyle(Color(hex: 0x1F1F1F))
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x747775), lineWidth: 1))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(working)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } footer: {
                        Text(store.t("accountOr", "or"))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 6)
                    }
                }
                Section {
                    Picker("", selection: $creating) {
                        Text(store.t("accountSignIn", "Sign in")).tag(false)
                        Text(store.t("accountCreate", "Create account")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    TextField(store.t("accountUsername", "Username"), text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(store.t("accountPassword", "Password"), text: $password)
                        .textContentType(creating ? .newPassword : .password)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if creating {
                            Text(store.t("accountUsernameHint", "3–24 letters or numbers."))
                            Text(store.t("appNoReset", "There’s no reset — let your iPhone save the password."))
                        }
                        if let problem {
                            Text(problem).foregroundStyle(Theme.accent).padding(.top, 2)
                        }
                    }
                }
                Section {
                    Button {
                        Task { await go() }
                    } label: {
                        HStack {
                            Spacer()
                            if working { ProgressView().tint(Theme.onAccent) }
                            Text(creating ? store.t("accountCreate", "Create account") : store.t("accountSignIn", "Sign in"))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(working || username.isEmpty || password.isEmpty)
                    .listRowBackground(Theme.accent.opacity(working || username.isEmpty || password.isEmpty ? 0.45 : 1))
                    .foregroundStyle(Theme.onAccent)
                } footer: {
                    // Only where the Google button is not there to press.
                    if !store.googleOffered {
                        Text(store.t("appGoogleOnSite", "Made your account with Google? Set a password for it on tallinntastebuds.ee, under your account, and sign in here with that."))
                    }
                }
            }
            .paperBackground()
            .navigationTitle(creating ? store.t("accountCreate", "Create account") : store.t("accountSignIn", "Sign in"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("close", "Close")) { dismiss() }
                }
            }
            .onChange(of: creating) { _, _ in problem = nil }
        }
        // Said here as well as at the root: this sheet is opened from many
        // screens, and its Close must be the style's accent from all of them.
        .tint(Theme.accent)
    }

    /// One of the two buttons: its mark, then its words, centred as a pair.
    private func door<Logo: View>(_ title: String, @ViewBuilder mark: () -> Logo) -> some View {
        HStack(spacing: 8) {
            mark()
            Text(title).font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .contentShape(Rectangle())
    }

    private func social(apple: Bool) async {
        working = true
        problem = nil
        defer { working = false }
        do {
            if apple {
                try await store.enterWithApple()
            } else {
                try await store.enterWithGoogle()
            }
            dismiss()
        } catch is SocialSignIn.Cancelled {
            // Changing your mind is not an error.
        } catch {
            problem = store.say(error)
        }
    }

    private func go() async {
        working = true
        problem = nil
        defer { working = false }
        do {
            try await store.enter(username: username.trimmingCharacters(in: .whitespaces),
                                  password: password, create: creating)
            dismiss()
        } catch {
            problem = store.say(error)
        }
    }
}
